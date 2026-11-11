# External dependency license policy and audio processors

Reviewed 11 November 2026. The project requirement is an openly distributable
application that can also be submitted to app stores, without GPL-only or
AGPL-only **external** dependencies. MIT, Apache-2.0, BSD and comparable
permissive licenses are preferred. MPL and LGPL are permitted when their
actual distribution obligations are met.

The owner's later restriction for **new external decoder additions** is
stricter: select MIT, Apache-2.0, BSD, ISC, zlib, MIT-0, Unlicense, CC0 or an
explicitly reviewed equivalent permissive source closure. This includes native
dependencies and copied tables. GPL, LGPL and MPL are not accepted for new
decoder additions. Existing MPL DSP choices and platform system libraries
remain separate; their notices and obligations are unchanged.

## Audio architecture priority

The owner clarified on 11 November 2026 that playback should use native
platform paths and reduce reliance on mpv and LGPL code. License eligibility
does not make another LGPL dependency the preferred architecture. Preserve
the existing permissive/MPL DSP core and connect it directly to platform
decoding and output APIs where practical.

The custom mpv filter and controlled desktop build were a compatibility
prototype. Their adapters, runtime packages and build recipes have now been
removed from the current path. Windows/Linux use Dart transport, bounded
Glint decoding, the shared DSP core and native miniaudio output. Duration
probing and waveform generation use the same decoder. Do not reintroduce
FFmpeg or another LGPL stack solely to increase the processor/codec count.

This preference does not relabel existing LGPL components, waive their
obligations, or impose a new blanket ban on platform system libraries. See
[portable native playback](PORTABLE_AUDIO_PROCESSORS.md) and
[decoder choices and remaining LGPL dependencies](AUDIO_DEPENDENCIES.md)
for current implementation and source boundaries.

This is an engineering policy and an evidence record. A package name, a build
flag, or a passing script does not establish legal compliance or guarantee
acceptance by an app store.

## Project-owned code

The project owner explicitly confirmed on 10 November 2026 that CrisperPlayer
and `crisp_storage` are their own code, may be dual licensed, and already use
section 7 additional permissions for App Store distribution. Their AGPL
declarations are therefore **not blockers under this external dependency
policy**. No new license choice or further ownership confirmation is required.

The inventory records this owner-provided authorization for the exact application
and pinned `crisp_storage` source. Their existing license notices remain intact.
This does not exempt their external dependencies, copied third-party material,
or arbitrary packages published under the same account. The checker continues
to traverse the complete production dependency graph and validate source and
license evidence.

This record describes the owner's distribution authority; it does not invent
or replace the text of any published additional permission or third-party grant.

## External native components requiring evidence

| Component | Evidence in this checkout | Consequence |
| --- | --- | --- |
| Direct Windows/Linux audio | Glint's selected MIT/Apache source closure, output-only miniaudio and the existing shared DSP core. | Preserve exact source/artifact identity and all original notices; passing playback tests do not complete distribution review. |
| SMB/NAS | `crisp_storage → dart_smb2 0.2.1 → libsmb2-r9`; the BSD wrapper bundles an LGPL-2.1-or-later native library. | Keep source/replacement and target artifact reviews explicit. The successful Linux bundle audit confirms `libdart_smb2.so`; other targets follow the platform build hook. |
| Linux host libraries | GTK/GLib, libsecret, PulseAudio/ALSA and glibc-based runtime dependencies are separate system libraries. | Record the exact target distribution's dependency closure. Removing mpv does not remove these LGPL system dependencies. Optional JACK loading is disabled in the owned output configuration. |

Filen and Internxt are MPL-2.0 components. Their source availability and notice
requirements continue to apply. `libsmb2` is a separate LGPL native component,
so choosing a permissive audio processor does not by itself finish the app's
license audit.

## Historical media_kit/mpv license boundary

`media_kit` itself is MIT, and `just_audio_media_kit` is Unlicense. Their
native libmpv/FFmpeg payloads have independent licenses. The architecture
change removed that playback dependency; it did not reclassify the wrappers
as LGPL. Retired payload identities remain historical inventory evidence.

mpv is GPL-2.0-or-later by default, but its libmpv build can be distributed under
LGPL-2.1-or-later when GPL-only files are excluded. The upstream option is
`-Dgpl=false`. mpv explicitly cautions that this flag alone is not a license
grant: linked dependencies, including FFmpeg, still determine the resulting
license. mpv's GPL documentation and example files are also separate from an
LGPL binary and should not be copied into a no-GPL distribution indiscriminately.

Historical controlled builds therefore recorded source revisions/hashes and
the exact GPL/nonfree exclusions. Their evidence cannot approve an unrelated
system build or a different dependency configuration. They are not a current
release audio payload.

