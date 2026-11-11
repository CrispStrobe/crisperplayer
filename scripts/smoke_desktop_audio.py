#!/usr/bin/env python3
"""Exercise a supplied libmpv's real PCM output at several pitch-preserving rates.

This is a timing/pitch smoke test using a generated sine wave, not a subjective
speech-quality benchmark or a license approval. Run only on a native library
whose source and provenance you intend to test.
"""

from __future__ import annotations

import argparse
import array
import ctypes
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import sys
import tempfile
import time
import wave


class Event(ctypes.Structure):
    _fields_ = [("event_id", ctypes.c_int), ("error", ctypes.c_int), ("reply_userdata", ctypes.c_uint64), ("data", ctypes.c_void_p)]


class EndFile(ctypes.Structure):
    _fields_ = [("reason", ctypes.c_int), ("error", ctypes.c_int)]


class NativePlayer:
    def __init__(self, library: Path):
        self._dll_directories = []
        if sys.platform == 'win32':
            # Python 3.8+ does not search PATH for dependent native DLLs.
            for directory in {library.resolve().parent, Path(sys.executable).parent}:
                self._dll_directories.append(os.add_dll_directory(str(directory)))
        self.lib = ctypes.CDLL(str(library.resolve()))
        self.lib.mpv_create.restype = ctypes.c_void_p
        self.lib.mpv_initialize.argtypes = [ctypes.c_void_p]
        self.lib.mpv_set_option_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
        self.lib.mpv_get_property_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.lib.mpv_get_property_string.restype = ctypes.c_void_p
        self.lib.mpv_free.argtypes = [ctypes.c_void_p]
        self.lib.mpv_command.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_char_p)]
        self.lib.mpv_wait_event.argtypes = [ctypes.c_void_p, ctypes.c_double]
        self.lib.mpv_wait_event.restype = ctypes.POINTER(Event)
        self.lib.mpv_terminate_destroy.argtypes = [ctypes.c_void_p]
        self.handle = self.lib.mpv_create()
        if not self.handle:
            raise RuntimeError("mpv_create failed")

    def option(self, name: str, value: str) -> None:
        result = self.lib.mpv_set_option_string(self.handle, name.encode(), value.encode())
        if result < 0:
            raise RuntimeError(f"Native option {name}={value} failed ({result})")

    def property(self, name: str) -> str | None:
        pointer = self.lib.mpv_get_property_string(self.handle, name.encode())
        if not pointer:
            return None
        try:
            return ctypes.string_at(pointer).decode("utf-8", errors="replace")
        finally:
            self.lib.mpv_free(pointer)

    def close(self) -> None:
        if self.handle:
            self.lib.mpv_terminate_destroy(self.handle)
            self.handle = None
        for directory in self._dll_directories:
            directory.close()
        self._dll_directories = []


def fixture(path: Path, seconds: int = 6) -> None:
    samples = array.array("h", (round(12000 * math.sin(2 * math.pi * 440 * index / 48000)) for index in range(48000 * seconds)))
    if sys.byteorder != "little":
        samples.byteswap()
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(48000)
        output.writeframes(samples.tobytes())


