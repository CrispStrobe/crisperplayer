#!/usr/bin/env python3
"""Inspect exact media binaries without treating embedded strings as legal approval.

This deliberately does not load or execute the inspected library. The report is
evidence for the separate release license gate, not a replacement for matching
source, dependency, notice, and LGPL distribution review.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys


REQUIRED_FFMPEG_LIBRARIES = {
    "libavcodec", "libavfilter", "libavformat", "libavutil", "libswresample",
    "libswscale",
}
FORBIDDEN_FLAGS = re.compile(
    r"(?<!\S)(?:--enable-(?:gpl|nonfree)|-Dgpl=(?:true|enabled))(?=\s|$)"
)
LICENSE_MARKER = re.compile(
    r"\b(lib(?:avcodec|avfilter|avformat|avutil|swresample|swscale)) license: "
    r"([^\r\n]+)"
)
LGPL_MARKER = re.compile(r"^LGPL version (2\.1|3) or later$")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inspect_bytes(data: bytes, *, role: str) -> dict:
    strings = sorted({item.decode("ascii") for item in re.findall(rb"[\x20-\x7e]{8,}", data)})
    mpv_configurations = sorted({
        item.removeprefix("Configuration: ") for item in strings
        if "-Dgpl=" in item and "-Dlibmpv=" in item
    })
    # FFmpeg may place the configuration beside another printable constant.
    # Keep the full observed string; do not silently edit its evidence.
    ffmpeg_configurations = sorted({
        item for item in strings
        if "--disable-gpl" in item or "--enable-gpl" in item
        or "--disable-nonfree" in item or "--enable-nonfree" in item
    })
    licenses: dict[str, list[str]] = {}
    for item in strings:
        match = LICENSE_MARKER.search(item)
        if match:
            licenses.setdefault(match[1], []).append(match[2])
    forbidden = []
    missing = []
    for item in [*mpv_configurations, *ffmpeg_configurations]:
        if FORBIDDEN_FLAGS.search(item):
            forbidden.append("An observed build configuration enables GPL or nonfree code.")
    for library, values in licenses.items():
        for value in values:
            if not LGPL_MARKER.fullmatch(value):
                forbidden.append(f"{library} reports an unapproved license: {value}")
    if role in {"mpv", "combined"}:
        if not mpv_configurations:
            missing.append("No mpv build configuration was found.")
        elif not all(re.search(r"(?:^|\s)-Dgpl=false(?:\s|$)", item) for item in mpv_configurations):
            missing.append("Not every observed mpv configuration explicitly disables GPL code.")
    if role in {"ffmpeg", "combined"}:
        if not ffmpeg_configurations:
            missing.append("No FFmpeg build configuration was found.")
        elif not all("--disable-gpl" in item and "--disable-nonfree" in item for item in ffmpeg_configurations):
            missing.append("Not every observed FFmpeg configuration explicitly disables GPL and nonfree code.")
        if not licenses:
            missing.append("No supported FFmpeg license marker was found.")
        if role == "combined":
            absent = REQUIRED_FFMPEG_LIBRARIES - licenses.keys()
            if absent:
                missing.append("Missing FFmpeg license markers: " + ", ".join(sorted(absent)))
    verdict = "forbidden_markers" if forbidden else "insufficient_evidence" if missing else "compatible_markers"
    return {
        "role": role,
        "marker_verdict": verdict,
        "mpv_versions": [item for item in strings if re.fullmatch(r"mpv v[\w.+-]+", item)],
        "mpv_configurations": mpv_configurations,
        "ffmpeg_configurations": ffmpeg_configurations,
        "ffmpeg_license_markers": licenses,
        "findings": sorted(set(forbidden + missing)),
        "release_approved": False,
        "limitations": [
            "Strings can corroborate build flags; they cannot identify all statically linked code.",
            "Matching corresponding source, modifications, linked dependencies, notices and replacement/relink obligations require separate review.",
            "No app-store compatibility or complete license-compliance conclusion is made by this scan.",
        ],
    }


def inspect(path: Path, *, role: str, expected_sha256: str | None = None) -> dict:
    data = path.read_bytes()
    observed = hashlib.sha256(data).hexdigest()
    report = inspect_bytes(data, role=role)
    report.update({"filename": path.name, "size_bytes": len(data), "sha256": observed})
    if expected_sha256 and observed != expected_sha256.lower():
        report["marker_verdict"] = "artifact_mismatch"
        report["findings"].append("The binary does not match the explicitly reviewed SHA-256.")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--role", choices=("combined", "mpv", "ffmpeg"), default="combined")
    parser.add_argument("--expected-sha256", help="Fail if the exact artifact has changed.")
    parser.add_argument("--archive", type=Path, help="Also record the original download's SHA-256 and size.")
    parser.add_argument("--archive-url")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--require-compatible-markers", action="store_true", help="Evidence check only; this never approves a release.")
    args = parser.parse_args()
    if args.expected_sha256 and not re.fullmatch(r"[0-9a-fA-F]{64}", args.expected_sha256):
        parser.error("--expected-sha256 must contain exactly 64 hexadecimal digits")
    try:
        report = {"schema_version": 1, "artifact": inspect(args.binary, role=args.role, expected_sha256=args.expected_sha256)}
        if args.archive:
            report["archive"] = {
                "filename": args.archive.name, "sha256": sha256(args.archive),
                "size_bytes": args.archive.stat().st_size, "url": args.archive_url,
            }
        encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(encoded, encoding="utf-8")
        else:
            print(encoded, end="")
        verdict = report["artifact"]["marker_verdict"]
        print(f"{args.binary.name}: {verdict}; release approval remains separate", file=sys.stderr)
        return int(verdict == "artifact_mismatch" or (args.require_compatible_markers and verdict != "compatible_markers"))
    except (OSError, ValueError) as error:
        print(f"Native artifact inspection failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