An LGPL component is not automatically approved for every store or packaging
method. Relinking/replacement requirements, the exact LGPL version, signing,
installation restrictions and applicable distribution terms need to be
resolved for the actual artifact. Apple's program agreement requires
compliance with included open-source licenses. Prefer platform playback or
permissive DSP on Apple platforms to avoid adding this burden to audio.

## Quality options that fit the policy

| Processor | License or platform basis | Decision |
| --- | --- | --- |
| Apple Time Domain / Spectral | AVFoundation system API; the maintained just_audio adapter is MIT. | Offer both on iOS/macOS. Time Domain remains the voice default; Spectral is an optional, more computationally intensive alternative. |
| Sonic | Apache-2.0 native library and implementation in AndroidX Media3. | Keep Media3 Sonic as Android's default. The pinned C core is optional on Apple local files and is the direct native desktop default. |
| mpv scaletempo2 / scaletempo | Available in an appropriately built LGPL libmpv. | Historical choices, removed from the current desktop path. |
| Bungee Basic | MPL-2.0; the selected Eigen Core and PFFFT source and original notices are pinned. | Optional shared native processor for Android, Apple local files and direct native desktop playback. `EIGEN_MPL2_ONLY` excludes GPL modules; proprietary Bungee Pro is not included. |
| Signalsmith Stretch | MIT, with the selected MIT Signalsmith Linear implementation. | Optional shared native processor for moderate rate changes. Upstream describes best time-stretch quality around 0.75×–1.5×; do not assume a 2×–3× speech improvement. |
| Chromium WSOLA fork | BSD-3-Clause; retained upstream originals and the maintained extraction have separate provenance. | Reuse the existing portable processor on the same native paths. The fork does not bring Chromium's browser/media runtime or mpv's source license into the shared core. |
| FFmpeg atempo | Part of an LGPL-configured FFmpeg build. | Historical comparison only; no longer a desktop playback option. |
| SoundTouch | LGPL-2.1. | Not integrated; adding another LGPL processor does not meet the native architecture priority. |
| Rubber Band | GPL-2.0-or-later or a separately purchased commercial license. | Excluded from the openly reproducible default dependency set under this policy. A commercial license for one publisher does not give all open-source recipients the same commercial redistribution rights. |

The word “quality” describes an available processing choice, not a measured
claim that one algorithm beats every other algorithm. Compare the same speech
and speech-with-music passages at matched level and several speeds, and measure
CPU/battery use, seek latency and interruption behavior on target devices.

The [portable processor record](PORTABLE_AUDIO_PROCESSORS.md) describes platform
integration and availability; the [Android record](ANDROID_AUDIO_PROCESSORS.md)
retains the Media3/JNI details. The shared core reuses the same seven upstream
components and 258 retained source/notice files, without introducing a new
external DSP license. Per-file hashes and original notices remain included.
The independent core and Apple adapters are MIT licensed; the maintained
Chromium extraction remains BSD-3-Clause. Historical desktop mpv modifications
and linked libraries retain their separate license/source identity in Git.

`portable-native-speed-processors` is required in the native inventory for all
five native targets. Its source manifest and exact permissive PFFFT notice are
checked for each target; the prior Android-only scope cannot exempt Apple or
desktop. The shared source review does not promote target binaries to reviewed
status. Device, simulator, desktop and package-specific artifact evidence remains
pending until it is actually collected.

## Enforced checks and current evidence

The [recorded inventory](../licensing/README.md) identifies exact dependency
versions, source/license hashes and native build inputs. Routine CI writes a
nonblocking report; binary-release and TestFlight workflows enforce it before
signing or uploading. External GPL/AGPL grants and unresolved external native
evidence are blockers; the explicitly authorized project-owned components are
reported separately. The Windows build additionally checks the DLL actually
placed in the application against its reviewed SHA-256 and native markers.

See [desktop artifact findings and the Linux candidate recipe](DESKTOP_AUDIO_BUILD.md)
and [verification results and remaining limits](LICENSE_VALIDATION.md).

## Primary sources

- [mpv licensing, excluded files and linked-library caveat](https://github.com/mpv-player/mpv/blob/master/Copyright)
- [FFmpeg licensing and corresponding-source guidance](https://ffmpeg.org/legal.html)
- [GNU LGPL 2.1, especially section 6](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)
- [Mozilla MPL 2.0 FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/)
- [Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)
- [Apple time-pitch algorithms](https://developer.apple.com/documentation/avfoundation/time-pitch-algorithm-settings)
- [Sonic speech-oriented processing and Apache-2.0 license](https://github.com/waywardgeek/sonic)
- [Signalsmith Stretch and its MIT license](https://github.com/Signalsmith-Audio/signalsmith-stretch)
- [Bungee Basic, dependencies and license](https://github.com/bungee-audio-stretch/bungee)
- [SoundTouch licensing](https://www.surina.net/soundtouch/license.html)
- [Rubber Band licensing](https://breakfastquay.com/rubberband/license.html)