def pcm_measurements(path: Path) -> tuple[float, float]:
    # Read the tiny subset of RIFF written by mpv's PCM sink, including PCM
    # WAVE_FORMAT_EXTENSIBLE which Python <3.12's wave reader does not support.
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("Native PCM output is not a RIFF WAVE file")
    position = 12
    fmt = None
    pcm = None
    while position + 8 <= len(data):
        name, length = struct.unpack_from("<4sI", data, position)
        payload = data[position + 8:position + 8 + length]
        if name == b"fmt ":
            fmt = payload
        elif name == b"data":
            pcm = payload
        position += 8 + length + length % 2
    if fmt is None or pcm is None or len(fmt) < 16:
        raise ValueError("Native PCM output lacks format or data")
    encoding, channels, rate, _, _, bits = struct.unpack_from("<HHIIHH", fmt)
    if encoding == 0xFFFE and len(fmt) >= 40:
        encoding = struct.unpack_from("<H", fmt, 24)[0]
    if encoding != 1 or bits != 16 or channels != 1:
        raise ValueError(f"Unexpected PCM output: format={encoding}, bits={bits}, channels={channels}")
    values = array.array("h")
    values.frombytes(pcm[:len(pcm) // 2 * 2])
    if sys.byteorder != "little":
        values.byteswap()
    duration = len(values) / rate
    edge = round(rate * .15)
    middle = values[edge:-edge]
    if len(middle) < rate / 2 or max(middle) - min(middle) < 100:
        raise ValueError("Native output is empty, silent, or too short")
    crossings = sum(left <= 0 < right for left, right in zip(middle, middle[1:]))
    frequency = crossings / ((len(middle) - 1) / rate)
    return duration, frequency


def render_options(output: Path, rate: float, mode: str) -> dict[str, str]:
    portable = {'sonic', 'wsola', 'signalsmith', 'bungee'}
    if mode not in {"automatic", "legacy_scaletempo", 'atempo', *portable}:
        raise ValueError("Unknown speed-processing mode")
    options = {
            "config": "no", "terminal": "no", "vid": "no", "audio-display": "no",
            "ao": "pcm", "ao-pcm-file": str(output), "ao-pcm-waveheader": "yes",
            "audio-format": "s16", "audio-channels": "mono", "audio-samplerate": "48000",
            "gapless-audio": "no", "idle": "yes",
            "speed": "1.0" if mode == 'legacy_scaletempo' else str(rate),
            "audio-pitch-correction": "no" if mode == 'legacy_scaletempo' else "yes",
    }
    if mode == "legacy_scaletempo":
        # Match media_kit 1.2.6 setRate with independent pitch enabled and the
        # app's pitch fixed at 1.0: tempo is the filter scale; mpv speed is pitch.
        options["af"] = f"scaletempo:scale={rate:.8f}"
    elif mode in portable:
        options['af'] = f'crisperdsp=engine={mode}'
    elif mode == 'atempo':
        options['af'] = 'lavfi-tempo=filter=atempo'
    return options


def render(library: Path, source: Path, output: Path, rate: float, mode: str) -> dict:
    player = NativePlayer(library)
    try:
        for name, value in render_options(output, rate, mode).items():
            player.option(name, value)
        if player.lib.mpv_initialize(player.handle) < 0:
            raise RuntimeError("mpv_initialize failed")
        version = player.property("mpv-version")
        configuration = player.property("mpv-configuration")
        command = (ctypes.c_char_p * 4)(b"loadfile", str(source).encode(), b"replace", None)
        result = player.lib.mpv_command(player.handle, command)
        if result < 0:
            raise RuntimeError(f"Native loadfile failed ({result})")
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            event = player.lib.mpv_wait_event(player.handle, .1).contents
            if event.event_id == 7:  # MPV_EVENT_END_FILE
                end = ctypes.cast(event.data, ctypes.POINTER(EndFile)).contents
                if end.error < 0 or end.reason != 0:
                    raise RuntimeError(f"Native EOF failed: reason={end.reason}, error={end.error}")
                break
        else:
            raise TimeoutError("Native PCM rendering did not reach EOF")
    finally:
        player.close()  # Finalize the WAV header before inspecting its length.
    duration, frequency = pcm_measurements(output)
    if abs(duration - 6 / rate) > .18:
        raise AssertionError(f"{mode} {rate}x: {duration:.3f}s output, expected {6 / rate:.3f}s")
    if abs(frequency - 440) > 12:
        raise AssertionError(f"{mode} {rate}x: pitch {frequency:.2f}Hz, expected about 440Hz")
    return {"mode": mode, "speed": rate, "output_seconds": duration, "frequency_hz": frequency, "mpv_version": version, "mpv_configuration": configuration}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument('--require-portable', action='store_true',
                        help='Require all four crisperdsp engines and native lavfi-tempo/atempo.')
    args = parser.parse_args()
    results = []
    with tempfile.TemporaryDirectory(prefix="crisper-audio-smoke-") as directory:
        directory = Path(directory)
        source = directory / "tone.wav"
        fixture(source)
        modes = ['automatic', 'legacy_scaletempo']
        if args.require_portable:
            modes += ['sonic', 'wsola', 'signalsmith', 'bungee', 'atempo']
        for mode in modes:
            for rate in (.5, 1, 1.5, 2, 3):
                results.append(render(args.library, source, directory / f"{mode}-{rate}.wav", rate, mode))
    report = {"schema_version": 1, "binary_sha256": hashlib.sha256(args.library.read_bytes()).hexdigest(), "checks": results, "claim": "Generated-tone duration and pitch smoke test only; speech quality and licensing are separate reviews.", "release_approved": False}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Native output passed {len(results)} timing/pitch checks; report: {args.output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, AssertionError, TimeoutError) as error:
        print(f"Native audio smoke test failed: {error}", file=sys.stderr)
        raise SystemExit(1)
