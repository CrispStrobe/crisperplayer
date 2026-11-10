# External dependency license policy and audio processors

Reviewed 10 November 2026. The project requirement is an openly distributable
application that can also be submitted to app stores, without GPL-only or
AGPL-only **external** dependencies. MIT, Apache-2.0, BSD and comparable
permissive licenses are preferred. MPL and LGPL are permitted when their
actual distribution obligations are met.

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
| Windows native audio | `media_kit_libs_windows_audio 1.0.9` selects the audio-only `2023-09-24` libmpv/FFmpeg archive. Its build recipes select LGPL configurations. | Verify the exact binary, dependencies, corresponding source and distribution materials. The MIT Flutter wrapper does not license its native payload. |
| Linux native audio | `media_kit_libs_linux 1.2.1` loads system libmpv; the app does not control the distribution's build options. | An arbitrary system installation cannot support a promise of no GPL components. Use a controlled LGPL build with recorded provenance for the supported release. |

Filen and Internxt are MPL-2.0 components. Their source availability and notice
requirements continue to apply. `libsmb2` is a separate LGPL native component,
so choosing a permissive audio processor does not by itself finish the app's
license audit.

## mpv can be LGPL

mpv is GPL-2.0-or-later by default, but its libmpv build can be distributed under
LGPL-2.1-or-later when GPL-only files are excluded. The upstream option is
`-Dgpl=false`. mpv explicitly cautions that this flag alone is not a license
grant: linked dependencies, including FFmpeg, still determine the resulting
license. mpv's GPL documentation and example files are also separate from an
LGPL binary and should not be copied into a no-GPL distribution indiscriminately.

For a controlled desktop build, record source revisions and hashes, exclude
GPL and nonredistributable FFmpeg features, keep native libraries replaceable,
publish the corresponding source and build instructions, and include all
required notices. Do not add Rubber Band, x264 or another GPL-only dependency
to an LGPL build and continue describing the result as LGPL.

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
| Sonic | Apache-2.0 native library and implementation in AndroidX Media3. | First choice for audiobook speech, including high rates; keep the existing Android default and use it as the comparison baseline. |
| mpv scaletempo2 / scaletempo | Available in an appropriately built LGPL libmpv. | Retain the existing choices subject to native artifact verification; processor choice does not waive packaging obligations. |
| Bungee Basic | MPL-2.0; the selected Eigen Core and PFFFT source and original notices are pinned. | Experimental Android option for comparison on speech mixed with music or ambience. `EIGEN_MPL2_ONLY` excludes GPL modules; proprietary Bungee Pro is not included. |
| Signalsmith Stretch | MIT, with the selected MIT Signalsmith Linear implementation. | Experimental Android option for moderate rate changes. Upstream describes best time-stretch quality around 0.75×–1.5×; do not assume a 2×–3× speech improvement. |
| SoundTouch | LGPL-2.1. | A possible alternative with the same source/relinking review needed for LGPL components. It is not assumed better for every voice. |
| Rubber Band | GPL-2.0-or-later or a separately purchased commercial license. | Excluded from the openly reproducible default dependency set under this policy. A commercial license for one publisher does not give all open-source recipients the same commercial redistribution rights. |

The word “quality” describes an available processing choice, not a measured
claim that one algorithm beats every other algorithm. Compare the same speech
and speech-with-music passages at matched level and several speeds, and measure
CPU/battery use, seek latency and interruption behavior on target devices.

The [Android processor record](ANDROID_AUDIO_PROCESSORS.md) documents the exact
source revisions, native integration and validation limits. The entire selected
external source closure is included with per-file hashes; app notices link to an
immutable public source snapshot. The independent adapter is MIT licensed.

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
