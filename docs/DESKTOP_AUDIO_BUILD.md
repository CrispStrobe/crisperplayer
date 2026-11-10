# Desktop audio: artifact evidence and controlled build candidate

Reviewed 10 November 2026. This records what has been inspected and what remains
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

## Native timing and pitch smoke test

[smoke_desktop_audio.py](../scripts/smoke_desktop_audio.py) loads a supplied native
libmpv and renders a generated six-second, 440 Hz PCM tone through mpv's actual
PCM output. It checks 0.5×, 1×, 1.5×, 2× and 3× for both automatic pitch
correction and legacy scaletempo. It verifies output duration and approximate
pitch and records the native version/configuration and binary hash.
The legacy path matches media_kit 1.2.6: pitch correction is off, mpv speed stays
at the app's 1.0 pitch value, and `scaletempo:scale=<rate>` applies the tempo.

```sh
LD_LIBRARY_PATH=/absolute/path/audio-build/prefix/lib \
  python3 scripts/smoke_desktop_audio.py \
  --library /absolute/path/audio-build/prefix/lib/libmpv.so \
  --output /absolute/path/audio-build/compliance/playback-smoke.json
```

The Linux builder invokes this test after compiling. The native test has not
been run in this workspace because no controlled native build is available.
This test does not measure narration intelligibility, transient fidelity,
music quality, battery use, gapless transitions or interruption behavior. Those
need representative content and real target-device validation.

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
