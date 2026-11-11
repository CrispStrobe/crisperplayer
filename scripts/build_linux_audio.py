#!/usr/bin/env python3
"""Build an isolated, source-pinned LGPL audio candidate, never a release approval.

No package-manager installation and no Meson dependency downloads are performed.
The default prints a plan. --prepare-sources verifies and unpacks exact archives;
--build additionally requires an already provisioned Linux toolchain.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import urllib.request

from audit_desktop_audio import inspect, sha256
from prepare_portable_mpv import prepare as prepare_portable_mpv


REPOSITORY = Path(__file__).resolve().parents[1]
LOCK = REPOSITORY / "licensing/linux_audio_sources.json"
SYSTEM_PACKAGES = ("freetype2", "fribidi", "harfbuzz", "alsa", "libpulse")
FFMPEG_OPTIONS = [
    "--disable-gpl", "--disable-nonfree", "--disable-version3",
    "--disable-autodetect", "--disable-everything", "--disable-network",
    "--disable-static", "--enable-shared", "--enable-pic",
    "--disable-doc", "--disable-debug", "--disable-ffplay", "--disable-ffprobe",
    "--disable-avdevice",
    "--enable-ffmpeg", "--enable-avcodec", "--enable-avformat", "--enable-avfilter",
    "--enable-avutil", "--enable-swresample", "--enable-swscale",
    "--enable-protocol=file,pipe",
    "--enable-demuxer=aac,ac3,aiff,asf,au,flac,matroska,mov,mp3,ogg,wav,wv",
    "--enable-parser=aac,aac_latm,ac3,flac,mpegaudio,opus,vorbis",
    "--enable-decoder=aac,aac_fixed,aac_latm,ac3,alac,flac,mp1,mp1float,mp2,mp2float,mp3,mp3float,opus,vorbis,wavpack,wmav1,wmav2,wmapro,wmalossless,wmavoice,pcm*",
    "--enable-encoder=pcm_s16le", "--enable-muxer=pcm_s16le,wav",
    "--enable-filter=abuffer,abuffersink,aformat,anull,aresample,asetpts,atempo",
]
MESON_COMMON = [
    "--wrap-mode=nofallback", "--buildtype=release", "--libdir=lib",
    "-Ddefault_library=shared", "-Dauto_features=disabled",
]
MESON_OPTIONS = {
    "libass": ["-Drequire-system-font-provider=false", "-Dasm=disabled"],
    "libplacebo": ["-Ddemos=false", "-Dtests=false", "-Dbench=false", "-Dfuzz=false"],
    "mpv": [
        "-Dgpl=false", "-Dlibmpv=true", "-Dcplayer=false", "-Dbuild-date=false",
        "-Dtests=false", "-Dfuzzers=false", "-Dgl=disabled", "-Dlua=disabled",
        "-Dcplugins=disabled", "-Djavascript=disabled", "-Drubberband=disabled",
        "-Dlibarchive=disabled", "-Dlibcurl=disabled", "-Dalsa=enabled", "-Dpulse=enabled",
    ],
}


def download(source: dict, destination: Path) -> None:
    if not destination.exists():
        temporary = destination.with_suffix(destination.suffix + ".partial")
        request = urllib.request.Request(source["url"], headers={"User-Agent": "CrisperPlayer-native-audio-build"})
        with urllib.request.urlopen(request, timeout=60) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        if sha256(temporary) != source["sha256"]:
            temporary.unlink()
            raise ValueError(f"Downloaded source hash mismatch: {source['id']}")
        temporary.replace(destination)
    if sha256(destination) != source["sha256"]:
        raise ValueError(f"Cached source hash mismatch: {destination}")


def extract(archive: Path, destination: Path) -> Path:
    if destination.exists():
        raise ValueError(f"Refusing to reuse an unpacked source tree: {destination}")
    destination.mkdir()
    with tarfile.open(archive) as source:
        if not hasattr(tarfile, "data_filter"):
            raise ValueError("Use Python 3.12+ or a Python version with tarfile.data_filter")
        source.extractall(destination, filter="data")
    roots = list(destination.iterdir())
    if len(roots) != 1 or not roots[0].is_dir():
        raise ValueError(f"Expected a single source root in {archive}")
    return roots[0]


def build_commands(source_roots: dict[str, Path], workspace: Path, jobs: int,
                   target: str = 'linux') -> list[dict]:
    prefix = workspace / "prefix"
    builds = workspace / "build"
    commands = [{
        "cwd": str(builds / "ffmpeg"),
        "argv": [*(['bash'] if target == 'windows' else []),
                 (source_roots["ffmpeg"] / "configure").as_posix(), f"--prefix={prefix.as_posix()}", *FFMPEG_OPTIONS,
                 *(['--disable-pthreads', '--enable-w32threads'] if target == 'windows' else [])],
    }, {
        "cwd": str(builds / "ffmpeg"), "argv": ["make", f"-j{jobs}"],
    }, {
        "cwd": str(builds / "ffmpeg"), "argv": ["make", "install"],
    }]
    for name in ("libass", "libplacebo", "mpv"):
        build = builds / name
        options = MESON_OPTIONS[name]
        if name == 'mpv' and target == 'windows':
            options = [option for option in options
                       if option not in ('-Dalsa=enabled', '-Dpulse=enabled')]
            options += ['-Dwasapi=enabled']
        commands.extend([
            {"cwd": str(workspace), "argv": ["meson", "setup", str(build), str(source_roots[name]), f"--prefix={prefix}", *MESON_COMMON, *options]},
            {"cwd": str(workspace), "argv": ["meson", "compile", "-C", str(build), "-j", str(jobs)]},
            {"cwd": str(workspace), "argv": ["meson", "install", "-C", str(build)]},
        ])
    return commands


def capture(argv: list[str], environment: dict) -> str:
    return subprocess.check_output(argv, env=environment, text=True, stderr=subprocess.STDOUT).strip()


def main(target: str = 'linux') -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, required=True, help="An isolated output directory; never /usr or an existing installation.")
    parser.add_argument("--source-cache", type=Path, help="Optional reusable download cache, always hash checked.")
    parser.add_argument("--jobs", type=int, default=2)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--prepare-sources", action="store_true")
    mode.add_argument("--build", action="store_true")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    workspace = args.workspace.resolve()
    if workspace == Path(workspace.anchor) or workspace == REPOSITORY or workspace in REPOSITORY.parents:
        parser.error("Use a dedicated build output directory")
    lock = json.loads(LOCK.read_text())
    sources = {item["id"]: item for item in lock["sources"]}
    expected_ids = {"ffmpeg", "mpv", "libass", "libplacebo"}
    if set(sources) != expected_ids:
        raise ValueError("The reviewed build plan requires exactly FFmpeg, mpv, libass and libplacebo")
    hypothetical = {name: workspace / "source" / name / "upstream-root" for name in sources}
    if not args.prepare_sources and not args.build:
        print(json.dumps({"status": "plan_only_not_release_approved", "target": target,
                          "sources": lock["sources"],
                          "system_packages": SYSTEM_PACKAGES if target == 'linux' else SYSTEM_PACKAGES[:3],
                          "portable_dsp": "Sonic, Chromium WSOLA, Signalsmith Stretch, Bungee Basic",
                          "commands": build_commands(hypothetical, workspace, args.jobs, target)}, indent=2))
        return 0
    if (workspace / "source").exists() or (workspace / "prefix").exists():
        raise ValueError("Use a new workspace; source or install trees already exist")
    workspace.mkdir(parents=True, exist_ok=True)
    downloads = (args.source_cache or workspace / "archives").resolve()
    downloads.mkdir(parents=True, exist_ok=True)
    (workspace / "source").mkdir()
    source_roots = {}
    for name, source in sources.items():
        archive = downloads / source["archive"]
        download(source, archive)
        source_roots[name] = extract(archive, workspace / "source" / name)
    compliance = workspace / "compliance"
    compliance.mkdir()
    shutil.copy2(LOCK, compliance / LOCK.name)
    shutil.copy2(__file__, compliance / Path(__file__).name)
    prepare_portable_mpv(source_roots['mpv'], compliance / 'portable-dsp-source.json')
    shutil.copytree(source_roots['mpv'] / 'crisper-dsp', compliance / 'portable-dsp-sources')
    shutil.copy2(source_roots['mpv'] / 'audio/filter/af_crisper.c', compliance / 'af_crisper.c')
    command_plan = build_commands(source_roots, workspace, args.jobs, target)
    (compliance / "commands.json").write_text(json.dumps(command_plan, indent=2) + "\n")
    if args.prepare_sources:
        print(f"Verified source archives and recorded the plan in {workspace}; no native build or release approval performed.")
        return 0
    if target == 'linux' and not sys.platform.startswith('linux'):
        raise ValueError('Use Linux for this recipe or build_windows_audio.py under MSYS2 UCRT64')
    if target == 'windows' and sys.platform != 'win32':
        raise ValueError('The Windows candidate requires native MSYS2 UCRT64 Python and toolchain')
    binary_tool = 'readelf' if target == 'linux' else 'objdump'
    for tool in ("cc", "make", "meson", "ninja", "pkg-config", "nasm", binary_tool):
        if not shutil.which(tool):
            raise ValueError(f"Missing build tool: {tool}; see docs/DESKTOP_AUDIO_BUILD.md")
    environment = dict(os.environ)
    prefix = workspace / "prefix"
    environment["PKG_CONFIG_PATH"] = os.pathsep.join(filter(None, (
        str(prefix / 'lib/pkgconfig'), environment.get('PKG_CONFIG_PATH'))))
    environment["LD_LIBRARY_PATH"] = str(prefix / "lib")
    environment['PATH'] = str(prefix / 'bin') + os.pathsep + environment['PATH']
    environment["LC_ALL"] = "C"
    environment["SOURCE_DATE_EPOCH"] = "1793836800"
    inventory = {
        "tools": {tool: capture([tool, "--version"], environment) for tool in ("cc", "make", "meson", "ninja", "pkg-config", "nasm")},
        "system_packages": {name: {"version": capture(["pkg-config", "--modversion", name], environment), "link_flags": capture(["pkg-config", "--libs", name], environment)} for name in (SYSTEM_PACKAGES if target == 'linux' else SYSTEM_PACKAGES[:3])},
        "status": "candidate_not_release_approved",
        "source_date_epoch": environment["SOURCE_DATE_EPOCH"],
    }
    if shutil.which("dpkg-query"):
        inventory["dpkg_packages"] = capture(["dpkg-query", "-W", "-f=${Package}\t${Version}\t${Architecture}\n"], environment)
    (compliance / "toolchain.json").write_text(json.dumps(inventory, indent=2) + "\n")
    (workspace / "build/ffmpeg").mkdir(parents=True)
    with (compliance / "build.log").open("w") as log:
        for command in command_plan:
            print("Running", command["argv"][0], flush=True)
            log.write(json.dumps(command) + "\n")
            log.flush()
            subprocess.run(command["argv"], cwd=command["cwd"], env=environment, stdout=log, stderr=subprocess.STDOUT, check=True)
    binaries = {}
    inspections = []
    candidates = (prefix / 'lib').glob('*.so*') if target == 'linux' else (prefix / 'bin').glob('*.dll')
    for path in sorted(candidates):
        if path.is_symlink() or not path.is_file():
            continue
        binaries[path.name] = {"sha256": sha256(path), "dynamic_section": capture([binary_tool, '-d' if target == 'linux' else '-p', str(path)], environment)}
        if path.name.startswith("libmpv"):
            inspections.append(inspect(path, role="mpv"))
        elif path.name.startswith(("libav", "libsw", "avcodec-", "avfilter-", "avformat-", "avutil-", "swresample-", "swscale-")):
            inspections.append(inspect(path, role="ffmpeg"))
    if not any(item["role"] == "mpv" for item in inspections) or len(inspections) < 7:
        raise ValueError("The expected libmpv and six FFmpeg libraries were not all produced")
    (compliance / "binary-evidence.json").write_text(json.dumps({"binaries": binaries, "inspections": inspections, "release_approved": False}, indent=2) + "\n")
    if any(item["marker_verdict"] != "compatible_markers" for item in inspections):
        raise ValueError("A built library did not pass the native marker checks")
    (compliance / "source-archives").mkdir()
    for source in sources.values():
        shutil.copy2(downloads / source["archive"], compliance / "source-archives" / source["archive"])
    notices = compliance / "upstream-notices"
    for name, source in source_roots.items():
        (notices / name).mkdir(parents=True)
        for path in source.iterdir():
            if path.is_file() and path.name.upper().startswith(("LICENSE", "COPYING", "COPYRIGHT", "NOTICE")):
                shutil.copy2(path, notices / name / path.name)
    player_library = prefix / ('lib/libmpv.so' if target == 'linux' else 'bin/libmpv-2.dll')
    subprocess.run([sys.executable, str(REPOSITORY / "scripts/smoke_desktop_audio.py"),
                    '--library', str(player_library), '--require-portable',
                    '--output', str(compliance / 'playback-smoke.json')], env=environment, check=True)
    print(f"Candidate built in {prefix}. Review {compliance}, full dependency closure, and target distribution obligations before changing any license-gate status.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, tarfile.TarError, subprocess.CalledProcessError) as error:
        print(f"LGPL audio candidate build stopped: {error}", file=sys.stderr)
        raise SystemExit(1)
