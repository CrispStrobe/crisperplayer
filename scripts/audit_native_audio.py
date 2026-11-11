#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Verify the packaged direct-native audio library and exercise its real ABI.

This is artifact/source-identity and runtime evidence, not distribution license
clearance or a claim about every operating-system component. It deliberately
does not fall back to a system library if the packaged artifact is absent.
"""

from __future__ import annotations

import argparse
import ctypes as ct
from contextlib import ExitStack
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


REPO = Path(__file__).resolve().parents[1]
FORBIDDEN = re.compile(
    r"^(?:lib)?(?:mpv|avcodec|avformat|avfilter|avutil|avdevice|swresample|"
    r"swscale|postproc|ffmpeg|ffprobe|ffplay)(?:[-_.0-9]|$)", re.IGNORECASE
)
NATIVE_SUFFIX = re.compile(r"(?:\.(?:dll|exe|dylib|a|lib)|\.so(?:\.[0-9]+)*)$", re.IGNORECASE)
LIBRARY_NAMES = {"crisper_audio.dll", "libcrisper_audio.so", "libcrisper_audio.dylib"}
ENGINES = ((0, "sonic"), (1, "bungee-basic"), (2, "signalsmith-stretch"), (3, "chromium-wsola"))


class AuditError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AuditError(message)


def checked_ended(state: int, engine: str) -> bool:
    # The C ABI returns -1 on failure. Python truthiness would mistake that
    # for successful EOF even if the final PCM and counters happened to match.
    require(state in (0, 1), f"{engine} returned invalid drain state {state}")
    return state == 1


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def expected_name(platform: str) -> str:
    try:
        return {"win32": "crisper_audio.dll", "linux": "libcrisper_audio.so",
                "darwin": "libcrisper_audio.dylib"}[platform]
    except KeyError as error:
        raise AuditError(f"Unsupported audit host: {platform}") from error


def discover_bundle(bundle: Path, platform: str = sys.platform) -> tuple[Path, dict]:
    bundle = bundle.resolve()
    require(bundle.is_dir(), f"Missing bundle directory: {bundle}")
    files = sorted(path for path in bundle.rglob("*") if path.is_file())
    forbidden = [path.relative_to(bundle).as_posix() for path in files
                 if FORBIDDEN.match(path.name) and
                 (NATIVE_SUFFIX.search(path.name) or path.name.lower() in {"ffmpeg", "ffprobe", "ffplay", "mpv"})]
    require(not forbidden, "Forbidden bundled audio payload: " + ", ".join(forbidden))
    matches = [path for path in files if path.name.lower() in LIBRARY_NAMES]
    require(len(matches) == 1, f"Expected exactly one crisper_audio native library; found {len(matches)}")
    name = expected_name(platform)
    relative = Path("lib") / name if platform == "linux" else Path(name)
    expected = bundle / relative
    require(matches[0] == expected, f"Expected bundled library at {relative}, found {matches[0].relative_to(bundle)}")
    require(expected.resolve().is_relative_to(bundle), "Bundled library symlink escapes the bundle")
    return expected, {
        "directory": str(bundle), "native_library": relative.as_posix(),
        "files_checked": len(files), "forbidden_payloads": forbidden,
        "native_payloads": [path.relative_to(bundle).as_posix() for path in files if NATIVE_SUFFIX.search(path.name)],
    }


def checked_file(root: Path, relative: str, digest: str) -> Path:
    path = PurePosixPath(relative)
    require(not path.is_absolute() and bool(relative) and
            all(part not in ("", ".", "..") for part in relative.split("/")),
            f"Invalid manifest path: {relative}")
    resolved = root.joinpath(*path.parts)
    require(resolved.resolve().is_relative_to(root.resolve()), f"Manifest file escapes source directory: {relative}")
    require(bool(re.fullmatch(r"[0-9a-f]{64}", digest)), f"Invalid source hash: {relative}")
    require(resolved.is_file(), f"Missing source file: {relative}")
    require(sha256(resolved) == digest, f"Source hash mismatch: {relative}")
    return resolved


def verify_source_manifests(repo: Path = REPO) -> dict:
    native = repo / "packages/crisper_audio/native"
    vendor = native / "vendor"
    miniaudio_file = vendor / "miniaudio.manifest.json"
    miniaudio = json.loads(miniaudio_file.read_text(encoding="utf-8"))
    require(bool(re.fullmatch(r"[0-9a-f]{40}", miniaudio["source_commit"])), "miniaudio has no immutable source pin")
    require(set(miniaudio["sha256"]) == {"miniaudio.h", "miniaudio.LICENSE"}, "Incomplete miniaudio source/license manifest")
    for name, digest in miniaudio["sha256"].items():
        checked_file(vendor, name, digest)

    glint_root = vendor / "glint"
    glint_file = glint_root / "UPSTREAM.json"
    glint = json.loads(glint_file.read_text(encoding="utf-8"))
    require(bool(re.fullmatch(r"[0-9a-f]{40}", glint["commit"])), "Glint has no immutable source pin")
    expected_glint = set()
    for entry in glint["selected_files"]:
        checked_file(glint_root, entry["path"], entry["vendored_sha256"])
        require(entry["path"] not in expected_glint, "Duplicate Glint manifest entry")
        expected_glint.add(entry["path"])
    checked_file(glint_root, glint["patch_file"], glint["patch_sha256"])
    actual_glint = {path.relative_to(glint_root).as_posix() for path in glint_root.rglob("*") if path.is_file()}
    require(actual_glint == expected_glint | {"UPSTREAM.json", "UPSTREAM.md", glint["patch_file"]},
            "Unlisted or missing Glint source files")
    require({"LICENSE", "src/mp3_decoder.cpp", "src/aac_decoder.cpp"} <= expected_glint,
            "Glint decoder/license closure is incomplete")

    dsp_root = repo / "packages/just_audio/native/crisper_dsp"
    dsp_vendor = dsp_root / "vendor"
    dsp_file = dsp_vendor / "manifest.json"
    dsp = json.loads(dsp_file.read_text(encoding="utf-8"))
    expected_dsp = set()
    for component in dsp["components"]:
        require(bool(re.fullmatch(r"[0-9a-f]{40}", component["revision"])),
                f"Unpinned DSP vendor: {component['id']}")
        for entry in component["files"]:
            checked_file(dsp_vendor, entry["path"], entry["sha256"])
            require(entry["path"] not in expected_dsp, "Duplicate DSP manifest entry")
            expected_dsp.add(entry["path"])
    actual_dsp = {path.relative_to(dsp_vendor).as_posix() for path in dsp_vendor.rglob("*") if path.is_file()}
    require(actual_dsp == expected_dsp | {"manifest.json"}, "Unlisted or missing DSP source files")
    require({"sonic", "bungee", "signalsmith-stretch", "chromium-wsola"} <=
            {component["id"] for component in dsp["components"]}, "Incomplete four-engine DSP source manifest")

    owned = [native / path for path in (
        "CMakeLists.txt", "glint.cmake", "crisper_output.cpp", "crisper_output.h",
        "miniaudio_impl.c", "miniaudio_config.h", "dsp_link.cpp",
        "glint_bridge.cpp", "glint_bridge.h")]
    owned += [dsp_root / path for path in (
        "CMakeLists.txt", "crisper_dsp.cpp", "crisper_dsp.h", "wsola/wsola.cpp", "wsola/wsola.h")]
    return {
        "verified": True,
        "manifests": {path.relative_to(repo).as_posix(): sha256(path)
                      for path in (miniaudio_file, glint_file, dsp_file)},
        "host_and_adapter_sources": {path.relative_to(repo).as_posix(): sha256(path) for path in owned},
        "miniaudio": {"revision": miniaudio["source_commit"], "license": miniaudio["license"], "files_verified": 2},
        "glint": {"revision": glint["commit"], "declared_license": glint["declared_license"],
                  "files_verified": len(expected_glint), "provenance_caveat": glint.get("provenance_caveat"),
                  "flac_required": "src/flac_decoder.cpp" in expected_glint},
        "dsp": {"files_verified": len(expected_dsp), "components": [
            {"id": item["id"], "revision": item["revision"], "license": item["license_expression"]}
            for item in dsp["components"]]},
    }


def bind(library: ct.CDLL, name: str, result, arguments):
    try:
        function = getattr(library, name)
    except AttributeError as error:
        raise AuditError(f"Missing native ABI symbol: {name}") from error
    function.restype, function.argtypes = result, arguments
    return function


def probe_library(path: Path, *, require_flac: bool = False) -> dict:
    """Called in a child process: a crash/hang cannot become a successful audit."""
    with ExitStack() as stack:
        if sys.platform == "win32":
            stack.enter_context(os.add_dll_directory(str(path.parent.resolve())))
        library = ct.CDLL(str(path.resolve()))
        pointer, u32, u64, i32, f32 = ct.c_void_p, ct.c_uint32, ct.c_uint64, ct.c_int32, ct.c_float
        floats = ct.POINTER(f32)
        abi = bind(library, "ca_output_abi_version", i32, [])()
        require(abi == 1, f"Unsupported output ABI: {abi}")
        output_create = bind(library, "ca_output_create", pointer, [i32, i32, u32, u32, i32])
        output_destroy = bind(library, "ca_output_destroy", None, [pointer])
        start = bind(library, "ca_output_start", i32, [pointer])
        pause = bind(library, "ca_output_pause", i32, [pointer])
        reset = bind(library, "ca_output_reset", i32, [pointer])
        write = bind(library, "ca_output_write", u32, [pointer, floats, u32])
        render = bind(library, "ca_output_test_render", u32, [pointer, floats, u32])
        presented = bind(library, "ca_output_presented_frames", u64, [pointer])
        rendered = bind(library, "ca_output_rendered_frames", u64, [pointer])
        buffered = bind(library, "ca_output_buffered_frames", u32, [pointer])
        capacity = bind(library, "ca_output_capacity_frames", u32, [pointer])
        latency = bind(library, "ca_output_latency_frames", u32, [pointer])
        playing = bind(library, "ca_output_is_playing", i32, [pointer])
        volume = bind(library, "ca_output_set_volume", i32, [pointer, f32])
        output_error = bind(library, "ca_output_error", ct.c_char_p, [pointer])
        bind(library, "ca_output_pump", u32, [pointer, u32])
        underrun = bind(library, "ca_output_underrun_frames", u64, [pointer])
        backend = bind(library, "ca_output_backend_name", ct.c_char_p, [pointer])
        output = output_create(16000, 2, 16, 4, 2)
        require(bool(output), "Could not create manual output")
        try:
            samples = (f32 * 48)(*(i / 64 for i in range(48)))
            result = (f32 * 40)()
            require(backend(output) == b"manual", "Audit sink is not the manual backend")
            require(capacity(output) == 16 and latency(output) == 0, "Manual queue metadata is inconsistent")
            require(write(output, samples, 24) == 16, "Output did not enforce bounded partial writes")
            require(write(output, samples, 1) == 0, "Full output queue accepted extra audio")
            require(start(output) == 0, "Manual output failed to start")
            require(playing(output) == 1 and volume(output, 0.5) == 0, "Output state/volume failed")
            require(render(output, result, 20) == 16, "Manual output consumed the wrong frame count")
            require(list(result) == [sample * 0.5 for sample in list(samples)[:32]] + [0.0] * 8,
                    "Output PCM order, volume or underrun silence changed")
            require(rendered(output) == presented(output) == 16 and underrun(output) == 4,
                    "Underrun silence advanced the music clock")
            require(pause(output) == 0 and write(output, samples, 2) == 2, "Paused queue did not preserve PCM")
            require(render(output, result, 3) == 0 and buffered(output) == 2, "Pause consumed queued PCM")
            require(reset(output) == 0 and buffered(output) == rendered(output) == presented(output) == 0,
                    "Reset did not establish a clean source epoch")
            require(playing(output) == 0 and output_error(output) == b"", "Reset left an active or failed output")
        finally:
            output_destroy(output)

        cancel_create = bind(library, "ca_cancel_create", pointer, [])
        cancel_set = bind(library, "ca_cancel_set", None, [pointer, u64])
        cancel_get = bind(library, "ca_cancel_get", u64, [pointer])
        cancel_destroy = bind(library, "ca_cancel_destroy", None, [pointer])
        cancellation = cancel_create()
        require(bool(cancellation), "Cancellation allocation failed")
        try:
            cancel_set(cancellation, 123456789)
            require(cancel_get(cancellation) == 123456789, "Cancellation generation did not round-trip")
        finally:
            cancel_destroy(cancellation)

        create = bind(library, "cp_dsp_create", pointer, [i32, i32, i32, ct.c_double])
        destroy = bind(library, "cp_dsp_destroy", None, [pointer])
        dsp_write = bind(library, "cp_dsp_write_f32", i32, [pointer, floats, i32])
        dsp_read = bind(library, "cp_dsp_read_f32", i32, [pointer, floats, i32])
        finish = bind(library, "cp_dsp_finish", i32, [pointer])
        ended = bind(library, "cp_dsp_ended", i32, [pointer])
        source_frames = bind(library, "cp_dsp_source_frames", ct.c_int64, [pointer])
        accepted_frames = bind(library, "cp_dsp_input_frames", ct.c_int64, [pointer])
        output_frames = bind(library, "cp_dsp_output_frames", ct.c_int64, [pointer])
        dsp_reset = bind(library, "cp_dsp_reset", i32, [pointer, ct.c_double])
        bind(library, "cp_dsp_last_error", ct.c_char_p, [])
        bind(library, "cp_dsp_available", i32, [pointer])
        bind(library, "cp_dsp_latency_frames", i32, [pointer])
        bind(library, "cp_dsp_write_s16", i32, [pointer, ct.POINTER(ct.c_int16), i32])
        bind(library, "cp_dsp_read_s16", i32, [pointer, ct.POINTER(ct.c_int16), i32])
        input_frames = 4097
        signal = (f32 * input_frames)(*(0.25 * math.sin(2 * math.pi * 440 * i / 16000)
                                       for i in range(input_frames)))
        pcm = (f32 * 2048)()
        engines = []
        for engine_id, name in ENGINES:
            handle = create(engine_id, 16000, 1, 1.5)
            require(bool(handle), f"Could not create {name}")
            try:
                written = delivered = 0
                energy = 0.0
                finishing = False
                for _ in range(10000):
                    if written < input_frames:
                        count = dsp_write(handle, ct.cast(ct.byref(signal, written * ct.sizeof(f32)), floats),
                                          min(1024, input_frames - written))
                        require(count >= 0, f"{name} write failed")
                        written += count
                    elif not finishing:
                        require(finish(handle) == 0, f"{name} finish failed")
                        finishing = True
                    count = dsp_read(handle, pcm, len(pcm))
                    require(0 <= count <= len(pcm), f"{name} read failed")
                    values = list(pcm)[:count]
                    require(all(math.isfinite(value) for value in values), f"{name} emitted non-finite PCM")
                    energy += sum(value * value for value in values)
                    delivered += count
                    if finishing and checked_ended(ended(handle), name):
                        break
                else:
                    raise AuditError(f"{name} did not drain")
                require(written == input_frames and delivered == int(input_frames / 1.5 + 0.5),
                        f"{name} output duration bypassed the selected speed")
                require(source_frames(handle) == input_frames, f"{name} source clock did not reach EOF")
                require(accepted_frames(handle) == written and output_frames(handle) == delivered,
                        f"{name} ABI counters disagree with processed PCM")
                require(energy > 0.01, f"{name} produced only silence")
                engines.append({"id": engine_id, "name": name, "speed": 1.5,
                                "input_frames": written, "output_frames": delivered})
                require(dsp_reset(handle, 1.0) == 0 and source_frames(handle) == output_frames(handle) == 0,
                        f"{name} reset retained an old source clock")
            finally:
                destroy(handle)

        class FrameInfo(ct.Structure):
            _fields_ = [(name, i32) for name in ("sample_rate", "channels", "samples", "frame_bytes")]

        glint_create = bind(library, "ca_glint_create", pointer, [i32])
        glint_destroy = bind(library, "ca_glint_destroy", None, [pointer])
        glint_decode = bind(library, "ca_glint_decode", i32,
                            [pointer, ct.POINTER(ct.c_uint8), i32, floats, ct.POINTER(FrameInfo), ct.c_int64])
        invalid = (ct.c_uint8 * 8)()
        decoded = (f32 * 2304)()
        for codec in (1, 2):
            handle = glint_create(codec)
            require(bool(handle), f"Glint codec {codec} creation failed")
            try:
                info = FrameInfo()
                require(glint_decode(handle, invalid, len(invalid), decoded, ct.byref(info), 0) < 0,
                        "Glint accepted an invalid compressed frame")
            finally:
                glint_destroy(handle)

        codecs = ["mp3", "aac-lc"]
        if require_flac:
            class FlacInfo(ct.Structure):
                _fields_ = [("first_frame", ct.c_int64), ("frames", i32), ("encoded_bytes", i32)]

            bytes_pointer = ct.POINTER(ct.c_uint8)
            flac_info = bind(library, "ca_glint_flac_frame_info", i32,
                             [bytes_pointer, bytes_pointer, i32, ct.POINTER(FlacInfo)])
            flac_decode = bind(library, "ca_glint_flac_decode", i32,
                               [bytes_pointer, bytes_pointer, i32, floats, i32, ct.POINTER(FlacInfo)])
            streaminfo = (ct.c_uint8 * 34)()
            info = FlacInfo()
            require(flac_info(streaminfo, invalid, len(invalid), ct.byref(info)) < 0,
                    "FLAC parser accepted invalid stream/frame data")
            require(flac_decode(streaminfo, invalid, len(invalid), decoded, len(decoded), ct.byref(info)) < 0,
                    "FLAC decoder accepted invalid stream/frame data")
            codecs.append("flac")
        return {"passed": True, "output_abi": abi, "sink": "manual",
                "checks": ["bounded queue", "PCM equality", "underrun clock", "pause", "reset", "cancellation"],
                "engines": engines, "glint_decoders": codecs,
                "glint_check": "Decoder ABI and invalid-frame rejection; valid codec fixtures run in Dart CI"}


def run_probe(path: Path, *, require_flac: bool = False) -> dict:
    command = [sys.executable, str(Path(__file__).resolve()), "--probe-library", str(path.resolve())]
    if require_flac:
        command.append("--require-flac")
    process = subprocess.run(command,
                             capture_output=True, text=True, timeout=60)
    require(process.returncode == 0,
            f"Native ABI probe failed (exit {process.returncode}): {(process.stderr or process.stdout)[-4000:]}")
    result = json.loads(process.stdout)
    require(result.get("passed") is True, "Native ABI probe did not report success")
    if require_flac:
        require("flac" in result.get("glint_decoders", []),
                "Source manifest requires FLAC but runtime probe did not exercise it")
    return result


def audit(*, bundle: Path | None = None, library: Path | None = None,
          repo: Path = REPO, expected_sha256: str | None = None) -> dict:
    report = {
        "schema_version": 1, "status": "failed", "release_approved": False,
        "scope": "Exact packaged native audio artifact, source hashes, and real manual-device ABI execution",
        "findings": [],
        "limitations": [
            "Source hashes and successful ABI calls are not a binary-to-source reproducibility proof.",
            "Filename inventory does not identify all statically linked or renamed code or all OS dependencies.",
            "The manual backend proves PCM and source accounting, not physical speaker output or measured hardware latency.",
            "Source attribution, corresponding source, notices, and distribution license clearance remain separate gates.",
        ],
    }
    try:
        require((bundle is None) != (library is None), "Choose exactly one bundle or host library")
        if bundle is not None:
            library, report["bundle"] = discover_bundle(bundle)
        assert library is not None
        library = library.resolve()
        require(library.is_file(), f"Missing native library: {library}")
        require(library.name == expected_name(sys.platform), f"Unexpected native library filename: {library.name}")
        observed = sha256(library)
        report["artifact"] = {"path": str(library), "filename": library.name,
                              "size_bytes": library.stat().st_size, "sha256": observed}
        if expected_sha256 is not None:
            require(observed == expected_sha256.lower(), "Native artifact differs from the expected SHA-256")
        report["source"] = verify_source_manifests(repo)
        revision = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], capture_output=True, text=True)
        report["source_revision"] = revision.stdout.strip() if revision.returncode == 0 else None
        report["runtime"] = run_probe(library, require_flac=report["source"]["glint"]["flac_required"])
        report["status"] = "passed"
    except (AuditError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        report["findings"].append(str(error))
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    location = parser.add_mutually_exclusive_group(required=True)
    location.add_argument("--bundle", type=Path, help="Final Linux/Windows Flutter bundle")
    location.add_argument("--library", type=Path, help="Exact host-built shared library")
    location.add_argument("--probe-library", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--expected-sha256")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--require-flac", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.probe_library is not None:
        try:
            print(json.dumps(probe_library(args.probe_library, require_flac=args.require_flac)))
            return 0
        except (AuditError, OSError, ValueError) as error:
            print(f"Native ABI probe: {error}", file=sys.stderr)
            return 1
    if args.expected_sha256 and not re.fullmatch(r"[0-9a-fA-F]{64}", args.expected_sha256):
        parser.error("--expected-sha256 requires exactly 64 hexadecimal digits")
    report = audit(bundle=args.bundle, library=args.library, expected_sha256=args.expected_sha256)
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    print(f"Direct native audio audit: {report['status']}", file=sys.stderr)
    for finding in report["findings"]:
        print(f"  {finding}", file=sys.stderr)
    return int(report["status"] != "passed")


if __name__ == "__main__":
    raise SystemExit(main())
