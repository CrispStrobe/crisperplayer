# Desktop audio: artifact evidence and controlled build candidate

Updated 11 November 2026. This records what has been inspected and what remains
unverified. The distribution policy is in [LICENSE_POLICY.md](LICENSE_POLICY.md).
The release gate reads [native_artifacts.json](../licensing/native_artifacts.json).

## The exact current Windows artifact

`media_kit_libs_windows_audio 1.0.9` downloads
`mpv-dev-x86_64-20230924-git-652a1dd.7z` from the
[audio-only release](https://github.com/media-kit/libmpv-win32-audio-build/releases/tag/2023-09-24).
The package's CMake MD5 pin matched the downloaded archive. Independent SHA-256
values from the archive and its extracted native library are:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Archive | 5,392,413 | `583af5a291fc99ae2641794ede1955c368eb4c19dc05f4f0a9c7f9456edeb6a8` |
| `libmpv-2.dll` | 15,525,902 | `0a5a0b476866c91a639a4e511e8153968f8fa23564461b0aa09acdba816164a4` |

The inspected DLL contains mpv `v0.36.0-403-g652a1dd907`, `-Dgpl=false`, and six
FFmpeg library license markers declaring LGPL version 3 or later. Its embedded
FFmpeg configuration has `--disable-gpl --disable-nonfree --enable-version3`.
The observed import table references Windows system DLLs; that does not identify
all of the third-party code statically linked inside the media DLL.

The machine-readable [observations](../licensing/evidence/windows_audio_2023-09-24.json)
are evidence for this binary, not a blanket finding that all media_kit builds
are LGPL. The `2023-09-24` release tag tree contains only a `version` file. The
binary archive contains headers, an import library and the DLL; it has no
complete corresponding-source or dependency/build manifest. Establish the exact
FFmpeg and other linked dependency revisions, modifications, build settings,
notices and replacement/relink materials before approving distribution.

Run the audit **after building**, against the DLL actually placed in the app:

```sh
python3 scripts/audit_desktop_audio.py \
  build/windows/x64/runner/Release/libmpv-2.dll \
  --expected-sha256 0a5a0b476866c91a639a4e511e8153968f8fa23564461b0aa09acdba816164a4 \
  --require-compatible-markers \
  --output build/license-evidence/windows-audio.json
```

The inspector fails on a changed hash, prohibited build flags, missing required
markers, or unapproved FFmpeg license markers. It does not execute the binary.
It always records `release_approved: false`: source and distribution review are
separate. Incidental text mentioning GPL, such as a diagnostic about another
program, is not mistaken for a license declaration. LGPL is not rejected merely
because its name contains the letters GPL.

## Linux: a source-pinned candidate, not an approved release

The current `media_kit_libs_linux 1.2.1` wrapper does not supply libmpv. Its CMake
downloads MIT-licensed mimalloc 2.1.2 and links its object by default; libmpv is
found separately at runtime. An arbitrary distro libmpv or FFmpeg cannot support
a promise that the application uses no GPL components.

[linux_audio_sources.json](../licensing/linux_audio_sources.json) pins archive
hashes for mpv 0.42.0, FFmpeg 9.0.2, libass 0.17.5 and libplacebo 7.387.0. The
archives were downloaded and hash-verified during this review. The preparation
path of [build_linux_audio.py](../scripts/build_linux_audio.py) was exercised.
**The native build has not been executed here**: this workspace lacks the
required native toolchain/development libraries. The script is an explicit
candidate for a separately provisioned build runner and does not change the
application's default loader or approve a Linux release.

The build plan:

- Builds FFmpeg with GPL, nonfree and version-three features disabled, external
  autodetection disabled, and an explicit local-audio decoder/demuxer allowlist.
  It includes a PCM-output FFmpeg command for waveform generation.
- Builds shared libraries. mpv has GPL code disabled and all optional features
  disabled unless explicitly enabled for ALSA/PulseAudio output. Rubber Band,
  scripting, plugin loading, archive support and network backends are disabled.
- Builds the required libass and libplacebo from pinned sources, without their
  optional render/demo/plugin dependencies. These libraries remain mandatory in
  current mpv even for this audio-focused build.
- Uses Meson `--wrap-mode=nofallback`; it does not silently download missing
  dependencies. No package-manager installation is performed by the script.
- Adds the optional `crisperdsp` filter using the existing pinned Sonic,
  Chromium WSOLA, Signalsmith Stretch and Bungee Basic source closure. The
  adapter participates in mpv's speed-command and source-timestamp protocol;
  it does not use a fixed-buffer effect or replace the default processor.
  `prepare_portable_mpv.py` verifies the exact upstream files before applying
  the integration, and preserves the patch and corresponding native sources.
- Records commands, logs, source archives, upstream notices, toolchain versions,
  host package inventory where available, native library hashes, ELF dynamic
  sections and post-build license-marker observations.

Start by reviewing the plan, which performs no downloads or compilation:

```sh
python3 scripts/build_linux_audio.py --workspace /absolute/path/audio-candidate
```

Prepare and verify source archives without building:

```sh
python3 scripts/build_linux_audio.py \
  --workspace /absolute/path/audio-sources \
  --source-cache /absolute/path/audio-archive-cache \
  --prepare-sources
```

For the build, use a **new workspace** on a controlled Linux runner with Python
3.12+, a C/C++ compiler, make, Meson, Ninja, NASM, pkg-config and readelf. Provide
development files for FreeType, FriBidi, HarfBuzz, ALSA and PulseAudio, plus the
Python modules required by the pinned upstream projects (including Jinja2).
Record and review the exact runner image, package versions, dependency licenses
and sources. The source archive hashes alone do not pin these host dependencies
or establish a byte-for-byte reproducible build.

```sh
python3 scripts/build_linux_audio.py \
  --workspace /absolute/path/audio-build \
  --source-cache /absolute/path/audio-archive-cache \
  --jobs 2 --build
```

Successful output is a `prefix/` installation and a separate `compliance/`
evidence directory. The build rejects unapproved license markers and records no
release approval. Upstream source archives can contain GPL-only files excluded
from the selected LGPL binary; do not copy entire source/documentation trees
into application assets without reviewing their separate licenses.

Before adopting a built candidate, inspect its final runtime dependency closure
and actual app loading path, verify that the app resolves the bundled candidate
instead of a system libmpv, and exercise the application's native playback
matrix. Its source/filter allowlist intentionally does not promise every format
available in a general-purpose FFmpeg build. Preserve compatible library
replacement, required notices and matching source/relink materials. Keep the
manifest in `needs_review` until this evidence and the actual packaging have
been reviewed.

## Windows portable source build

The same source pins are supported by
[build_windows_audio.py](../scripts/build_windows_audio.py) under a native
**MSYS2 UCRT64** shell. This builds a private FFmpeg with the same non-GPL
configuration, builds the patched mpv with WASAPI output, and installs to an
isolated prefix. It does not use an MSYS2 prebuilt FFmpeg or replace the
existing `2023-09-24` Windows binary automatically.

The Windows runner needs `base-devel`, `make`, and these UCRT64 packages (each
with the `mingw-w64-ucrt-x86_64-` prefix): `toolchain`, `python`, `meson`,
`ninja`, `pkgconf`, `nasm`, `python-jinja`, `freetype`, `fribidi`, `harfbuzz`,
and `xxhash`. The exact installation and both platform builds are recorded in
[desktop-portable-audio.yml](../.github/workflows/desktop-portable-audio.yml).
Use the UCRT64 Python, compiler and pkg-config consistently, and a workspace
path without spaces because upstream native build tools may reject them.

```sh
python scripts/build_windows_audio.py \
  --workspace /c/crisper-build/portable-windows \
  --source-cache /c/crisper-build/audio-archives \
  --jobs 2 --build
```

Its `prefix/bin/` contains the resulting media DLLs. Review and supply their
complete runtime dependency closure, including the applicable UCRT64 runtime,
font and text libraries, before distributing a bundle. The build evidence and
source patch are in `compliance/`; the recipe retains `release_approved: false`.

## Run the app with a controlled candidate

Use [run_portable_desktop.py](../scripts/run_portable_desktop.py) to launch the
app with the completed prefix. The helper selects `LIBMPV_LIBRARY_PATH` and
sets the dependent-library search path for that child process, so libmpv loads
its own FFmpeg and other libraries without replacing a system installation:

```sh
python3 scripts/run_portable_desktop.py \
  --prefix /absolute/path/audio-build/prefix -- flutter run -d linux
```

On Windows, provide the UCRT64 runtime directory when it is not already on
`PATH`. The helper prepends the candidate's `bin/` and the specified runtime
directory only for the child process:

```sh
python scripts/run_portable_desktop.py \
  --prefix C:/crisper-build/portable-windows/prefix \
  --runtime-bin C:/msys64/ucrt64/bin -- flutter run -d windows
```

At startup the local `just_audio_media_kit` adapter asks the **loaded** libmpv
for `option-info/af/choices`. The four portable choices appear only when
`crisperdsp` is present. FFmpeg Atempo appears only when both `lavfi-tempo`
and `atempo` are present. Older stock mpv builds retain Automatic and Legacy
scaletempo. A saved optional mode unavailable in a later installation falls
back to Automatic with an explanation; its saved preference remains intact.
The native player independently checks an explicit selection before loading
audio and verifies that mpv installed the requested filter.

The command after `--` can also be a built application executable. Separate
app-bundling work must preserve this dependency closure and loader selection.
A successful source build alone does not certify
an arbitrary copied DLL/`.so`, a stock package download, or a release bundle.

## Native timing and pitch smoke test

[smoke_desktop_audio.py](../scripts/smoke_desktop_audio.py) loads a supplied native
libmpv and renders a generated six-second, 440 Hz PCM tone through mpv's actual
PCM output. It checks 0.5×, 1×, 1.5×, 2× and 3× for both automatic pitch
correction and legacy scaletempo. With `--require-portable`, it also requires
Sonic, Chromium WSOLA, Signalsmith Stretch, Bungee Basic and FFmpeg Atempo,
for 35 native output checks. It verifies output duration and approximate
pitch and records the native version/configuration and binary hash. Each optional
choice must appear in the loaded filter inventory and survive configuration
readback. Native error logs, including a failed filter being disabled, fail the
check even if fallback processing would produce plausible output.
The legacy path matches media_kit 1.2.6: pitch correction is off, mpv speed stays
at the app's 1.0 pitch value, and `scaletempo:scale=<rate>` applies the tempo.

```sh
LD_LIBRARY_PATH=/absolute/path/audio-build/prefix/lib \
  python3 scripts/smoke_desktop_audio.py \
  --library /absolute/path/audio-build/prefix/lib/libmpv.so \
  --require-portable \
  --output /absolute/path/audio-build/compliance/playback-smoke.json
```

Both source builders invoke this test after compiling, and the desktop audio
workflow runs them on Linux and Windows. Check the workflow artifacts for the
result of the actual branch being reviewed. A full native build requires the
development dependencies listed above.
This test does not measure narration intelligibility, transient fidelity,
music quality, battery use, gapless transitions or interruption behavior. Those
need representative content and real target-device validation.

There is also an isolated host test of the **actual** `af_crisper.c` callbacks
against the compiled shared DSP core. It models only mpv's frame/pin contract:
24 stream cases cover all engines and six speeds; 12 further cases cover
draining a speed change, discarding old audio on seek, and changing sample rate
and channel count. Another 16 cases cover unsupported channel counts, invalid
PCM, invalid speed and failures from the internal converter. All 52 cases check
that failures end the stream without mpv bypassing the selected processor. The
stream tests check frame totals, finite PCM, source PTS, unity passthrough,
partial input larger than the core ring, and finite EOF. This harness is
separate from the full mpv build and does not claim device playback validation.

The desktop adapter also tests native error-event ordering. A fatal error from
the selected optional processor or mpv disabling the labeled filter stops the
player, fails any pending load and retains the error through subsequent buffering
and completion events. Choosing another processor and restarting creates a new
player. Existing default processors keep their existing error behavior.

```sh
python3 packages/just_audio/native/mpv/tests/run_contract.py \
  --library build/native-dsp/libcrisper_dsp.so --build-dir build/mpv-contract
```

## Other desktop migration paths

The exact `just_audio_windows 0.2.3` package is MIT and bundles no media-engine
DLL. Its implementation uses WinRT MediaPlayer and supports playlists and
playback rate, making it a relatively small Windows migration if selected.
Its actual `setPitch` handler is a no-op despite the feature table; do not expose
a pitch/algorithm control based on the table alone. Its source also calls the
deprecated `MediaPlayer.PlaybackRate` property, so native rate behavior and
multi-file/long-file seeks need Windows testing.

GStreamer is a viable Linux route with controlled LGPL plugins and explicit
`scaletempo` in the audio pipeline. A wrapper's MIT license does not approve
arbitrary GStreamer plugins or linked codecs. `audioplayers_linux 4.3.0` sets
rate through seek events but does not add scaletempo in its actual pipeline;
adapting it would need that native change and a coordinator adapter for the
current playlist and completion contract. A miniaudio wrapper likewise requires
auditing every bundled decoder and DSP implementation; its top-level MIT label
does not establish the license of an included AAC decoder.

## Primary implementation references

- [mpv licensing and linked-library caveat](https://github.com/mpv-player/mpv/blob/master/Copyright)
- [mpv 0.42.0 required dependencies](https://github.com/mpv-player/mpv/blob/v0.42.0/meson.build)
- [FFmpeg license and distribution guidance](https://ffmpeg.org/legal.html)
- [GStreamer plugin licensing](https://gstreamer.freedesktop.org/documentation/frequently-asked-questions/general.html)
- [GStreamer scaletempo](https://gstreamer.freedesktop.org/documentation/audiofx/scaletempo.html)
- [just_audio_windows 0.2.3](https://pub.dev/packages/just_audio_windows/versions/0.2.3)
- [WinRT playback rate](https://learn.microsoft.com/en-us/uwp/api/windows.media.playback.mediaplayer.playbackrate)
