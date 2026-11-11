# Audio codec patents and native decoder direction

Reviewed 11 November 2026. This records the engineering decision and the
limits of the available evidence. It is not a patent clearance opinion.
Source licenses, codec patents, and the exact distributed binary are separate
questions. Passing the source/license audit does not answer all three.

## Current status

The branch currently compiles Glint's **AAC-LC** decoder into Windows/Linux
`crisper_audio`. It does not include HE-AAC or xHE-AAC. The AAC tables now have
a reproducible Apache-2.0 source chain and retained notices; that resolved a
source copyright/provenance issue, **not codec patent coverage**.

No patent clearance has been established for this bundled AAC implementation.
The `desktop-glint-decoders` native inventory records that unresolved issue as
a distribution blocker. Development builds and functional tests are not a
release approval. Merely hiding AAC in the UI or preferring another decoder
does not remove the bundled implementation from a binary.

Android and Apple continue using their platform media adapters. The Windows
Media Foundation route below is a planned replacement, **not implemented by
this documentation change**. No new decoder library has been added here.

## Source-license selection is necessary but insufficient

New decoder source closures remain limited to the permissive grants in
[the dependency policy](LICENSE_POLICY.md). Include copied tables and native
transitive dependencies, and preserve their original notices.

- [Apache-2.0 section 3](https://www.apache.org/licenses/LICENSE-2.0) grants
  contributor-controlled patent claims necessarily infringed by the relevant
  contribution/combination. It cannot grant unrelated third parties' patents.
- MIT/BSD/Unlicense text does not contain an equivalent express patent grant;
  separate grants or other legal rights must not be assumed absent or present
  solely from that label.
- [CC0 section 4(a)](https://creativecommons.org/publicdomain/zero/1.0/legalcode.en)
  expressly leaves patent rights unaffected. Public-domain copyright treatment
  is not a patent license.

The existing Sonic, Chromium WSOLA, Signalsmith and Bungee source reviews are
not independent patent searches. Sonic's Apache grant and Bungee's
[MPL-2.0 contributor grant](https://www.mozilla.org/en-US/MPL/2.0/) have defined
scope. No separate royalty requirement was identified in the reviewed project
materials, but that is not a non-infringement warranty. Existing Bungee/Eigen
MPL code remains within the previously selected DSP scope; MPL is not eligible
for new decoder additions under the owner's stricter rule.

## AAC: do not use age as a clearance test

[Via LA's current AAC program](https://www.via-la.com/licensing-programs/aac/)
expressly includes AAC-LC, HE-AAC v1/v2, xHE-AAC and MPEG-D DRC. Its published
position distinguishes licensing decoder/encoder products from distributing
AAC-encoded content. That does not establish which unexpired claims apply to
this implementation in each jurisdiction, nor whether an existing platform
license covers this app.

Consequently, AAC-LC's age is not sufficient evidence for calling it cleared.
Adding newer AAC tools expands the implementation being assessed; restricting
to LC does not itself establish an exemption. The Apache license on
[Ittiam/AOSP libxaac](https://github.com/ittiam-systems/libxaac) does not resolve
third-party AAC claims. Keep libxaac out of the default additions until the
distribution position is established.

[Fraunhofer's implementation guidance](https://www.iis.fraunhofer.de/en/ff/amm/impl.html)
directs developers to determine whether their application is already covered
by an existing license. Using a shipped OS decoder reduces the implementation
we distribute, but no public source reviewed here establishes universal app
indemnity. Via's Android-OEM warning concerns device manufacturers; it is not
evidence that every app using MediaCodec separately owes a fee.

## Preferred platform routes

All decoder routes produce PCM for the shared speed processors. Choosing an
OS decoder does not require giving up Dart transport or replacing the four
DSP choices with an OS playback-speed implementation.

| Platform | Engineering direction | Evidence and qualification |
| --- | --- | --- |
| Android | Keep Media3/platform MediaCodec decoding and the existing PCM processors. | [Android's format matrix](https://developer.android.com/media/platform/supported-formats) documents LC/HE and xHE decoding from Android 9. Check the actual device/format capability. Do not copy AOSP codec code into the app merely because it is available. |
| iOS/macOS | Keep AVFoundation/AudioToolbox decoding and the Apple/native processor adapters. | [Apple's WWDC20 explanation](https://developer.apple.com/videos/play/wwdc2020/10158/) dates xHE file playback to iOS 13/macOS Catalina. Availability, channel support and container handling remain platform-specific. |
| Windows | Replace bundled AAC decoding with Microsoft's Media Foundation decoder behind the bounded decoder interface. | Microsoft's [AAC transform](https://learn.microsoft.com/en-us/windows/win32/medfound/aac-decoder) provides LC/HE and float PCM. [Fraunhofer confirms](https://www.audioblog.iis.fraunhofer.com/xhe-aac-windows11) Microsoft licensed its xHE implementation for the Windows 11 2022 update. Query capabilities, including [Windows N / Media Feature Pack](https://support.microsoft.com/en-us/windows/experience/platform-variants/media-feature-pack-for-windows-n). Broader AAC support needs its own timing/parser tests. |
| Linux | Keep permissive bundled decoders for the other supported formats; resolve AAC distribution explicitly. | No universal equivalent OS AAC service has been established for the supported Linux targets. A system FFmpeg/GStreamer installation, dynamically loaded plugin or user-installed codec is not by itself evidence of patent coverage or compliance with the new-decoder source policy. |

For Linux, the release choices are to establish coverage/clearance for the
actual bundled AAC implementation, select a suitably licensed implementation
and distribution arrangement, or exclude the AAC implementation from that
release and report the unsupported codec clearly. No such removal or legal
selection has been silently made by this documentation change. A fallback
must not silently reintroduce bundled AAC when the selected OS codec is absent.

### Windows implementation boundary

Start with the existing AAC-LC mono/stereo scope, using the Microsoft AAC
`IMFTransform` and the current bounded Dart packet/demux/trim accounting.
Keep COM/Media Foundation lifetime on an owned native thread; a Dart worker
isolate is not a promise of OS-thread affinity. Preserve exact source frames,
preroll, cancellation, finite drain and the current decoder interface.

A general Source Reader adapter is also possible, but its
[seek API does not promise exact positions](https://learn.microsoft.com/en-us/windows/win32/api/mfreadwrite/nf-mfreadwrite-imfsourcereader-setcurrentposition).
Presentation-duration metadata alone is not an exact PCM-frame ledger. Tests
must establish trim/delay behavior, repeated seeks, missing-codec errors,
corrupt input, teardown and all four DSP engines against a packaged Windows
artifact. HE-AAC and xHE-AAC need capability-specific integration; the LC MFT
documentation must not be treated as proof that that same transform accepts
every later profile.

## Permissive additions with better documented format positions

These are engineering candidates, not a guarantee that no third-party claim
could ever arise. The selected implementation still needs its source and
artifact review.

| Format | Primary-source position | Decision for this app |
| --- | --- | --- |
| FLAC | [Xiph](https://xiph.org/flac/license.html) states no format royalties and no known patents covering the formats or implemented methods. Reference libraries are BSD; some accompanying tools are GPL. | Retain current FLAC and consider a permissive library for wider coverage. |
| Vorbis | [Xiph](https://www.xiph.org/vorbis/faq/) describes a patent/royalty-free format and BSD reference libraries. | Strong addition through libvorbisfile/libvorbis/libogg. |
| Opus | [The project](https://opus-codec.org/license/) provides BSD code and explicit royalty-free patent grants with defensive conditions. It is patented, not unpatented. | Strong addition for this independently distributed app; retain the actual patent grants alongside source notices. |
| MP3 | [Fraunhofer](https://www.audioblog.iis.fraunhofer.com/mp3-software-patents-licenses) says the last core patent in its Technicolor program expired on 23 April 2017, while distinguishing possible implementation/enhancement claims. | Retain the permissive implementation; describe that portfolio's expiration accurately. |
| ALAC | [Apple's reference implementation](https://macosforge.github.io/alac/) is Apache-2.0, with its contributor patent grant. | Viable additional decoder; this is not proof of universal third-party clearance. |

Opus has an additional nuance: [Vectis's current pool policy](https://www.opuspool.com/home)
targets end-user hardware and says its program is not directed at open-source
software/apps/content distributed independently of hardware. That is a
published program policy, not an irrevocable third-party patent license or
proof of the pool's essentiality claims. Record the standalone-app scope and
reassess if the product is later bundled with hardware.

## Release evidence to retain

For any codec with unresolved asserted patent coverage, record a concrete
decision for the actual decoder/profile, distributed implementation, product
model, target countries and OS versions. A qualified patent adviser can assess
claim scope/expiry and applicable platform or supplier grants; a pool can
confirm the scope of its own agreement. Do not equate an interested party's
marketing page with a legal determination of infringement.

Keep source-license status, patent-review status and packaged-artifact status
separate in the inventory. A source grant becoming reviewed must not silently
promote either of the other statuses. Routine feature-branch testing may
continue while the existing enforced distribution review remains incomplete.
