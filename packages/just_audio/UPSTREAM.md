# just_audio: native speed-processing extensions

## Provenance and license

- Upstream package: **just_audio 0.10.6**, published by Ryan Heise.
- Source archive: <https://pub.dev/api/archives/just_audio-0.10.6.tar.gz>
- Published archive SHA-256, recorded in the original app lockfile and pub cache:
  `e60aa97b233ddea025e13dfac59195207f528fa5e9e4a4a49a8c0766701e5fe6`
- Upstream repository: <https://github.com/ryanheise/just_audio/tree/minor/just_audio>
- The upstream [MIT license](LICENSE) is retained unchanged. Our Dart, Java,
  Objective-C, JNI and independent C++ adapter changes use MIT. The derived
  portable Chromium WSOLA implementation and derived semantic fixtures retain
  BSD-3-Clause. The separately pinned DSP dependencies retain their own
  permissive or MPL licenses; see
  [the native component manifest](native/crisper_dsp/vendor/manifest.json).
- Local package version: **0.10.6+crisper.4**, `publish_to: none`.

The 38 original source, platform build, documentation and notice files are
listed with their original SHA-256 values in [UPSTREAM_SHA256.json](UPSTREAM_SHA256.json).
All Dart, Android and shared Darwin runtime/build files are retained. Examples,
sample media and upstream test fixtures are omitted; no generated artifacts or
native binaries are vendored.

## Complete patch surface

[UPSTREAM.patch](UPSTREAM.patch) records the complete diff from those original
files plus the local adapter files listed in [LOCAL_ADDITIONS.json](LOCAL_ADDITIONS.json).
Third-party native source bytes are independently pinned, per file, in the
native component manifest rather than duplicated in the patch.

### Apple configuration

1. `lib/just_audio.dart` adds the public `DarwinTimePitchAlgorithm` enum and
   `DarwinLoadControl.audioTimePitchAlgorithm`, defaulting to `timeDomain`.
   A small subclass extends the public `DarwinLoadControlMessage.toMap()` API
   with one Darwin configuration key. This avoids a second fork of
   `just_audio_platform_interface`; other backends retain their existing paths.
2. Native `LoadControl.h` / `LoadControl.m` carry the immutable selection.
3. Native `AudioPlayer.m` reads the selection at player initialization. Only
   the exact string `spectral` enables it; missing or unknown values preserve
   the Time Domain default.
4. Native `UriAudioSource.m` assigns the public AVFoundation
   `AVPlayerItem.audioTimePitchAlgorithm` property. The same factory creates
   initial, playlist and loop-copy player items, so all use the configured mode.

No reflection, method swizzling, private Apple APIs, extra player registry or
global preferences are used. The public option is immutable for a player and
is included again if just_audio recreates that player's native instance.
CrisperPlayer presents it as a restart-required preference so active playback
is never reconfigured mid-passage.

### Optional Apple PCM playback

`DarwinSpeedProcessor` and nullable `DarwinLoadControl.speedProcessor` transport
`portableSpeedProcessor` without changing the default AVPlayer configuration.
The plugin creates `CrisperPortableAudioPlayer` only for an explicit portable
selection. `CrisperDspStream` decodes local files with `AVAudioFile`, streams
bounded mono/stereo float PCM through the existing four-engine C ABI, and drains
the exact finite output. `AVAudioPlayerNode` schedules a bounded output queue;
the clock maps played frames to original source time and excludes queued audio,
processor lookahead, hardware latency and output-starvation gaps.
The Dart position getter uses these native snapshots for portable Apple players,
so it cannot extrapolate a stale ready event across an undetected output gap.
AVPlayer and other platforms retain their existing interpolated position clock.
Seeking and speed changes replace buffered audio at the current source position. File queues,
clipping, loop/shuffle order and local playlist operations retain the native
method-channel contract. Network/unsupported inputs report an explicit error.

CocoaPods compiles wrapper translation units including the same pinned native
source files. SwiftPM uses the local `native/crisper_dsp` package and excludes
those wrappers to avoid duplicate symbols. Apple Time Domain and Spectral retain
the upstream `AVQueuePlayer`; neither instantiates the portable playback path.

### Direct native desktop reuse

`../crisper_audio` links `native/crisper_dsp` directly through its C ABI. Dart
owns desktop transport and Glint decoding; its native host owns PCM output.
The former `native/mpv` adapter is removed. No desktop platform implementation
is registered through just_audio, and Apple/Android keep their own adapters.

### Android streaming processors

`AndroidSpeedProcessor` and `AndroidLoadControl.speedProcessor` add an immutable
startup selection: `sonic` (default), `bungee`, `signalsmith` or `wsola`. A public message
subclass carries the value without forking `just_audio_platform_interface`.
Missing selections preserve upstream Sonic; an unknown non-null native value
fails explicitly. `AudioPlayer.java` retains the upstream renderer factory for
Sonic, including its existing silence skipping. That path never loads our JNI
library. A selected alternative uses the new renderer factory and one custom
Media3 1.4.1 `AudioProcessorChain` stage, with no second Sonic stage.

