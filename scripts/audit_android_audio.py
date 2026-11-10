#!/usr/bin/env python3
"""Check the Android audio payload and preserve exact installed-NDK notices.

The APK/ELF/DEX readers use only Python's standard library. They never load an
APK library. To account for AGP's stripping, a runtime that differs from the
installed libc++ is compared to a temporary copy produced by that same pinned
NDK's llvm-strip --strip-unneeded. No APK content is passed to an executable.

Passing these checks supplies packaging evidence, not a license determination,
source-to-binary reproducibility claim, signing review, or release approval.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import zipfile
import zlib


NDK_VERSION = "28.2.13676358"
NDK_HOST = "linux-x86_64"
PAGE_SIZE = 16384
MAX_MEMBER_BYTES = 256 * 1024 * 1024
DSP_LIBRARY = "libcrisper_audio_dsp.so"
RUNTIME_LIBRARY = "libc++_shared.so"
NOTICE_ASSET = "assets/flutter_assets/assets/licenses/ANDROID-NDK.txt"
NDK_NOTICES = ("NOTICE", "NOTICE.toolchain")
ABI_FORMATS = {
    "arm64-v8a": (2, 183, "aarch64-linux-android"),
    "x86_64": (2, 62, "x86_64-linux-android"),
    "armeabi-v7a": (1, 40, "arm-linux-androideabi"),
    "x86": (1, 3, "i686-linux-android"),
}
JNI_CLASS = "Lcom/ryanheise/just_audio/JniCrisperDspEngine;"
JNI_PREFIX = "Java_com_ryanheise_just_1audio_JniCrisperDspEngine_"
JNI_METHODS = {
    "create": "(IIID)J",
    "destroy": "(J)V",
    "write": "(JLjava/nio/ByteBuffer;II)I",
    "read": "(JLjava/nio/ByteBuffer;I)I",
    "finish": "(J)V",
    "ended": "(J)Z",
    "sourceFrames": "(J)J",
    "outputFrames": "(J)J",
}
LIMITATIONS = [
    "Packaging checks do not approve a release or change any license-review status.",
    "NDK aggregate notices include build tools that are not necessarily shipped in the app.",
    "Matching libc++ bytes identifies the installed runtime; it does not prove all statically linked source provenance.",
    "This does not exercise ExoPlayer, AudioTrack, hardware, an AAB, or store signing and delivery.",
]


class AuditError(ValueError):
    """Incomplete, malformed, or unexpected packaging evidence."""


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_bounded(path: Path, maximum: int = MAX_MEMBER_BYTES) -> bytes:
    if path.stat().st_size > maximum:
        raise AuditError(f"File is too large to inspect: {path.name}")
    return path.read_bytes()


def region(data: bytes, offset: int, size: int, label: str) -> bytes:
    if offset < 0 or size < 0 or offset > len(data) - size:
        raise AuditError(f"Truncated or out-of-range {label}")
    return data[offset:offset + size]


def unpack(fmt: str, data: bytes, offset: int, label: str) -> tuple:
    return struct.unpack(fmt, region(data, offset, struct.calcsize(fmt), label))


def c_string(data: bytes, offset: int, label: str) -> str:
    if offset < 0 or offset >= len(data):
        raise AuditError(f"Out-of-range {label} string")
    end = data.find(b"\0", offset)
    if end < 0:
        raise AuditError(f"Unterminated {label} string")
    # DEX uses modified UTF-8. Every name/type relevant to this JNI contract is
    # ASCII; unrelated strings need not be decoded as Java text.
    return data[offset:end].decode("utf-8", errors="replace")


def collect_ndk_notices(ndk: Path) -> tuple[bytes, dict, dict[str, bytes]]:
    properties = read_bounded(ndk / "source.properties", 65536)
    revisions = re.findall(rb"(?m)^Pkg\.Revision\s*=\s*([^\r\n]+)", properties)
    if revisions != [NDK_VERSION.encode()]:
        raise AuditError(f"Expected installed NDK {NDK_VERSION} in source.properties")
    sources = {}
    records = []
    for name in NDK_NOTICES:
        content = read_bounded(ndk / name, 16 * 1024 * 1024)
        if not content.strip():
            raise AuditError(f"Installed NDK {name} is empty")
        # Flutter's license registry loads this as text; retain original bytes.
        content.decode("utf-8")
        sources[name] = content
        records.append({"path": name, "sha256": digest(content), "size_bytes": len(content)})
    header = (
        "Android NDK runtime and toolchain notices\n"
        f"Installed NDK revision: {NDK_VERSION}\n"
        f"source.properties SHA-256: {digest(properties)}\n\n"
        "Generated from the exact installed NDK by scripts/audit_android_audio.py.\n"
        "The app uses the NDK C++ shared runtime (libc++_shared.so). The complete\n"
        "upstream aggregate notices below also cover development tools and other\n"
        "NDK components, not all of which are shipped in this application. Their\n"
        "inclusion is not a statement that those tools are linked into the app,\n"
        "nor a license or App Store approval. Artifact evidence separately records\n"
        "the packaged runtime bytes and their comparison with this installed NDK.\n"
    ).encode()
    pieces = [header]
    for record in records:
        pieces.extend([
            (f"\n===== BEGIN NDK {record['path']} =====\n"
             f"Original bytes: {record['size_bytes']}; SHA-256: {record['sha256']}\n\n").encode(),
            sources[record["path"]],
            f"\n===== END NDK {record['path']} =====\n".encode(),
        ])
    asset = b"".join(pieces)
    report = {
        "revision": NDK_VERSION,
        "source_properties_sha256": digest(properties),
        "notice_sources": records,
        "notice_asset": {"apk_path": NOTICE_ASSET, "sha256": digest(asset), "size_bytes": len(asset)},
    }
    sources["source.properties"] = properties
    return asset, report, sources


def prepare_notices(ndk: Path, asset: Path, output: Path) -> dict:
    payload, ndk_report, sources = collect_ndk_notices(ndk)
    asset.parent.mkdir(parents=True, exist_ok=True)
    asset.write_bytes(payload)
    evidence = output.parent / "ndk-notices"
    evidence.mkdir(parents=True, exist_ok=True)
    for name, content in sources.items():
        (evidence / name).write_bytes(content)
    (evidence / "ANDROID-NDK.txt").write_bytes(payload)
    report = {
        "schema_version": 1,
        "action": "prepare_notices",
        "ndk": ndk_report,
        "packaged_asset_verified": False,
        "release_approved": False,
        "limitations": LIMITATIONS,
    }
    write_report(output, report)
    return report


def inspect_elf(data: bytes, abi: str) -> dict:
    expected_class, expected_machine, _ = ABI_FORMATS[abi]
    ident = region(data, 0, 16, "ELF identification")
    if ident[:4] != b"\x7fELF" or ident[4] != expected_class or ident[5:7] != b"\x01\x01":
        raise AuditError(f"Expected little-endian ELF class {expected_class} for {abi}")
    is64 = expected_class == 2
    fmt = "<16sHHIQQQIHHHHHH" if is64 else "<16sHHIIIIIHHHHHH"
    header = unpack(fmt, data, 0, "ELF header")
    if header[1:4] != (3, expected_machine, 1):
        raise AuditError(f"Expected ET_DYN ELF machine {expected_machine} for {abi}")
    phoff, shoff = header[5:7]
    ehsize, phsize, phnum, shsize, shnum = header[8:13]
    phfmt = "<IIQQQQQQ" if is64 else "<IIIIIIII"
    shfmt = "<IIQQQQIIQQ" if is64 else "<IIIIIIIIII"
    if ehsize != struct.calcsize(fmt) or phsize != struct.calcsize(phfmt) or not 0 < phnum < 65535:
        raise AuditError("Unsupported ELF program header layout")
    region(data, phoff, phsize * phnum, "ELF program table")
    loads, dynamics = [], []
    for index in range(phnum):
        values = unpack(phfmt, data, phoff + index * phsize, "ELF program header")
        if is64:
            kind, flags, offset, address, _, file_size, memory_size, alignment = values
        else:
            kind, offset, address, _, file_size, memory_size, flags, alignment = values
        region(data, offset, file_size, "ELF segment")
        if kind == 1:
            if memory_size < file_size or not alignment or alignment & (alignment - 1):
                raise AuditError("Invalid ELF PT_LOAD size or alignment")
            if address % alignment != offset % alignment:
                raise AuditError("ELF PT_LOAD address and offset are not congruent")
            if is64 and (alignment < PAGE_SIZE or address % PAGE_SIZE != offset % PAGE_SIZE):
                raise AuditError("64-bit ELF PT_LOAD does not support 16 KB pages")
            loads.append({"offset": offset, "virtual_address": address, "file_size": file_size,
                          "memory_size": memory_size, "alignment": alignment, "flags": flags})
        elif kind == 2:
            dynamics.append((offset, address, file_size))
    if not loads or len(dynamics) != 1:
        raise AuditError("Expected ELF PT_LOAD and one PT_DYNAMIC segment")

    def virtual_offset(address: int, length: int) -> int:
        for load in loads:
            delta = address - load["virtual_address"]
            if 0 <= delta <= load["file_size"] - length:
                return load["offset"] + delta
        raise AuditError("ELF dynamic data is outside file-backed PT_LOAD segments")

    def virtual_bytes(address: int, length: int) -> bytes:
        return region(data, virtual_offset(address, length), length, "ELF dynamic data")

    dynfmt = "<qQ" if is64 else "<iI"
    dynsize = struct.calcsize(dynfmt)
    dynamic = {}
    offset, address, size = dynamics[0]
    if virtual_offset(address, size) != offset:
        raise AuditError("ELF PT_DYNAMIC file offset disagrees with its loaded virtual address")
    if size % dynsize:
        raise AuditError("Invalid ELF PT_DYNAMIC size")
    terminated = False
    for position in range(offset, offset + size, dynsize):
        tag, value = unpack(dynfmt, data, position, "ELF dynamic entry")
        if tag == 0:
            terminated = True
            break
        dynamic.setdefault(tag, []).append(value)
    if not terminated or any(len(dynamic.get(tag, [])) != 1 for tag in (5, 6, 10, 11)):
        raise AuditError("Incomplete ELF dynamic string/symbol-table metadata")
    strings = virtual_bytes(dynamic[5][0], dynamic[10][0])
    needed = [c_string(strings, value, "DT_NEEDED") for value in dynamic.get(1, [])]
    sonames = [c_string(strings, value, "DT_SONAME") for value in dynamic.get(14, [])]
    if len(sonames) > 1:
        raise AuditError("Ambiguous ELF DT_SONAME")

    if shsize != struct.calcsize(shfmt) or not shnum:
        raise AuditError("Missing or unsupported ELF section table for dynamic-symbol evidence")
    region(data, shoff, shsize * shnum, "ELF section table")
    sections = [unpack(shfmt, data, shoff + index * shsize, "ELF section") for index in range(shnum)]
    exports = {}
    symbol_names = []
    dynsym_count = 0
    for section in sections:
        if section[1] != 11:  # SHT_DYNSYM remains present after ordinary stripping.
            continue
        dynsym_count += 1
        _, _, _, _, offset, size, link, _, _, entry_size = section
        symfmt = "<IBBHQQ" if is64 else "<IIIBBH"
        if entry_size != struct.calcsize(symfmt) or size % entry_size or link >= len(sections):
            raise AuditError("Invalid ELF dynamic symbol table")
        if section[3] != dynamic[6][0] or entry_size != dynamic[11][0] or virtual_offset(dynamic[6][0], size) != offset:
            raise AuditError("ELF dynamic symbol section disagrees with loader DT_SYMTAB/DT_SYMENT")
        region(data, offset, size, "ELF dynamic symbols")
        string_section = sections[link]
        if string_section[1] != 3:
            raise AuditError("ELF dynamic symbols do not link to SHT_STRTAB")
        if (string_section[3] != dynamic[5][0] or string_section[5] != dynamic[10][0]
                or string_section[4] != virtual_offset(dynamic[5][0], dynamic[10][0])):
            raise AuditError("ELF symbol strings disagree with loader DT_STRTAB/DT_STRSZ")
        symbol_strings = region(data, string_section[4], string_section[5], "ELF symbol strings")
        for position in range(offset, offset + size, entry_size):
            values = unpack(symfmt, data, position, "ELF dynamic symbol")
            name, info, other, section_index = (values[:4] if is64 else (values[0], *values[3:]))
            symbol_name = c_string(symbol_strings, name, "ELF symbol")
            symbol_names.append(symbol_name)
            if section_index and info >> 4 in (1, 2) and info & 15 == 2 and other & 3 in (0, 3):
                value, length = values[4:6] if is64 else values[1:3]
                exports[symbol_name] = (len(symbol_names) - 1, value, length)
    if dynsym_count != 1:
        raise AuditError("Expected one ELF dynamic symbol table")

    # The loader looks names up through DT_HASH/DT_GNU_HASH, not section names.
    # Require the advertised lookup tables to actually reach the JNI exports.
    hashes = []
    for tag in (4, 0x6FFFFEF5):
        addresses = dynamic.get(tag, [])
        if len(addresses) > 1:
            raise AuditError("Ambiguous ELF dynamic hash table")
        if not addresses:
            continue
        address = addresses[0]
        if tag == 4:
            buckets, chains = struct.unpack("<II", virtual_bytes(address, 8))
            if not buckets or chains != len(symbol_names):
                raise AuditError("Invalid ELF DT_HASH table")
            values = virtual_bytes(address + 8, (buckets + chains) * 4)
            hashes.append(("sysv", buckets, chains, values))
        else:
            buckets, first_symbol, bloom_count, shift = struct.unpack("<IIII", virtual_bytes(address, 16))
            if (not buckets or not bloom_count or bloom_count & (bloom_count - 1)
                    or first_symbol > len(symbol_names) or shift >= 32):
                raise AuditError("Invalid ELF DT_GNU_HASH table")
            bloom_bytes = bloom_count * (8 if is64 else 4)
            values = virtual_bytes(address + 16, bloom_bytes + buckets * 4 + (len(symbol_names) - first_symbol) * 4)
            hashes.append(("gnu", buckets, first_symbol, bloom_count, shift, bloom_bytes, values))
    if not hashes:
        raise AuditError("No ELF loader hash table for exported-symbol evidence")

    def reachable(name: str, symbol_index: int, table: tuple) -> bool:
        if table[0] == "sysv":
            _, bucket_count, chain_count, values = table
            hash_value = 0
            for byte in name.encode():
                hash_value = (hash_value << 4) + byte
                high = hash_value & 0xF0000000
                hash_value ^= high >> 24
                hash_value &= ~high
            index = unpack("<I", values, (hash_value % bucket_count) * 4, "ELF hash bucket")[0]
            visited = set()
            while index:
                if index >= chain_count or index in visited:
                    raise AuditError("Invalid or cyclic ELF DT_HASH chain")
                if index == symbol_index:
                    return True
                visited.add(index)
                index = unpack("<I", values, (bucket_count + index) * 4, "ELF hash chain")[0]
            return False
        _, bucket_count, first_symbol, bloom_count, shift, bloom_bytes, values = table
        hash_value = 5381
        for byte in name.encode():
            hash_value = (hash_value * 33 + byte) & 0xFFFFFFFF
        word_bits = 64 if is64 else 32
        bloom = unpack("<Q" if is64 else "<I", values,
                       (hash_value // word_bits % bloom_count) * (word_bits // 8), "ELF GNU bloom")[0]
        mask = (1 << (hash_value % word_bits)) | (1 << ((hash_value >> shift) % word_bits))
        if bloom & mask != mask:
            return False
        index = unpack("<I", values, bloom_bytes + (hash_value % bucket_count) * 4, "ELF GNU hash bucket")[0]
        if not index:
            return False
        while first_symbol <= index < len(symbol_names):
            value = unpack("<I", values, bloom_bytes + (bucket_count + index - first_symbol) * 4, "ELF GNU hash chain")[0]
            if value | 1 == hash_value | 1 and index == symbol_index:
                return True
            if value & 1:
                return False
            index += 1
        raise AuditError("Invalid ELF GNU hash chain")

    jni_exports = []
    for name, (index, address, length) in exports.items():
        if not name.startswith("Java_"):
            continue
        # Thumb symbols encode instruction-set selection in the low address bit.
        address = address & ~1 if abi == "armeabi-v7a" else address
        if not any(load["flags"] & 1 and 0 <= address - load["virtual_address"] <= load["file_size"] - max(1, length)
                   for load in loads):
            raise AuditError("JNI function address is outside executable file-backed PT_LOAD segments")
        if not all(reachable(name, index, table) for table in hashes):
            raise AuditError("JNI function is unreachable through an ELF loader hash table")
        jni_exports.append(name)
    return {
        "class_bits": 64 if is64 else 32, "machine": expected_machine,
        "soname": sonames[0] if sonames else None, "needed": sorted(needed), "load_segments": loads,
        "page_alignment_16kb": is64,
        "exported_function_count": len(exports),
        "symbol_lookup_tables": [table[0] for table in hashes],
        "jni_exports": sorted(jni_exports),
    }


def uleb128(data: bytes, offset: int) -> tuple[int, int]:
    result = 0
    for index in range(5):
        value = region(data, offset + index, 1, "DEX ULEB128")[0]
        if index == 4 and value > 15:
            raise AuditError("Oversized DEX ULEB128")
        result |= (value & 127) << (index * 7)
        if not value & 128:
            return result, offset + index + 1
    raise AuditError("Unterminated DEX ULEB128")


def inspect_dex(data: bytes) -> dict | None:
    header = region(data, 0, 112, "DEX header")
    if header[:8] not in {f"dex\n{version:03d}\0".encode() for version in (35, 37, 38, 39, 40)}:
        raise AuditError("Unsupported DEX format")
    if unpack("<III", header, 32, "DEX size/endian") != (len(data), 112, 0x12345678):
        raise AuditError("Invalid DEX size, header, or byte order")
    if struct.unpack_from("<I", header, 8)[0] != zlib.adler32(data[12:]) or header[12:32] != hashlib.sha1(data[32:]).digest():
        raise AuditError("DEX checksum or signature mismatch")

    def table(header_offset: int, size: int) -> tuple[int, int]:
        count, offset = unpack("<II", header, header_offset, "DEX table")
        region(data, offset, count * size, "DEX table entries")
        return count, offset

    string_count, string_offset = table(56, 4)
    type_count, type_offset = table(64, 4)
    proto_count, proto_offset = table(72, 12)
    method_count, method_offset = table(88, 8)
    class_count, class_offset = table(96, 32)

    def string(index: int) -> str:
        if not 0 <= index < string_count:
            raise AuditError("Out-of-range DEX string ID")
        position = unpack("<I", data, string_offset + index * 4, "DEX string ID")[0]
        declared_units, start = uleb128(data, position)
        end = data.find(b"\0", start)
        if end < 0:
            raise AuditError("Unterminated DEX string")
        encoded = data[start:end]
        # MUTF-8 represents NUL as C0 80 and supplementary characters as UTF-16
        # surrogate units. Check the declared UTF-16 length of the actual names
        # and type descriptors, rather than accepting stray matching text.
        if any(byte >= 0xF0 for byte in encoded):
            raise AuditError("Invalid DEX modified UTF-8 string")
        value = encoded.replace(b"\xC0\x80", b"\0").decode("utf-8", errors="surrogatepass")
        if len(value.encode("utf-16-le", errors="surrogatepass")) // 2 != declared_units:
            raise AuditError("DEX string's declared UTF-16 length differs from its bytes")
        return value

    def typename(index: int) -> str:
        if not 0 <= index < type_count:
            raise AuditError("Out-of-range DEX type ID")
        return string(unpack("<I", data, type_offset + index * 4, "DEX type ID")[0])

    def prototype(index: int) -> str:
        if not 0 <= index < proto_count:
            raise AuditError("Out-of-range DEX prototype ID")
        _, result, parameters = unpack("<III", data, proto_offset + index * 12, "DEX prototype")
        arguments = []
        if parameters:
            count = unpack("<I", data, parameters, "DEX type list")[0]
            region(data, parameters + 4, count * 2, "DEX parameter types")
            arguments = [typename(unpack("<H", data, parameters + 4 + i * 2, "DEX parameter")[0]) for i in range(count)]
        return "(" + "".join(arguments) + ")" + typename(result)

    matches = []
    for index in range(class_count):
        entry = unpack("<8I", data, class_offset + index * 32, "DEX class definition")
        if typename(entry[0]) == JNI_CLASS:
            matches.append(entry)
    if not matches:
        return None
    if len(matches) != 1 or not matches[0][6]:
        raise AuditError("JNI class has ambiguous or missing DEX class data")
    target_type = matches[0][0]
    offset = matches[0][6]
    counts = []
    for _ in range(4):
        count, offset = uleb128(data, offset)
        counts.append(count)
    if sum(counts) > len(data):
        raise AuditError("Oversized DEX class data")
    for _ in range(counts[0] + counts[1]):
        _, offset = uleb128(data, offset)
        _, offset = uleb128(data, offset)
    methods = {}
    for group, count in enumerate(counts[2:]):
        method_index = 0
        for _ in range(count):
            delta, offset = uleb128(data, offset)
            flags, offset = uleb128(data, offset)
            code_offset, offset = uleb128(data, offset)
            method_index += delta
            if method_index >= method_count:
                raise AuditError("Out-of-range DEX encoded method")
            owner, proto, name_index = unpack("<HHI", data, method_offset + method_index * 8, "DEX method ID")
            if owner != target_type:
                raise AuditError("JNI class method has a different DEX owner")
            if flags & 0x100:
                name = string(name_index)
                incompatible_flags = 0x2 | 0x4 | 0x8 | 0x400 | 0x10000
                if group != 1 or code_offset or not flags & 1 or flags & incompatible_flags or name in methods:
                    raise AuditError("JNI declaration must be a unique public instance native method in DEX virtual_methods")
                methods[name] = prototype(proto)
    if methods != JNI_METHODS:
        raise AuditError("JNI native method names/signatures changed or were removed by R8")
    return {"class": JNI_CLASS, "native_methods": methods}


def strip_ndk_runtime(source: Path, tool: Path) -> bytes:
    with tempfile.TemporaryDirectory(prefix="crisper-ndk-runtime-") as directory:
        destination = Path(directory) / RUNTIME_LIBRARY
        try:
            subprocess.run([str(tool), "--strip-unneeded", "-o", str(destination), str(source)],
                           check=True, capture_output=True, timeout=30)
        except (subprocess.SubprocessError, OSError) as error:
            raise AuditError(f"Pinned NDK llvm-strip comparison failed: {error}") from error
        return read_bounded(destination)


def compare_runtime(data: bytes, ndk: Path, abi: str) -> dict:
    toolchain = ndk / "toolchains/llvm/prebuilt" / NDK_HOST
    source = toolchain / "sysroot/usr/lib" / ABI_FORMATS[abi][2] / RUNTIME_LIBRARY
    original = read_bounded(source)
    report = {"source_path": source.relative_to(ndk).as_posix(),
              "installed_sha256": digest(original), "packaged_sha256": digest(data)}
    if data == original:
        report["match"] = "exact_installed_bytes"
        return report
    tool = toolchain / "bin/llvm-strip"
    try:
        tool.resolve(strict=True).relative_to(ndk.resolve(strict=True))
    except (OSError, ValueError) as error:
        raise AuditError("Expected llvm-strip inside the pinned installed NDK") from error
    report["strip_tool"] = {"path": tool.relative_to(ndk).as_posix(), "sha256": digest(read_bounded(tool))}
    stripped = strip_ndk_runtime(source, tool)
    report["stripped_sha256"] = digest(stripped)
    report["match"] = "exact_ndk_strip_unneeded_bytes" if data == stripped else "mismatch"
    return report


def zip_data_offset(stream, entry: zipfile.ZipInfo) -> int:
    stream.seek(entry.header_offset)
    header = stream.read(30)
    if len(header) != 30:
        raise AuditError("Truncated ZIP local header")
    signature, _, flags, compression, _, _, _, _, _, name_size, extra_size = struct.unpack("<I5H3I2H", header)
    if signature != 0x04034B50 or compression != entry.compress_type or flags & 1:
        raise AuditError("Unexpected or encrypted ZIP local header")
    name = stream.read(name_size).decode("utf-8" if flags & 0x800 else "cp437")
    if name != entry.filename or len(stream.read(extra_size)) != extra_size:
        raise AuditError("ZIP local header differs from central directory")
    return entry.header_offset + 30 + name_size + extra_size


def inspect_apk(apk: Path, ndk: Path, abis: list[str], *, source_revision: str | None = None) -> dict:
    report = {
        "schema_version": 1, "apk": {"filename": apk.name, "size_bytes": apk.stat().st_size},
        "source_revision": source_revision, "expected_abis": sorted(set(abis)),
        "libraries": [], "jni_declarations": [], "errors": [],
        "release_approved": False, "limitations": LIMITATIONS,
    }
    # Streaming hash avoids duplicating the potentially large Flutter APK.
    with apk.open("rb") as stream:
        report["apk"]["sha256"] = hashlib.file_digest(stream, "sha256").hexdigest()
    errors = report["errors"]
    try:
        expected_notice, report["ndk"], _ = collect_ndk_notices(ndk)
        system_bytes = read_bounded(ndk / "meta/system_libs.json", 1024 * 1024)
        system_libraries = json.loads(system_bytes)
        if not isinstance(system_libraries, dict) or not all(isinstance(name, str) for name in system_libraries):
            raise AuditError("Invalid installed NDK system library metadata")
        report["ndk"]["system_libs_sha256"] = digest(system_bytes)
        with zipfile.ZipFile(apk) as archive, apk.open("rb") as raw:
            duplicates = [name for name, count in Counter(item.filename for item in archive.infolist()).items() if count > 1]
            if duplicates:
                raise AuditError("Duplicate ZIP members: " + ", ".join(duplicates))
            entries = {item.filename: item for item in archive.infolist()}

            def member(entry: zipfile.ZipInfo) -> bytes:
                if entry.file_size > MAX_MEMBER_BYTES:
                    raise AuditError(f"APK member is too large: {entry.filename}")
                if entry.flag_bits & 1 or entry.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                    raise AuditError(f"Unsupported compressed or encrypted APK member: {entry.filename}")
                return archive.read(entry)

            notice = entries.get(NOTICE_ASSET)
            packaged_notice = member(notice) if notice else None
            notice_matches = packaged_notice == expected_notice
            report["packaged_notice"] = {"path": NOTICE_ASSET, "matches_installed_ndk": notice_matches,
                                         "sha256": digest(packaged_notice) if packaged_notice is not None else None}
            if not notice_matches:
                errors.append("APK is missing the exact prepared installed-NDK notice asset (fallback/stale content is insufficient)")
            libraries = {}
            for name, entry in entries.items():
                match = re.fullmatch(r"lib/([^/]+)/([^/]+\.so)", name)
                if match:
                    libraries.setdefault(match[1], {})[match[2]] = entry
            report["observed_abis"] = sorted(libraries)
            if set(libraries) != set(abis):
                errors.append("Packaged ABIs differ from the explicitly requested ABI set")
            for abi in sorted(set(abis) | libraries.keys()):
                names = libraries.get(abi, {})
                for required in (DSP_LIBRARY, RUNTIME_LIBRARY):
                    if required not in names:
                        errors.append(f"{abi}: missing {required}")
                if abi not in ABI_FORMATS:
                    errors.append(f"Unsupported APK ABI: {abi}")
                    continue
                for name, entry in sorted(names.items()):
                    item = {"abi": abi, "name": name, "apk_path": entry.filename}
                    report["libraries"].append(item)
                    try:
                        data = member(entry)
                        item.update({"sha256": digest(data), "size_bytes": len(data),
                                     "zip_compression": entry.compress_type, "zip_data_offset": zip_data_offset(raw, entry)})
                        is64 = ABI_FORMATS[abi][0] == 2
                        item["zip_alignment_16kb"] = entry.compress_type == zipfile.ZIP_STORED and item["zip_data_offset"] % PAGE_SIZE == 0
                        if is64 and not item["zip_alignment_16kb"]:
                            raise AuditError("64-bit library must be uncompressed and ZIP-aligned to 16 KB")
                        elf = inspect_elf(data, abi)
                        item["elf"] = elf
                        if elf["soname"] != name and (elf["soname"] is not None or name in (DSP_LIBRARY, RUNTIME_LIBRARY)):
                            raise AuditError("ELF SONAME differs from its packaged library filename")
                        unknown = set(elf["needed"]) - names.keys() - system_libraries.keys()
                        if unknown:
                            raise AuditError("Unresolved dynamic dependencies: " + ", ".join(sorted(unknown)))
                        if name == DSP_LIBRARY:
                            if RUNTIME_LIBRARY not in elf["needed"]:
                                raise AuditError("DSP does not link the expected shared C++ runtime")
                            missing = {JNI_PREFIX + method for method in JNI_METHODS} - set(elf["jni_exports"])
                            if missing:
                                raise AuditError("Missing exported JNI functions: " + ", ".join(sorted(missing)))
                        if name == RUNTIME_LIBRARY:
                            item["ndk_runtime_comparison"] = compare_runtime(data, ndk, abi)
                            if item["ndk_runtime_comparison"]["match"] == "mismatch":
                                raise AuditError("Packaged libc++ does not match installed NDK bytes, before or after its documented strip step")
                    except (OSError, ValueError, zipfile.BadZipFile) as error:
                        errors.append(f"{entry.filename}: {error}")
            for name, entry in sorted(entries.items()):
                if not re.fullmatch(r"classes(?:[2-9]|[1-9][0-9]+)?\.dex", name):
                    continue
                try:
                    data = member(entry)
                    declaration = inspect_dex(data)
                    if declaration:
                        declaration.update({"apk_path": name, "dex_sha256": digest(data)})
                        report["jni_declarations"].append(declaration)
                except (OSError, ValueError, zipfile.BadZipFile) as error:
                    errors.append(f"{name}: {error}")
            if len(report["jni_declarations"]) != 1:
                errors.append("Expected exactly one DEX definition retaining all native JNI method names and signatures")
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        errors.append(str(error))
    report["verdict"] = "failed" if errors else "passed"
    return report


def write_report(path: Path, report: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    prepare = commands.add_parser("prepare-notices", help="Prepare notices from the pinned installed NDK before Flutter builds")
    prepare.add_argument("--ndk", type=Path, required=True)
    prepare.add_argument("--asset", type=Path, default=Path("assets/licenses/ANDROID-NDK.txt"))
    prepare.add_argument("--output", type=Path, required=True)
    inspect = commands.add_parser("inspect", help="Inspect the final APK; nonzero exit on missing/mismatched evidence")
    inspect.add_argument("apk", type=Path)
    inspect.add_argument("--ndk", type=Path, required=True)
    inspect.add_argument("--abi", choices=tuple(ABI_FORMATS), action="append", required=True)
    inspect.add_argument("--source-revision")
    inspect.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.action == "prepare-notices":
            prepare_notices(args.ndk, args.asset, args.output)
            print(f"Prepared exact NDK {NDK_VERSION} notices; APK verification is still required.")
            return 0
        report = inspect_apk(args.apk, args.ndk, args.abi, source_revision=args.source_revision)
        write_report(args.output, report)
        print(f"{args.apk.name}: {report['verdict']}; release approval remains separate")
        for error in report["errors"]:
            print(f"  {error}", file=sys.stderr)
        return int(report["verdict"] != "passed")
    except (OSError, ValueError) as error:
        print(f"Android audio artifact audit failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
