# Playback speed and pitch preservation

The speed sheet accepts exact rates from **0.50× to 3.00×** (up to two decimal
places), offers **0.05×** adjustment buttons and slider steps, and previews the
remaining listening time. The coordinator still owns playback and persists the
selected rate per book. The sheet follows changes made elsewhere, reports
failed changes, and stops controlling a book when another one becomes active.

## What the installed app uses

This assessment is based on the dependency versions in `pubspec.lock`:
`just_audio 0.10.6+crisper.1` (a small, MIT-licensed local patch to 0.10.6),
`just_audio_media_kit 2.1.0`, and `media_kit 1.2.6`.

| Platform | Current speed processing | Choice available in this app |
| --- | --- | --- |
| Android | Media3/ExoPlayer's Sonic processor on the normal decoded PCM path. The packaged just_audio Android plugin uses Media3 1.4.1, the default renderer/audio sink, and disables audio offload. | Fixed by the current native backend. |
| iOS and macOS, Time Domain | AVFoundation `AVAudioTimePitchAlgorithmTimeDomain`, the upstream voice-oriented default. | Default; selectable. |
| iOS and macOS, Spectral | AVFoundation `AVAudioTimePitchAlgorithmSpectral`, Apple's music-oriented alternative with higher computational cost. | Optional; selectable. |
| Windows and Linux, Automatic | mpv's default pitch-preserving speed path, through media_kit. Current mpv documentation specifies `scaletempo2`; the exact implementation depends on the bundled or installed mpv version. | Default for new launches; selectable. |
| Windows and Linux, Legacy scaletempo | media_kit's independent pitch-control path, with pitch left at 1.0. It installs `scaletempo:scale=...` and turns off mpv's separate automatic pitch-correction filter. | Compatibility alternative; selectable. |

The separate Pages browser player uses browser media playback; this document
describes the native Flutter app.

## Desktop choice

Open **Speed → Speed processing**. Choose **Automatic** or **Legacy scaletempo**.
The preference applies to all books **after restarting CrisperPlayer**. The
sheet identifies the mode used by the current process and a pending selection
separately. It never claims to switch the running decoder when only a preference
has changed.

Automatic is configured before player creation using the public
`JustAudioMediaKit.pitch = false` option. Despite that option's name, it disables
*independent pitch shifting*, **not pitch preservation**. With that option off,
media_kit changes mpv's playback `speed` and leaves mpv's default
`audio-pitch-correction` enabled. With it on, media_kit uses its legacy
`scaletempo` route. CrisperPlayer does not expose independent pitch shifting.

Before this change, the adapter's `pitch = true` default implicitly selected the
legacy route on Windows and Linux. The app now makes this behavior explicit and
offers the normal engine-default path, while retaining the previous path for
recordings where the listener prefers it.

## Apple choice

On iOS and macOS, open **Speed → Speed processing** and choose **Time Domain**
or **Spectral**. Time Domain remains the default. Apple documents it as suitable
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

The complete seven-file upstream diff, original source hashes, license and
update procedure are documented in
[the vendored package provenance](../packages/just_audio/UPSTREAM.md).
The patch uses public AVFoundation APIs and adds no GPL or AGPL library.
The broader app/distribution license review is tracked separately in
[LICENSE_POLICY.md](LICENSE_POLICY.md).

## Other algorithms and tradeoffs

- **Sonic** is already present on Android. It adjusts speed while preserving
  voice pitch. Selecting another processor requires integration in the native
  audio sink; changing a Dart setting cannot replace it.
- **scaletempo2** uses Chromium's waveform similarity overlap-and-add (WSOLA)
  approach. Current mpv selects it automatically for pitch-corrected speed
  changes. The mpv manual describes improved quality relative to older
  scaletempo and Rubber Band's R2 engine; this is an upstream characterization,
  not a CrisperPlayer listening benchmark.
- **Signalsmith Stretch** and its current **Signalsmith Linear** dependency use
  MIT licenses. This is a useful candidate for a future custom native DSP path.
  The author says time stretching sounds best for modest changes around
  0.75×–1.5×, so it should not be assumed to improve 2×–3× audiobook speech.
  Its API exposes input/output latency, seek priming and flush behavior. Those
  need explicit handling to preserve track boundaries and the original
  timestamps used by Return Trail and the listening journal.
- **Bungee** provides a C++ streaming/granular stretcher under MPL 2.0. MPL is
  file-level copyleft, with source/notice obligations, rather than an
  unrestricted permissive license. Its dependencies and exact build need review
  before adoption. The separately marketed proprietary Bungee Pro is not the
  open-source implementation and is not part of this plan.
- **SoundTouch** uses LGPL 2.1 and supplies a native streaming processing API.
  It is another candidate for a measured comparison, not an established upgrade
  over the app's existing Sonic speech processing. LGPL obligations for source,
  replacement/relinking and distribution terms still need to be satisfied;
  "LGPL" alone is not a blanket App Store clearance. Prefer the existing
  AVFoundation processor choices on Apple platforms while this is unresolved.
- **Rubber Band** is available under GPL-2.0-or-later or a separate commercial
  license. Its normal open-source license fails this project's no-GPL/AGPL
  dependency policy, so it is excluded from the open-source processor options.

Signalsmith, Bungee and SoundTouch consume decoded audio samples. They are not
drop-in Dart options for the current just_audio backends. A supported integration
would need a native PCM processing stage, reset/drain/latency handling, correct
source-time mapping, and real device tests. The current adapter does not expose
arbitrary mpv filters. No unavailable processor is shown as a functioning switch.

No algorithm is claimed to sound best for every narrator, recording, speed,
device or listener. A future native processor comparison should use the same
spoken passages, matched output level, several voices/languages and both
speech-only and music-backed material, while measuring CPU/battery use and
seeking/interruption behavior. Interface and configuration tests do not establish
audible superiority.

## Primary references

- [just_audio_media_kit configuration and public pitch option](https://pub.dev/packages/just_audio_media_kit)
- [media_kit source: native setRate/setPitch paths](https://github.com/media-kit/media-kit/blob/main/media_kit/lib/src/player/native/player/real.dart)
- [just_audio source: Apple UriAudioSource](https://github.com/ryanheise/just_audio/blob/minor/just_audio/darwin/just_audio/Sources/just_audio/UriAudioSource.m)
- [Android: DefaultAudioSink.Builder and speed processing](https://developer.android.com/reference/androidx/media3/exoplayer/audio/DefaultAudioSink.Builder)
- [Android: SonicAudioProcessor](https://developer.android.com/reference/androidx/media3/common/audio/SonicAudioProcessor)
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
