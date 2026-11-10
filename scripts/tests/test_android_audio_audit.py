"""Synthetic binary fixtures verify the final-package contract without an SDK."""

import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import tempfile
import unittest
from unittest import mock
import warnings
import zipfile
import zlib


SPEC = importlib.util.spec_from_file_location(
    "audit_android_audio", Path(__file__).parents[1] / "audit_android_audio.py"
)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


def align(value, size):
    return (value + size - 1) // size * size


def elf_fixture(abi, name, *, needed=(), exports=(), alignment=16384):
    """An ELF with real program/dynamic/section tables and exported symbols."""
    elf_class, machine, _ = audit.ABI_FORMATS[abi]
    is64 = elf_class == 2
    strings = bytearray(b"\0")
    offsets = {}
    for text in (name, *needed, *exports):
        if text not in offsets:
            offsets[text] = len(strings)
            strings.extend(text.encode() + b"\0")
    symbol_size = 24 if is64 else 16
    symbols_offset = align(0x200 + len(strings), 16)
    symbols = bytearray(symbol_size)
    for text in exports:
        if is64:
            symbols.extend(struct.pack("<IBBHQQ", offsets[text], 0x12, 0, 1, 0x1F0, 1))
        else:
            symbols.extend(struct.pack("<IIIBBH", offsets[text], 0x1F0, 1, 0x12, 0, 1))
    hash_offset = align(symbols_offset + len(symbols), 16)
    hash_words = [1, len(exports) + 1, 1 if exports else 0, 0]
    hash_words.extend(index + 1 if index < len(exports) else 0 for index in range(1, len(exports) + 1))
    hash_data = struct.pack("<" + "I" * len(hash_words), *hash_words)
    sections_offset = align(hash_offset + len(hash_data), 16)
    section_size = 64 if is64 else 40
    data = bytearray(sections_offset + 4 * section_size)
    ident = b"\x7fELF" + bytes((elf_class, 1, 1)) + b"\0" * 9
    if is64:
        struct.pack_into("<16sHHIQQQIHHHHHH", data, 0, ident, 3, machine, 1, 0, 64,
                         sections_offset, 0, 64, 56, 2, 64, 4, 0)
    else:
        struct.pack_into("<16sHHIIIIIHHHHHH", data, 0, ident, 3, machine, 1, 0, 52,
                         sections_offset, 0, 52, 32, 2, 40, 4, 0)
    dynamics = [(5, 0x200), (10, len(strings)), (6, symbols_offset), (11, symbol_size),
                (14, offsets[name]), *((1, offsets[item]) for item in needed), (4, hash_offset), (0, 0)]
    dynamic_data = b"".join(struct.pack("<qQ" if is64 else "<iI", *entry) for entry in dynamics)
    data[0x100:0x100 + len(dynamic_data)] = dynamic_data
    data[0x1F0:0x1F4] = b"CODE"
    data[0x200:0x200 + len(strings)] = strings
    data[symbols_offset:symbols_offset + len(symbols)] = symbols
    data[hash_offset:hash_offset + len(hash_data)] = hash_data
    if is64:
        struct.pack_into("<IIQQQQQQ", data, 64, 1, 5, 0, 0, 0, len(data), len(data), alignment)
        struct.pack_into("<IIQQQQQQ", data, 120, 2, 4, 0x100, 0x100, 0x100, len(dynamic_data), len(dynamic_data), 8)
    else:
        struct.pack_into("<IIIIIIII", data, 52, 1, 0, 0, 0, len(data), len(data), 5, alignment)
        struct.pack_into("<IIIIIIII", data, 84, 2, 0x100, 0x100, 0x100, len(dynamic_data), len(dynamic_data), 4, 4)
    for index, section in enumerate([
        (0, 1, 6, 0x1F0, 0x1F0, 4, 0, 0, 4, 0),
        (0, 3, 2, 0x200, 0x200, len(strings), 0, 0, 1, 0),
        (0, 11, 2, symbols_offset, symbols_offset, len(symbols), 2, 1, 8 if is64 else 4, symbol_size),
    ], start=1):
        struct.pack_into("<IIQQQQIIQQ" if is64 else "<IIIIIIIIII", data,
                         sections_offset + index * section_size, *section)
    return bytes(data)


