# just_audio: small Apple speed-processing patch

## Provenance and license

- Upstream package: **just_audio 0.10.6**, published by Ryan Heise.
- Source archive: <https://pub.dev/api/archives/just_audio-0.10.6.tar.gz>
- Published archive SHA-256, recorded in the original app lockfile and pub cache:
  `e60aa97b233ddea025e13dfac59195207f528fa5e9e4a4a49a8c0766701e5fe6`
- Upstream repository: <https://github.com/ryanheise/just_audio/tree/minor/just_audio>
- The upstream [MIT license](LICENSE) is retained unchanged. The local changes
  to this package are distributed under the same MIT license.
- Local package version: **0.10.6+crisper.1**, `publish_to: none`.

The 38 original source, platform build, documentation and notice files are
listed with their original SHA-256 values in [UPSTREAM_SHA256.json](UPSTREAM_SHA256.json).
All Dart, Android and shared Darwin runtime/build files are retained. Examples,
sample media and upstream test fixtures are omitted; no generated artifacts or
native binaries are vendored.

## Complete patch surface

[UPSTREAM.patch](UPSTREAM.patch) is the complete diff from those original files:

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
5. `pubspec.yaml` identifies this local version and prevents accidental publishing.
6. `analysis_options.yaml` suppresses `use_super_parameters` locally, keeping
   unrelated upstream constructors unchanged under the app's newer lint set.

No reflection, method swizzling, private Apple APIs, extra player registry or
global preferences are used. The public option is immutable for a player and
is included again if just_audio recreates that player's native instance.
CrisperPlayer presents it as a restart-required preference so active playback
is never reconfigured mid-passage.

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

The native `ios/RunnerTests` and `macos/RunnerTests` exercise actual AVPlayerItem
properties for default, Time Domain and Spectral settings, including loop-copy
creation and flipping. The Apple audio CI workflow compiles macOS and iOS
simulator builds and runs the macOS native tests. Flutter transport/widget tests
on Linux do not run AVFoundation or establish audible quality. Native build/test
results and device listening comparisons must be reported separately.
Compare voice-only and music-backed passages at several speeds,
including seeking, loop/track transitions, background playback and interruptions.

For an upstream update, obtain the exact new archive, audit its license and
platform changes, reapply the small option patch, update the recorded hashes
and reviewed diff, then rerun transport/UI tests and Apple native compilation.
An upstream implementation of this configuration option should replace the
local patch when available.
