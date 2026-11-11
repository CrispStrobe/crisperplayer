# Portable native speed processors

CrisperPlayer reuses its existing Sonic C, Chromium-derived WSOLA, Signalsmith
Stretch and Bungee Basic source across native playback integrations. Android
keeps Media3 Sonic, Apple keeps Time Domain, and Windows/Linux keep mpv
Automatic as their defaults. An optional processor must have a working decoder,
PCM processing and output path before the application treats it as available.

## Platform coverage

| Platform | Default route | Optional portable route | Availability boundary |
| --- | --- | --- | --- |
| Android | Media3 Sonic | Existing Media3/JNI integration for WSOLA, Signalsmith and Bungee Basic | Native processor library must be packaged for the device ABI. Sonic continues to use Media3. |
| iOS and macOS | AVFoundation Time Domain; Spectral remains selectable | Local audio decoded by Apple's APIs, processed by the shared core and rendered through AVAudioEngine | Portable choices are for supported local files. They do not make the AVPlayer streaming decoder a custom PCM source. |
| Linux and Windows | Existing mpv Automatic; Legacy scaletempo remains selectable | The CrisperPlayer filter compiled into a controlled libmpv links the shared core | The loaded library must expose the custom filter. A stock system library or historical Windows DLL does not acquire the filter from a Flutter package update. |
| Browser | Existing browser media playback | No new portable processor integration in this change | The separate Pages player remains on its browser-controlled audio route. |

The desktop adapter checks capabilities of the library actually loaded. The
controlled mpv route keeps the existing decoder, output device and source
timeline. FFmpeg atempo is an additional desktop choice only where the loaded
mpv exposes its tempo integration. Processor selection must not append another
pitch-correcting speed stage or silently label a fallback as the selected engine.

Controlled desktop builders use the pinned mpv 0.42.0 and FFmpeg source manifest,
apply the reviewed CrisperPlayer filter, and retain the added source with build
evidence. Use a fresh build workspace:

```sh
# Linux, with the development toolchain/dependencies described in DESKTOP_AUDIO_BUILD.md
python3 scripts/build_linux_audio.py --workspace build/linux-audio --build

# Windows, from an MSYS2 UCRT64 shell with the documented build dependencies
python scripts/build_windows_audio.py --workspace build/windows-audio --build
```

The Windows builder compiles its private FFmpeg configuration with GPL/nonfree
features excluded; it does not link an arbitrary MSYS2 FFmpeg package. These
source recipes enable an optional playback path. A candidate still needs actual
build, loading, packaging and license evidence before it replaces a release's
recorded native artifact.

The shared core accepts mono/stereo 8–192 kHz PCM and speeds from 0.50× to
3.00×. Its public contract preserves pitch at 1.0; selecting these processors
does not imply a new independent pitch-shift control. At unity speed the core
passes samples through unchanged. Algorithm support over this range is separate
from a claim about perceptual quality: Signalsmith's upstream guidance remains
approximately 0.75×–1.5×, and comparisons should use the same narration and
music-backed passages at matched listening levels.

## Source time and stream boundaries

Resume positions, bookmarks, chapters, played ranges and journal entries use
the original audio timeline. The native core reports source frames represented
by output already delivered, separately from decoded input and queued output.
Adapters must account for output still waiting in the device or player queue.
Decoded lookahead cannot advance the displayed source position.

The bounded streaming interface accepts partial writes, preserves unconsumed
input, and reports how many output frames were read. End-of-stream performs a
finite drain and produces exactly the rounded input-frame count divided by the
speed. Seek/reset discards old input, output and lookahead. Speed changes must
drain or explicitly restart the current processing segment; a setting change
cannot leave audio from two different speed mappings in one untracked queue.

The existing Bungee adapter deliberately uses its granular interface with a
rebased input origin. It does not replace that implementation with a cumulative
32-bit `Stream` input counter, which would be unsuitable for long audiobooks.

## License and provenance

The seven upstream components and 258 retained original source/notice files
remain unchanged. Their exact revisions and hashes are in
[`vendor/manifest.json`](../packages/just_audio/native/crisper_dsp/vendor/manifest.json):

| Component | Grant retained |
| --- | --- |
| Sonic C | Apache-2.0 |
| Chromium WSOLA originals and maintained derived implementation | BSD-3-Clause |
| Signalsmith Stretch and Signalsmith Linear | MIT |
| Bungee Basic | MPL-2.0 |
| Selected Eigen Core closure | MPL-2.0, with original BSD/Apache notices |
| PFFFT/FFTPACK | Original permissive NCAR/UCAR grant, recorded as `LicenseRef-PFFFT-FFTPACK` |

All native integrations retain `EIGEN_MPL2_ONLY`. Bungee Pro, unsupported Eigen
modules, Sonic Speedy, external FFT backends and runtime processor downloads
remain excluded. The independent core and Apple adapters retain MIT. The
maintained Chromium fork remains separately BSD-3-Clause. The desktop Flutter
adapter retains its upstream Unlicense; the custom mpv integration and linked
libmpv/FFmpeg keep their separately declared grants and obligations.

Original notices are registered in the app on every native platform. The shared
notice asset keeps its historical `assets/licenses/ANDROID-DSP.txt` filename.
It includes immutable source links and the original license texts. MPL source
availability requirements apply to every binary that includes the covered code.
The controlled desktop library additionally needs matching LGPL source/build
materials and the applicable library replacement/relink route.

The distribution checker requires `portable-native-speed-processors` on all
five native targets. It checks the exact native manifest and restricts the
PFFFT license reference to the reviewed notice bytes and source component.
Wrapper/package grants do not approve native payloads. See
[the policy](LICENSE_POLICY.md) and [recorded evidence](../licensing/README.md).

## Verification boundaries

The native host tools execute all four actual algorithms and test timing,
preserved tone pitch, channel handling, stream boundaries, backpressure and
reset behavior. They can be run without downloading a new DSP dependency:

```sh
python3 packages/just_audio/native/crisper_dsp/tools/build_host.py --jobs 2
python3 packages/just_audio/native/crisper_dsp/tools/test_streaming.py \
  --library build/native-dsp/libcrisper_dsp.so \
  --report build/native-dsp/test-report.json
python3 -m unittest scripts.tests.test_distribution_licenses
```

A controlled Linux x86-64 libmpv build has also passed 35 actual native PCM
checks: Automatic, Legacy scaletempo, Sonic, WSOLA, Signalsmith, Bungee and
atempo at 0.5×, 1×, 1.5×, 2× and 3×. The smoke test checks the installed
optional filter and rejects native error messages, so a correctly timed
fallback cannot silently satisfy it. Exact candidate and report hashes are
recorded in [the host evidence](../licensing/evidence/portable_linux_host_2026-11-11.json).
This is synthetic file-output evidence; Flutter app packaging, audio-device
playback and the other native targets retain their separate validation needs.

After resolving the real Flutter dependency graph, the existing distribution
report checks the complete production dependency inventory and native evidence:

```sh
flutter pub get
python3 scripts/check_distribution_licenses.py --report --platform all \
  --output build/licensing/portable-processors.json
```

An absent SDK/package graph is an incomplete audit, not a clean report. Native
source verification and unit tests do not establish Apple device playback,
Windows/Linux package loading, background operation, interruption handling,
Bluetooth routing, listening quality or battery cost. Each target artifact
remains pending in the inventory until that evidence is collected; the shared
source review does not approve all platform binaries at once. Existing release
and TestFlight enforcement remains enabled.
