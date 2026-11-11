# Playback speed and pitch preservation

The speed sheet accepts exact rates from **0.50× to 3.00×** (up to two decimal
places), offers **0.05×** adjustment buttons and slider steps, and previews the
remaining listening time. The coordinator still owns playback and persists the
selected rate per book. The sheet follows changes made elsewhere, reports
failed changes, and stops controlling a book when another one becomes active.

## What the installed app uses

The installed app uses the maintained `just_audio 0.10.6+crisper.4` native
Android/Apple adapters and the local `crisper_audio` Dart FFI package on desktop.

| Platform | Default | Optional processors |
| --- | --- | --- |
| Android | Media3 Sonic | Chromium WSOLA, Signalsmith Stretch, Bungee Basic through the existing JNI processor chain. |
| iOS/macOS | Apple Time Domain | Apple Spectral, or all four portable processors for supported local/downloaded mono/stereo files. |
| Windows/Linux | Sonic C through direct Dart/native playback | Chromium WSOLA, Signalsmith Stretch and Bungee Basic from the same shared core. |

The separate Pages browser player uses browser media playback; this document
describes the native Flutter app.

## Android choice

Open **Speed → Speed processing** and choose **Sonic**, **Bungee Basic**,
**Signalsmith Stretch**, or **WSOLA**. Sonic remains the default. The preference applies to
all books after restarting CrisperPlayer; the panel distinguishes the processor
active now from a saved choice that is pending restart.

The three native alternatives support mono/stereo PCM at 8–192 kHz and the app's
full 0.50×–3.00× rate range. Support for a rate does not establish that it sounds
better at that rate. Signalsmith's upstream recommendation is approximately
0.75×–1.5×; Sonic remains the speech baseline, particularly at high rates.
At 1.00× the native adapters pass PCM through unchanged.

**Skip silence is available with Sonic.** The first version of the native
alternatives does not combine silence removal with time stretching. Global and
per-book preferences are retained, but the controls show that the feature is
unavailable for the current processor. Choosing a pending mode does not change
the capability of the running player.

The native modes replace Media3's speed-processing chain; they do not append a
second stretcher after Sonic. They force decoding to PCM and disable encoded
passthrough, offload and AudioTrack speed adjustment so processing cannot be
bypassed or applied twice. Media3 drains the old processing segment before a
rate transition. Seek/reset discards buffered audio, end-of-stream drains the
tail, and the clock maps delivered output back to original source time. These
properties matter to resume, played ranges, Return Trail and the journal.

The unchanged Sonic path does not load the JNI library. Initialization errors
in an explicitly selected native processor are reported rather than silently
claiming that a different engine is running. Native source pins, original
licenses, offline build/test tools and the WAV comparison renderer are in
[the native processor package](../packages/just_audio/native/crisper_dsp/README.md).
These options are experimental pending target-device listening and battery
measurements. See [Android validation](ANDROID_AUDIO_PROCESSORS.md).

## Desktop choice

Open **Speed → Speed processing** and choose **Sonic**, **WSOLA**,
**Signalsmith Stretch** or **Bungee Basic**. Sonic is the speech default.
The preference applies to all books **after restarting CrisperPlayer**. The
sheet identifies the active processor separately from a pending selection.
Older Automatic, Legacy scaletempo and atempo settings migrate to Sonic.

Dart owns a streaming decoder/DSP/output worker. All four engines link into
one native library; selecting one does not depend on a system mpv filter
inventory. The pipeline preserves source timing through partial writes,
seek/reset and finite end-of-file drain. Decoder lookahead and underrun zeros
do not move the source clock. The output clock includes an estimated backend
buffer delay and is not an exact hardware/DAC timestamp.

Duration probing and waveform extraction use the same bounded decoder.
The current format/profile boundaries, source pins and testing limits are
in [PORTABLE_AUDIO_PROCESSORS.md](PORTABLE_AUDIO_PROCESSORS.md) and
[DESKTOP_AUDIO_BUILD.md](DESKTOP_AUDIO_BUILD.md). No mpv or FFmpeg runtime is
needed for this native path. There is no independent pitch-shift control.

