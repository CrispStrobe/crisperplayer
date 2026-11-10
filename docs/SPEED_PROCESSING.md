# Playback speed and pitch preservation

The speed sheet accepts exact rates from **0.50× to 3.00×** (up to two decimal
places), offers **0.05×** adjustment buttons and slider steps, and previews the
remaining listening time. The coordinator still owns playback and persists the
selected rate per book. The sheet follows changes made elsewhere, reports
failed changes, and stops controlling a book when another one becomes active.

## What the installed app uses

This assessment is based on the dependency versions in `pubspec.lock`:
`just_audio 0.10.6`, `just_audio_media_kit 2.1.0`, and `media_kit 1.2.6`.

| Platform | Current speed processing | Choice available in this app |
| --- | --- | --- |
| Android | Media3/ExoPlayer's Sonic processor on the normal decoded PCM path. The packaged just_audio Android plugin uses Media3 1.4.1, the default renderer/audio sink, and disables audio offload. | Fixed by the current native backend. |
| iOS and macOS | AVFoundation `AVAudioTimePitchAlgorithmTimeDomain`, explicitly selected by just_audio for each audio source. | Fixed by the current native backend. |
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

## Other algorithms and tradeoffs

- **Sonic** is already present on Android. It adjusts speed while preserving
  voice pitch. Selecting another processor requires integration in the native
  audio sink; changing a Dart setting cannot replace it.
- **scaletempo2** uses Chromium's waveform similarity overlap-and-add (WSOLA)
  approach. Current mpv selects it automatically for pitch-corrected speed
  changes. The mpv manual describes improved quality relative to older
  scaletempo and Rubber Band's R2 engine; this is an upstream characterization,
  not a CrisperPlayer listening benchmark.
- **Rubber Band** is an alternative when an mpv build includes it. Its R3/Finer
  engine uses more CPU than R2/Faster and targets higher-quality output. The
  current just_audio adapter does not expose arbitrary mpv audio filters, and
  CrisperPlayer does not guarantee that the library is present in all platform
  builds. It is therefore not advertised as an available switch. Its vendor
  offers GPL-2.0-or-later and commercial licensing; distribution terms would
  need to be resolved before adding it to further app packages.
- **Apple Spectral** is documented as suitable for music; **Time Domain** is
  intended for voice. Spectral could be evaluated in a maintained native
  backend extension. It is not exposed by the pinned just_audio API, so no
  inactive or misleading switch is shown.

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