def uleb(value):
    result = bytearray()
    while value > 127:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def dex_fixture(*, methods=None, native=True, class_name=audit.JNI_CLASS):
    """Construct DEX ID/prototype/class-data tables; raw string matches are insufficient."""
    methods = dict(audit.JNI_METHODS if methods is None else methods)
    names = sorted(methods)
    types_in_signature = lambda text: re.findall(r"\[*[BCDFIJSZV]|\[*L[^;]+;", text)
    descriptors = {class_name, "Ljava/lang/Object;"}
    for signature in methods.values():
        descriptors.update(types_in_signature(signature))
    signatures = sorted(set(methods.values()))
    shorties = {}
    for signature in signatures:
        arguments, result = signature[1:].split(")")
        parts = [result, *types_in_signature(arguments)]
        shorties[signature] = "".join("L" if part.startswith(("L", "[")) else part for part in parts)
    # Keep an unused real descriptor even in the obfuscated fixture: searching
    # for its string alone would incorrectly claim that R8 retained the class.
    strings = sorted({*descriptors, *names, *shorties.values(), audit.JNI_CLASS})
    string_ids = {text: index for index, text in enumerate(strings)}
    types = sorted(descriptors, key=string_ids.get)
    type_ids = {text: index for index, text in enumerate(types)}
    string_offset = 112
    type_offset = string_offset + len(strings) * 4
    proto_offset = type_offset + len(types) * 4
    method_offset = proto_offset + len(signatures) * 12
    class_offset = method_offset + len(names) * 8
    data_offset = class_offset + 32
    data = bytearray(data_offset)
    for index, text in enumerate(strings):
        struct.pack_into("<I", data, string_offset + index * 4, len(data))
        data.extend(uleb(len(text)) + text.encode() + b"\0")
    for index, text in enumerate(types):
        struct.pack_into("<I", data, type_offset + index * 4, string_ids[text])
    for index, signature in enumerate(signatures):
        arguments, result = signature[1:].split(")")
        parameters = types_in_signature(arguments)
        list_offset = 0
        if parameters:
            data.extend(b"\0" * (align(len(data), 4) - len(data)))
            list_offset = len(data)
            data.extend(struct.pack("<I", len(parameters)))
            data.extend(struct.pack("<" + "H" * len(parameters), *(type_ids[item] for item in parameters)))
        struct.pack_into("<III", data, proto_offset + index * 12,
                         string_ids[shorties[signature]], type_ids[result], list_offset)
    class_data_offset = len(data)
    data.extend(b"\0\0\0" + uleb(len(names)))
    for index, name in enumerate(names):
        struct.pack_into("<HHI", data, method_offset + index * 8,
                         type_ids[class_name], signatures.index(methods[name]), string_ids[name])
        data.extend(uleb(0 if index == 0 else 1) + uleb(0x101 if native else 1) + b"\0")
    struct.pack_into("<8I", data, class_offset, type_ids[class_name], 1,
                     type_ids["Ljava/lang/Object;"], 0, 0xFFFFFFFF, 0, class_data_offset, 0)
    data[:8] = b"dex\n039\0"
    struct.pack_into("<III", data, 32, len(data), 112, 0x12345678)
    for offset, count, location in [(56, len(strings), string_offset), (64, len(types), type_offset),
                                    (72, len(signatures), proto_offset), (88, len(names), method_offset),
                                    (96, 1, class_offset), (104, len(data) - data_offset, data_offset)]:
        struct.pack_into("<II", data, offset, count, location)
    data[12:32] = hashlib.sha1(data[32:]).digest()
    struct.pack_into("<I", data, 8, zlib.adler32(data[12:]))
    return bytes(data)


def write_apk(path, members, *, misalign=None, compress=None, duplicate=None):
    with zipfile.ZipFile(path, "w") as archive:
        for name, data in members.items():
            entry = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED if name == compress else zipfile.ZIP_STORED
            if name.endswith(".so") and name != misalign:
                padding = (-(archive.fp.tell() + 30 + len(name.encode()))) % 16384
                if padding:
                    if padding < 4:
                        padding += 16384
                    entry.extra = struct.pack("<HH", 0xCAFE, padding - 4) + b"\0" * (padding - 4)
            archive.writestr(entry, data)
        if duplicate:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                archive.writestr(duplicate, members[duplicate])


class AndroidAudioAuditTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.ndk = self.directory / "ndk"
        self.ndk.mkdir()
        (self.ndk / "source.properties").write_text(f"Pkg.Desc = Android NDK\nPkg.Revision = {audit.NDK_VERSION}\n")
        (self.ndk / "NOTICE").write_bytes(b"Original base notices.\r\n")
        (self.ndk / "NOTICE.toolchain").write_bytes(b"Original toolchain notices with an LLVM exception.\n")
        (self.ndk / "meta").mkdir()
        (self.ndk / "meta/system_libs.json").write_text(json.dumps({"libc.so": 9, "libdl.so": 9, "liblog.so": 9}))
        self.abis = ["arm64-v8a", "x86_64"]
        self.members = {audit.NOTICE_ASSET: audit.collect_ndk_notices(self.ndk)[0], "classes.dex": dex_fixture()}
        self.runtime_sources = {}
        for abi in self.abis:
            runtime = elf_fixture(abi, audit.RUNTIME_LIBRARY, needed=("libc.so", "libdl.so"), exports=("runtime_export",))
            source = self.ndk / "toolchains/llvm/prebuilt" / audit.NDK_HOST / "sysroot/usr/lib" / audit.ABI_FORMATS[abi][2] / audit.RUNTIME_LIBRARY
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(runtime)
            self.runtime_sources[abi] = source
            self.members[f"lib/{abi}/{audit.RUNTIME_LIBRARY}"] = runtime
            self.members[f"lib/{abi}/{audit.DSP_LIBRARY}"] = self.dsp(abi)
        self.apk = self.directory / "app-release.apk"

    def dsp(self, abi, **kwargs):
        return elf_fixture(abi, audit.DSP_LIBRARY,
                           needed=kwargs.pop("needed", (audit.RUNTIME_LIBRARY, "liblog.so")),
                           exports=kwargs.pop("exports", tuple(audit.JNI_PREFIX + name for name in audit.JNI_METHODS)), **kwargs)

    def run_audit(self, **kwargs):
        write_apk(self.apk, self.members, **kwargs)
        return audit.inspect_apk(self.apk, self.ndk, self.abis, source_revision="fixture-commit")

    def assert_failure(self, report, text):
        self.assertEqual(report["verdict"], "failed", report)
        self.assertTrue(any(text in error for error in report["errors"]), report["errors"])
        self.assertFalse(report["release_approved"])

    def test_complete_package_records_actual_bytes_without_approving_release(self):
        report = self.run_audit()
        self.assertEqual(report["verdict"], "passed", report["errors"])
        self.assertFalse(report["release_approved"])
        self.assertTrue(report["packaged_notice"]["matches_installed_ndk"])
        self.assertEqual(len(report["libraries"]), 4)
        self.assertEqual(report["jni_declarations"][0]["native_methods"], audit.JNI_METHODS)
        self.assertTrue(all(item["zip_alignment_16kb"] for item in report["libraries"]))
        self.assertEqual(report["apk"]["sha256"], audit.digest(self.apk.read_bytes()))

    def test_preparation_preserves_exact_original_notice_bytes_and_is_deterministic(self):
        asset = self.directory / "assets/ANDROID-NDK.txt"
        output = self.directory / "evidence/notices.json"
        report = audit.prepare_notices(self.ndk, asset, output)
        first = asset.read_bytes()
        audit.prepare_notices(self.ndk, asset, output)
        self.assertEqual(first, asset.read_bytes())
        for name in audit.NDK_NOTICES:
            original = (self.ndk / name).read_bytes()
            self.assertIn(original, first)
            self.assertEqual((output.parent / "ndk-notices" / name).read_bytes(), original)
        self.assertFalse(report["packaged_asset_verified"])
        self.assertFalse(report["release_approved"])

    def test_fallback_or_stale_notice_cannot_pass(self):
        self.members[audit.NOTICE_ASSET] = b"A checked-in explanatory fallback is not the exact notices."
        self.assert_failure(self.run_audit(), "exact prepared installed-NDK notice")

    def test_missing_notice_cannot_pass(self):
        del self.members[audit.NOTICE_ASSET]
        self.assert_failure(self.run_audit(), "exact prepared installed-NDK notice")

    def test_wrong_ndk_or_missing_toolchain_notice_fails_preparation(self):
        (self.ndk / "source.properties").write_text("Pkg.Revision = 27.0.0\n")
        with self.assertRaisesRegex(audit.AuditError, "Expected installed NDK"):
            audit.collect_ndk_notices(self.ndk)
        (self.ndk / "source.properties").write_text(f"Pkg.Revision = {audit.NDK_VERSION}\n")
        (self.ndk / "NOTICE.toolchain").unlink()
        with self.assertRaises(OSError):
            audit.collect_ndk_notices(self.ndk)

    def test_missing_dsp_in_one_abi_is_not_hidden_by_other_abi(self):
        del self.members[f"lib/arm64-v8a/{audit.DSP_LIBRARY}"]
        self.assert_failure(self.run_audit(), f"arm64-v8a: missing {audit.DSP_LIBRARY}")

    def test_entire_missing_abi_is_rejected(self):
        self.members = {name: data for name, data in self.members.items() if not name.startswith("lib/x86_64/")}
        self.assert_failure(self.run_audit(), "Packaged ABIs differ")

    def test_wrong_elf_machine_cannot_pass(self):
        self.members[f"lib/arm64-v8a/{audit.DSP_LIBRARY}"] = self.dsp("x86_64")
        self.assert_failure(self.run_audit(), "ELF machine 183")

    def test_four_kb_load_alignment_fails_even_when_zip_is_aligned(self):
        self.members[f"lib/arm64-v8a/{audit.DSP_LIBRARY}"] = self.dsp("arm64-v8a", alignment=4096)
        self.assert_failure(self.run_audit(), "PT_LOAD does not support 16 KB")

    def test_zip_misalignment_or_compression_fails_even_when_elf_is_aligned(self):
        member = f"lib/arm64-v8a/{audit.DSP_LIBRARY}"
        for option in ("misalign", "compress"):
            with self.subTest(option=option):
                self.assert_failure(self.run_audit(**{option: member}), "uncompressed and ZIP-aligned")

    def test_all_packaged_libraries_are_checked_for_page_compatibility(self):
        self.members["lib/arm64-v8a/libunrelated.so"] = elf_fixture("arm64-v8a", "libunrelated.so", alignment=4096)
        self.assert_failure(self.run_audit(), "libunrelated.so: 64-bit ELF PT_LOAD")

    def test_missing_jni_export_and_unresolved_dependency_fail(self):
        key = f"lib/arm64-v8a/{audit.DSP_LIBRARY}"
        self.members[key] = self.dsp("arm64-v8a", exports=(audit.JNI_PREFIX + "create",))
        self.assert_failure(self.run_audit(), "Missing exported JNI functions")
        self.members[key] = self.dsp("arm64-v8a", needed=(audit.RUNTIME_LIBRARY, "libunpackaged.so"))
        self.assert_failure(self.run_audit(), "Unresolved dynamic dependencies: libunpackaged.so")

    def test_orphaned_symbol_sections_do_not_prove_loader_jni_exports(self):
        key = f"lib/arm64-v8a/{audit.DSP_LIBRARY}"
        for position, value, error in (
            (0x128, 0, "disagrees with loader DT_SYMTAB"),
            (0x138, 16, "disagrees with loader DT_SYMTAB"),
            (120 + 16, 0, "PT_DYNAMIC file offset disagrees"),
        ):
            with self.subTest(position=position):
                data = bytearray(self.dsp("arm64-v8a"))
                struct.pack_into("<Q", data, position, value)
                self.members[key] = bytes(data)
                self.assert_failure(self.run_audit(), error)

    def test_jni_functions_must_point_to_executable_bytes_and_be_hash_reachable(self):
        key = f"lib/arm64-v8a/{audit.DSP_LIBRARY}"
        data = bytearray(self.dsp("arm64-v8a"))
        symbol_offset = struct.unpack_from("<Q", data, 0x128)[0]
        struct.pack_into("<Q", data, symbol_offset + 24 + 8, 0xFFFFFFFFFFFF0000)
        self.members[key] = bytes(data)
        self.assert_failure(self.run_audit(), "outside executable file-backed")
        data = bytearray(self.dsp("arm64-v8a"))
        hash_offset = struct.unpack_from("<Q", data, 0x100 + 7 * 16 + 8)[0]
        struct.pack_into("<I", data, hash_offset + 8, 0)
        self.members[key] = bytes(data)
        self.assert_failure(self.run_audit(), "unreachable through an ELF loader hash table")

    def test_runtime_original_or_exact_documented_strip_output_required(self):
        abi = "arm64-v8a"
        original = self.runtime_sources[abi].read_bytes()
        self.runtime_sources[abi].write_bytes(original + b"synthetic debug section")
        tool = self.ndk / "toolchains/llvm/prebuilt" / audit.NDK_HOST / "bin/llvm-strip"
        tool.parent.mkdir()
        tool.write_bytes(b"fixture pinned strip tool; never executed")
        with mock.patch.object(audit, "strip_ndk_runtime", return_value=original) as strip:
            report = self.run_audit()
        self.assertEqual(report["verdict"], "passed", report["errors"])
        strip.assert_called_once_with(self.runtime_sources[abi], tool)
        runtime = next(item for item in report["libraries"] if item["abi"] == abi and item["name"] == audit.RUNTIME_LIBRARY)
        self.assertEqual(runtime["ndk_runtime_comparison"]["match"], "exact_ndk_strip_unneeded_bytes")
        with mock.patch.object(audit, "strip_ndk_runtime", return_value=original + b"different"):
            self.assert_failure(self.run_audit(), "does not match installed NDK bytes")

    def test_r8_renamed_class_not_accepted_even_when_original_descriptor_is_a_string(self):
        self.members["classes.dex"] = dex_fixture(class_name="La;")
        self.assertIn(audit.JNI_CLASS.encode(), self.members["classes.dex"])
        self.assert_failure(self.run_audit(), "Expected exactly one DEX definition")

    def test_r8_renamed_method_changed_signature_or_missing_native_flag_fails(self):
        renamed = dict(audit.JNI_METHODS)
        renamed["a"] = renamed.pop("create")
        signature_changed = {**audit.JNI_METHODS, "create": "(III)J"}
        for fixture in (dex_fixture(methods=renamed), dex_fixture(methods=signature_changed), dex_fixture(native=False)):
            with self.subTest(dex_hash=audit.digest(fixture)):
                self.members["classes.dex"] = fixture
                self.assert_failure(self.run_audit(), "native method names/signatures changed")

    def test_dex_descriptor_length_and_native_method_placement_must_be_valid(self):
        wrong_length = bytearray(dex_fixture())
        wrong_length[wrong_length.index(audit.JNI_CLASS.encode()) - 1] = 0
        wrong_group = bytearray(dex_fixture())
        class_offset = struct.unpack_from("<I", wrong_group, 100)[0]
        class_data_offset = struct.unpack_from("<I", wrong_group, class_offset + 24)[0]
        wrong_group[class_data_offset + 2:class_data_offset + 4] = bytes((len(audit.JNI_METHODS), 0))
        for data, error in ((wrong_length, "declared UTF-16 length"), (wrong_group, "in DEX virtual_methods")):
            with self.subTest(error=error):
                data[12:32] = hashlib.sha1(data[32:]).digest()
                struct.pack_into("<I", data, 8, zlib.adler32(data[12:]))
                self.members["classes.dex"] = bytes(data)
                self.assert_failure(self.run_audit(), error)

    def test_later_multidex_definition_is_inspected_and_duplicates_rejected(self):
        self.members["classes10.dex"] = self.members.pop("classes.dex")
        self.assertEqual(self.run_audit()["verdict"], "passed")
        self.members["classes.dex"] = self.members["classes10.dex"]
        self.assert_failure(self.run_audit(), "Expected exactly one DEX definition")

    def test_duplicate_zip_members_and_truncated_elf_fail_closed(self):
        self.assert_failure(self.run_audit(duplicate=audit.NOTICE_ASSET), "Duplicate ZIP members")
        self.members[f"lib/arm64-v8a/{audit.DSP_LIBRARY}"] = b"\x7fELF"
        self.assert_failure(self.run_audit(), "Truncated or out-of-range ELF")

    def test_dex_checksum_corruption_is_not_accepted(self):
        self.members["classes.dex"] = self.members["classes.dex"][:-1] + b"\xFF"
        self.assert_failure(self.run_audit(), "DEX checksum or signature mismatch")

    def test_32_bit_elf_parser_does_not_impose_64_bit_alignment_contract(self):
        for abi in ("armeabi-v7a", "x86"):
            with self.subTest(abi=abi):
                report = audit.inspect_elf(self.dsp(abi, alignment=4096), abi)
                self.assertEqual(report["class_bits"], 32)
                self.assertEqual(set(report["jni_exports"]), {audit.JNI_PREFIX + name for name in audit.JNI_METHODS})


if __name__ == "__main__":
    unittest.main()