## Apple choice

On iOS and macOS, open **Speed → Speed processing** and choose **Time Domain**
or **Spectral**, or opt into **Sonic**, **WSOLA**, **Signalsmith Stretch** or
**Bungee Basic** for local/downloaded books. Time Domain remains the default. Apple documents it as suitable
for voice and less computationally intensive than Spectral. Spectral is intended
for music and is useful to compare on music-backed or mixed recordings; no
CrisperPlayer listening benchmark establishes that it is better for every voice.

The choice applies to all books **after restarting CrisperPlayer**. The UI shows
the currently applied processor and the saved selection separately. Startup
constructs an immutable `DarwinLoadControl.audioTimePitchAlgorithm` configuration
for the shared player. The patched native source sets the public
`AVPlayerItem.audioTimePitchAlgorithm` on each source and loop copy; it does not
swap the active audio processor during playback. The choice is also transported
again if just_audio recreates its native player.

The four portable choices select a separate local PCM path using AVAudioFile
for decoding and AVAudioPlayerNode for output. Audio is streamed through bounded
buffers; a whole audiobook is never decoded into memory. The player maps actual
played frames to source time, holds the clock through output gaps and pauses,
reopens at source position on seeks/rate changes, and drains before completing
or advancing a file. It supports file queues, clipping, loops and shuffle order.
Portable Apple positions use native snapshots at roughly 200 ms intervals, so
an undetected output gap cannot be counted by wall-clock interpolation. The
existing Apple and other platform players retain their usual smooth clocks.
The Apple network/AVPlayer path remains available by choosing Time Domain or
Spectral. Unsupported URLs, channel layouts or sample rates fail with an
explanation instead of silently changing the selected engine.

CocoaPods and SwiftPM compile the same pinned native source closure used on
Android. The functional range remains 0.50×–3.00×, 8–192 kHz mono/stereo; Apple
format support is limited to the formats AVAudioFile can decode. Portable
choices are experimental pending target-device listening and performance checks.

The complete upstream diff, original source hashes, licenses and
update procedure are documented in
[the vendored package provenance](../packages/just_audio/UPSTREAM.md).
The patch uses public AVFoundation APIs and adds no GPL or AGPL library.
The broader app/distribution license review is tracked separately in
[LICENSE_POLICY.md](LICENSE_POLICY.md).

## Other algorithms and tradeoffs

- **Sonic** remains the Android default. The native C implementation is also
  included as an optional Apple/desktop engine and the host comparison baseline;
  Android's default continues to use Media3's implementation. The C core is not
  claimed to be bit-identical to Media3.
- **WSOLA** now has its own portable C++ implementation maintained in this
  repository, derived from Chromium's BSD-3-Clause matching, windowing and
  overlap-add code. It uses shared stereo alignment, bounded streaming buffers,
  exact unity-rate passthrough and source-time accounting. The retained original
  source and [documented modifications](../packages/just_audio/native/crisper_dsp/wsola/UPSTREAM.md)
  make future updates reviewable. Chromium's browser/runtime and mpv are not
  dependencies of this Android processor. This fork is an additional listening
  choice; signal tests do not establish that it sounds better than Sonic.
- **Signalsmith Stretch** and its current **Signalsmith Linear** dependency use
  MIT licenses. The shared native implementation has Android, Apple-local and direct Dart/native desktop PCM integrations.
  The author says time stretching sounds best for modest changes around
  0.75×–1.5×, so it should not be assumed to improve 2×–3× audiobook speech.
  Its adapter handles input/output latency, seek priming and flush behavior to
  preserve track boundaries and original source timestamps.
- **Bungee** provides a C++ streaming/granular stretcher under MPL 2.0. MPL is
  file-level copyleft, with source/notice obligations, rather than an
  unrestricted permissive license. The vendored Basic build includes only the
  selected Eigen/PFFFT source closure, original notices and file hashes. It uses
  `EIGEN_MPL2_ONLY`; no unsupported Eigen modules or proprietary Bungee Pro code
  are included.