The custom sink forces decoded PCM16, disables encoded passthrough, float-output
bypass, AudioTrack speed processing and offload. Its source clock maps delivered
output frames to represented source frames, excluding pending input/lookahead.
Media3 drains old audio before a rate checkpoint; the processor applies a pending
rate on flush, owns partial writes and returned buffers, drains a finite tail,
and replaces the native handle on seek/reset. The adapter accepts mono/stereo,
8–192 kHz and 0.5–3.0×. Independent pitch changes and silence skipping are rejected
for these alternatives; neutral pitch and disabled silence skipping remain valid.

The new Java files are `CrisperAudioProcessor`, `CrisperAudioProcessorChain`,
`CrisperDspEngine`, `JniCrisperDspEngine`, `CrisperPcmAudioSink`, and
`CrisperRenderersFactory`. JNI range checks and exception translation live in
`android/src/main/cpp/crisper_audio_jni.cpp`. The C ABI and bounded streaming
engine live under `native/crisper_dsp`; Bungee Basic and Signalsmith use their
actual pinned sources. WSOLA uses the maintained BSD-3-Clause portable
Chromium extraction under `native/crisper_dsp/wsola`. Its unchanged derivation
and reference sources are separately retained under `vendor/chromium-wsola`,
with exact revision, tree, Git blob and SHA-256 pins; Chromium's browser/runtime
is outside the app compilation closure. The fork's origin map and modifications
are documented in [its provenance](native/crisper_dsp/wsola/UPSTREAM.md).
Sonic C supplies a host comparison baseline, while the app's default stays on
Media3's existing Sonic implementation.

Gradle builds the C++ source locally with NDK `28.2.13676358` and CMake `3.22.1`.
The fork's Android minimum SDK is 21 (the app itself requires 24). The JNI target
requests 16 KB ELF page alignment; its consumer R8 rule preserves JNI names.
No downloaded binary, runtime source fetch, reflection or private API is used.
The core is optimized in Debug as well as Release because unoptimized spectral
processing is unsuitable for real-time playback.

`pubspec.yaml` identifies the local version and prevents accidental publishing.
`analysis_options.yaml` suppresses `use_super_parameters` locally, keeping
unrelated upstream constructors unchanged under the app's newer lint set.

## Verification and updates

From the app repository root, verify that every retained upstream file matches
the published source and that the reviewed patch contains every local change:

```sh
python3 packages/just_audio/tools/check_upstream_patch.py \
  --upstream "$PUB_CACHE/hosted/pub.dev/just_audio-0.10.6"
```

The original package may need to be fetched into the cache separately when
working in a fresh checkout. The verifier does not download anything or modify
the package. Treat a changed original hash or an unrecorded diff as a review
failure; do not silently regenerate the manifest to make a check pass.

`test/apple_speed_processing_test.dart` exercises the actual AudioPlayer →
platform-interface → method-channel serialization for both modes, including
native-instance recreation and the unaffected Android configuration path.
`test/speed_controls_test.dart` covers persisted/default/invalid preferences,
platform capability checks and the iOS/macOS restart-required UI.

`test/android_speed_processing_test.dart` checks the real Dart method-channel
configuration for all four Android selections and player-instance recreation.
The native tests can be run from the app's `android` directory:

```sh
./gradlew :just_audio:testDebugUnitTest
./gradlew :just_audio:connectedDebugAndroidTest
```

`CrisperAudioProcessorTest` exercises Media3's actual pipeline with a deterministic
engine test double: partial writes, unread buffers, EOS polls, finite drain,
source clocks, rate checkpoints, seeks, mono/stereo configuration and disabled
passthrough/offload. `CrisperDspJniTest` loads the real packaged JNI core, checks
all three optional algorithms' generated PCM duration and pitch, source counters, exact unity
stereo, handle replacement and invalid-buffer errors, and runs the real core
inside Media3's pipeline. WSOLA also checks opposite-phase stereo at 0.75× and
2×. These tests establish transport and signal invariants,
not a subjective quality ranking or an audible-device comparison.

The same 16 Java/JNI tests passed under the host JVM against actual Media3 1.4.1
JARs and the compiled native core during development. Host-only Android Build
constants and OpenJDK development headers stayed in ignored build output.
Android NDK/ABI, APK packaging and emulator tests are separate CI gates; a host
pass is not an Android device pass. The core's standalone streaming tests and
reproducible four-processor A/B renderer are under `native/crisper_dsp/tools`.
The preserved-original WSOLA helper comparison compiles the unchanged Chromium
scalar helper with test-only framework shims, compares selected semantics with
the portable SIMD/scalar helper, and documents intentional edge-case changes.
Those shims and retained reference originals are never linked into the app.

The native `ios/RunnerTests` and `macos/RunnerTests` exercise actual AVPlayerItem
properties for default, Time Domain and Spectral settings, including loop-copy
creation and flipping. The Apple audio CI workflow compiles macOS and iOS
simulator builds and runs the macOS native tests. Flutter transport/widget tests
on Linux do not run AVFoundation or establish audible quality. Native build/test
results and device listening comparisons must be reported separately.
Compare voice-only and music-backed passages at several speeds,
including seeking, loop/track transitions, background playback and interruptions.

For an upstream update, obtain the exact new archive, audit its license and
platform changes, reapply the configuration and processor hooks, update the
recorded hashes and reviewed diff, then rerun Dart, Media3, JNI, native DSP,
Android and Apple verification. Prefer upstream-supported configuration hooks
when they become available.
