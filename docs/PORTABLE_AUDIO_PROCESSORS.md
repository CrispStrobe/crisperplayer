# Portable native speed processors

CrisperPlayer uses four portable engines through the same bounded PCM core:
**Sonic C, Chromium WSOLA, Signalsmith Stretch and Bungee Basic**. The desktop
implementation is controlled directly from Dart. It does not register a
just_audio desktop backend, load mpv, or invoke FFmpeg for duration or waveform
work. Apple and Android retain their existing native playback paths.

## Platform coverage

| Platform | Default | Other choices | Decoder and output |
| --- | --- | --- | --- |
| Android | Media3 Sonic | Chromium WSOLA, Signalsmith Stretch, Bungee Basic | Existing Media3/JNI integration and AudioTrack. |
| iOS/macOS | Apple Time Domain | Apple Spectral and all four portable engines | Apple defaults use AVQueuePlayer; portable modes use local AVAudioFile → shared DSP → AVAudioEngine. |
| Windows | Sonic C | Chromium WSOLA, Signalsmith Stretch, Bungee Basic | Dart file/container reader, Glint frame decoding, shared DSP and a native miniaudio output callback. |
| Linux | Sonic C | Chromium WSOLA, Signalsmith Stretch, Bungee Basic | The same Dart/native pipeline, with the host's native audio output backend. |
| Browser | Browser-controlled playback in the separate Pages player | No new portable engine | The installed Flutter app still displays its unsupported-browser screen. |

Every processor selection is immutable for a player session. The UI shows the
active engine and a saved choice that takes effect after restart. Desktop
Automatic, Legacy scaletempo and atempo preferences migrate to Sonic. Existing
Sonic/WSOLA/Signalsmith/Bungee preferences retain their meaning. There is no
silent engine substitution if the selected processor fails.

The core supports mono/stereo 8–192 kHz PCM and **0.50×–3.00×** speed, with pitch
preserved. It passes through samples at 1×. These are functional bounds, not a
claim of equal perceived quality throughout that range. Signalsmith's upstream
comparison range is approximately 0.75×–1.5×. CrisperPlayer still has no
independent pitch-shift control. Skip silence remains an Android Sonic feature.

## Direct Dart/native desktop path

`packages/crisper_audio` owns one worker isolate per player. It opens the file,
reads bounded compressed packets, calls Glint's stateful decoder and the
selected DSP through FFI, then fills a bounded native float PCM queue. The
output callback only consumes prepared PCM; it never calls Dart or runs a
decoder. Partial writes preserve their unaccepted remainder.

The UI isolate sends transport commands. Seek, stop, replacement load and rate
changes invalidate earlier commands using a generation token; long header
scans check that token and close their resources when cancelled. Disposal waits
for worker cleanup. Real decoder/device failures remain visible and stop the
affected session. Duration probing and desktop waveform extraction use the same
bounded decoder on separate worker isolates.

The desktop source clock maps presented output-frame spans back to original
book frames. Decode lookahead, queued DSP output and underrun silence do not
advance it. The native sink includes a backend-buffer delay estimate and ages
PCM credits through later silence, allowing the final partial buffer to finish.
This is **not a hardware/DAC timestamp or a bound on acoustic latency**. Bluetooth,
audio servers and hardware can add unreported delay. Physical-device checks
remain necessary. Pause preserves queued PCM; a submitted backend tail can
finish. Seek/rate replacement starts a new decoder/DSP/output epoch, dropping
stale queues rather than mixing speed mappings.

### Decoder scope

The initial streaming codec path supports PCM/float WAV, MPEG-1/2/2.5 Layer III
MP3, AAC-LC ADTS and unencrypted AAC-LC in M4A/M4B/MP4. MP3 seeks restore the
reservoir/synthesis state with preroll; MP4 uses on-disk paged sample tables,
64-bit chunk offsets, and supported priming/presentation trims. AAC seek noise
state is per decoder and tied to the absolute packet ordinal.

This is not general MP4 or all-profile AAC support. HE-AAC/SBR/PS, ALAC,
encryption, fragmented MP4, multichannel audio and complex edit lists are
rejected explicitly. Unsupported formats are not passed to an invisible mpv
fallback. Consult the package README for the current additional codec scope.
Apple/Android format support remains governed by their own decoders.

## Reuse of the other CrispStrobe projects

The implementation follows source inspected at these immutable revisions:

- [Glint `7b458cff`](https://github.com/CrispStrobe/glint/tree/7b458cff0fc9c397f671c422db4770c72fc22f5c):
  reuse the owned C++ codec internals through a bounded frame ABI. Its existing
  Dart convenience API decodes whole files, so it is not the audiobook transport.
- [CometBeat `a9e4d0e`](https://github.com/CrispStrobe/cometbeat/tree/a9e4d0e553b94369ad883596c9e686e8581c62a2/native/aec):
  reuse the independently MIT-licensed native package's explicit library loading,
  FFI packaging and miniaudio/SPSC design. This host adds playback backpressure,
  frame accounting and stereo float output; it does not use SoLoud or the
  practice player's whole-file PCM/stopwatch model.
- [CrispAudio `6a4cf2ec`](https://github.com/CrispStrobe/crispaudio/tree/6a4cf2ecf34d680a5062f4edd7d89a6f6251defd):
  adopt session generations, ordered teardown, bounded output, persistent
  errors and the separation between queued and played audio. Its macOS
  AudioQueue path and predecoded editor snapshots are not copied as a desktop
  audiobook backend.

## Licenses and original source

The existing seven-component DSP closure and 258 retained originals are pinned
in [the shared manifest](../packages/just_audio/native/crisper_dsp/vendor/manifest.json):

| Component | Retained grant |
| --- | --- |
| Sonic C | Apache-2.0 |
| Chromium-derived WSOLA | BSD-3-Clause |
| Signalsmith Stretch and Linear | MIT |
| Bungee Basic | MPL-2.0 |
| Selected Eigen Core | MPL-2.0 with original BSD/Apache notices |
| PFFFT/FFTPACK | Original permissive NCAR/UCAR grant |

The independent host and Dart code are MIT. miniaudio's exact 0.11.25 header,
MIT-0/public-domain notices and source hash are retained. Glint's selected source
and local patches have original/current file hashes and a reversible patch.
Glint declares MIT, but the AAC-table extraction provenance noted by CrispAudio
is still unresolved; that fact remains in the source manifest and distribution
gate. No top-level wrapper license is used to approve a native payload.

The new desktop audio dependency graph removes media_kit/libmpv and FFmpeg. This
does not remove LGPL components from the rest of the application or the host OS.
MPL source availability, original notices and the existing distribution policy
still apply. Historical mpv prototype commits and evidence remain in Git; they
are not the current build path.

## Verification

See [desktop build and checks](DESKTOP_AUDIO_BUILD.md),
[the native package contract](../packages/crisper_audio/README.md), and
[Apple/Android processor details](SPEED_PROCESSING.md). Host native/manual-output
tests exercise actual compiled algorithms and decoder PCM. They do not establish
speaker output, interruption behavior, latency, battery use or listening quality
on a physical device. Platform workflows must run and retain their results before
target build claims are made. Distribution approval remains a separate gate.