- **SoundTouch** uses LGPL 2.1 and supplies a native streaming processing API.
  It is another candidate for a measured comparison, not an established upgrade
  over the app's existing Sonic speech processing. LGPL obligations for source,
  replacement/relinking and distribution terms still need to be satisfied;
  "LGPL" alone is not a blanket App Store clearance. Prefer the existing
  AVFoundation processor choices on Apple platforms while this is unresolved.
- **Rubber Band** is available under GPL-2.0-or-later or a separate commercial
  license. Its normal open-source license fails this project's no-GPL/AGPL
  dependency policy, so it is excluded from the open-source processor options.

The four shared engines now have platform adapters for Android, Apple local
files and direct Dart/native Windows/Linux playback. Apple Time Domain remains
the Apple default; desktop uses Sonic C. SoundTouch adds LGPL obligations without
increasing platform reach and is not integrated. Rubber Band's GPL route is
excluded. Browser playback is unchanged, and this work adds no independent pitch
slider. Further engines should demonstrate a useful quality/performance tradeoff
before adding another maintenance and provenance burden.

No algorithm is claimed to sound best for every narrator, recording, speed,
device or listener. A processor listening comparison should use the same
spoken passages, matched output level, several voices/languages and both
speech-only and music-backed material, while measuring CPU/battery use and
seeking/interruption behavior. Interface and configuration tests do not establish
audible superiority.

## Primary references

- [just_audio source: Apple UriAudioSource](https://github.com/ryanheise/just_audio/blob/minor/just_audio/darwin/just_audio/Sources/just_audio/UriAudioSource.m)
- [Android: DefaultAudioSink.Builder and speed processing](https://developer.android.com/reference/androidx/media3/exoplayer/audio/DefaultAudioSink.Builder)
- [Android: SonicAudioProcessor](https://developer.android.com/reference/androidx/media3/common/audio/SonicAudioProcessor)
- [Chromium: pinned WSOLA helpers](https://chromium.googlesource.com/chromium/src.git/+/ddd30ef8aa98443509bf4ce006cb36b4e2296c0b/media/filters/wsola_internals.cc)
- [Chromium: pinned BSD license](https://chromium.googlesource.com/chromium/src.git/+/ddd30ef8aa98443509bf4ce006cb36b4e2296c0b/LICENSE)
- [mpv manual: audio-pitch-correction and audio filters](https://mpv.io/manual/stable/)
- [Apple: Time Domain](https://developer.apple.com/documentation/avfoundation/avaudiotimepitchalgorithm/timedomain)
- [Apple: Spectral](https://developer.apple.com/documentation/avfoundation/avaudiotimepitchalgorithm/spectral)
- [Signalsmith Stretch: implementation, latency and license](https://github.com/Signalsmith-Audio/signalsmith-stretch)
- [Signalsmith Linear: MIT license](https://github.com/Signalsmith-Audio/linear/blob/main/LICENSE.txt)
- [Bungee: streaming API and MPL license](https://github.com/bungee-audio-stretch/bungee)
- [Mozilla: MPL 2.0 FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/)
- [SoundTouch: LGPL 2.1 license](https://surina.net/soundtouch/license.html)
- [Rubber Band licensing](https://breakfastquay.com/rubberband/license.html)

References reviewed 10 November 2026. Local package sources were inspected in
addition to documentation; online defaults may change with future dependency
updates.

## Screenshots and validation

Actual Flutter renders at 390 × 844 with fictional book metadata:

| Precise rates and time estimate | Supported desktop processing choice |
| --- | --- |
| ![Speed controls](images/speed-controls-preview.png) | ![Speed processing](images/speed-processing-preview.png) |

See [journal and speed validation](JOURNAL_SPEED_VALIDATION.md).

Apple processing selection, rendered from the real Flutter widget with fictional
book metadata. Time Domain remains active while Spectral is saved for restart:

![Apple processing choice](images/apple-speed-processing-preview.png)
