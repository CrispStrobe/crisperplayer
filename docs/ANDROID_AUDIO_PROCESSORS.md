# Optional Android audio processors

CrisperPlayer keeps Media3 Sonic as the default and adds real, experimental
native Bungee Basic and Signalsmith Stretch alternatives. Choose a processor
under **Speed → Speed processing**, then restart the app. The choice applies
to all books. The displayed active processor does not change merely because
a different preference has been saved.

| Choice | Intended comparison | Limits in this integration |
| --- | --- | --- |
| Sonic | Spoken audio, including high listening rates | Existing Media3 path and skip-silence support remain unchanged. |
| Bungee Basic | Narration with music or ambience | Experimental; mono/stereo; skip silence unavailable. |
| Signalsmith Stretch | Moderate changes, approximately 0.75×–1.5× | Experimental; mono/stereo; skip silence unavailable. The full app rate range is accepted, but high-rate speech superiority is not claimed. |

The native processors accept 8–192 kHz PCM and rates from 0.50× to 3.00×.
At 1.00× the adapter passes samples through unchanged. Global and per-book
skip-silence settings are preserved while a native alternative is active;
the settings explain that Sonic is required to use them.

## Playback and source time

The maintained just_audio adapter passes the startup selection into a custom
Media3 1.4.1 `AudioProcessorChain`. This chain owns the only speed stage.
Using a custom processor with the *default* chain would leave Sonic after it
and apply the speed twice, so the implementation replaces the chain itself.

The custom sink disables encoded passthrough, offload, floating-point output
and AudioTrack speed changes. Media3 decodes and converts to PCM16 before the
native stage. The ordinary Sonic construction path remains upstream behavior
and does not load the JNI library. Existing audio-effect renderer observation
is retained for both paths.

The C ABI uses interleaved frames, bounded queues and partial writes. The
Java processor retains returned output until Media3 consumes it and accepts
empty end-of-stream polls. Finishing drains the native tail; a seek or new
processing segment discards old input, output and lookahead. Changes in speed
are applied after Media3 drains the previous segment.

Clock conversion uses source frames represented by **delivered output**, not
decoded input waiting in a queue. Priming and final padding do not advance the
book's position. Counters use 64-bit frames, and the Bungee adapter rebases its
granular input coordinates instead of allowing a cumulative 32-bit stream
offset to overflow during a long audiobook. Both normal app startup and the
PlaybackService fallback constructor pass the same immutable configuration.

This keeps played ranges, historical jumps and resume coordinates in the
original recording's timeline. It does not turn the listening journal on;
that remains a separate, default-off preference.

## External source and license closure

All selected source is vendored. Builds do not fetch a moving branch or
download processor code at runtime. The source manifest records exact upstream
revisions, archive hashes and hashes for every selected file:

| Component | Revision | License |
| --- | --- | --- |
| Sonic C comparison baseline | `b93885dcb70aae50c6f76b0fe4e0868f029a077e` | Apache-2.0 |
| Bungee Basic | `61f52bf34be577d189d388772ddfa3696dee77d8` | MPL-2.0 |
| Eigen selected Core sources | `c29c800126982c561e8d0b9255dc65474cd98de3` | MPL-2.0 and retained BSD/Apache notices |
| PFFFT / FFTPACK | `02fe7715a5bf8bfd914681c53429600f94e0f536` | Original permissive NCAR/UCAR notice; recorded as `LicenseRef-PFFFT-FFTPACK` |
| Signalsmith Stretch | `88061fd4eda56a2353c5d65c74aa3f4ccf76f9da` | MIT |
| Signalsmith Linear | `7bb1c8f36794d6980080ce817c91f8da8fe56a66` | MIT |

`EIGEN_MPL2_ONLY` is defined for the selected build. Unsupported Eigen modules,
proprietary Bungee Pro, Sonic Speedy and external FFT backends are excluded.
The upstream files are unmodified; the independent adapter and JNI bridge
are MIT licensed. Original notices and a link to the exact public source
snapshot are included in the app's license screen through
`assets/licenses/ANDROID-DSP.txt`.

The owner's confirmed distribution authority for their own AGPL code is
separate from this external dependency policy. This implementation adds no
GPL-only or AGPL-only external processor. Existing desktop/libmpv and other
native payload evidence is tracked separately in [the policy](LICENSE_POLICY.md).

## Reproduce the checks

Build the actual C/C++ implementations, verifying the selected source closure
first, then exercise the streaming interface:

```sh
python3 packages/just_audio/native/crisper_dsp/tools/build_host.py --jobs 2
python3 packages/just_audio/native/crisper_dsp/tools/test_streaming.py \
  --library build/native-dsp/libcrisper_dsp.so \
  --report build/native-dsp/test-report.json
```

The host suite checks output duration, preserved tone pitch, separate stereo
channels, source counters, arbitrary input/output chunk sizes, short and empty
clips, exact unity-rate PCM, bounded backpressure, reset isolation, and audio
at the beginning and end of a track. The report retains measurements even
where the Sonic reference removes an isolated impulse at high speed; it does
not reinterpret that synthetic measurement as a speech-intelligibility result.

The Android plugin also contains tests against the real Media3 processing
pipeline and JNI tests that execute the real algorithms. On an Android SDK
checkout, run:

```sh
flutter pub get
flutter test --no-pub test/android_speed_processing_test.dart test/speed_controls_test.dart
python3 scripts/check_distribution_licenses.py --report --platform android \
  --output build/android-audio-evidence/source-license-report.json
python3 scripts/audit_android_audio.py prepare-notices \
  --ndk "$ANDROID_HOME/ndk/28.2.13676358" \
  --output build/android-audio-evidence/ndk-notices.json
flutter build apk --debug --no-pub --target-platform android-arm64,android-x64
flutter build apk --release --no-pub --target-platform android-arm64,android-x64
python3 scripts/audit_android_audio.py inspect \
  build/app/outputs/flutter-apk/app-release.apk \
  --ndk "$ANDROID_HOME/ndk/28.2.13676358" \
  --abi arm64-v8a --abi x86_64 \
  --source-revision "$(git rev-parse HEAD)" \
  --output build/android-audio-evidence/release-apk.json
cd android
./gradlew :just_audio:testDebugUnitTest
./gradlew :just_audio:connectedDebugAndroidTest -Ptarget-platform=android-x64
```

The connected task needs a running Android device or emulator. The dedicated
[Android audio workflow](../.github/workflows/android-audio.yml) installs the
pinned NDK/CMake versions, compiles arm64 and x86-64 debug and release app
integration, runs the Media3 tests and executes the JNI tests on an API 35
emulator. Its release build uses the local debug key with R8/resource shrinking
enabled; it needs no store signing credentials. The general CI and signed
release workflows also run the notice preparation and inspect their final
three-ABI APKs, including armv7. Existing release signing and policy gates
remain in force.

## Inspect the actual Android package

`scripts/audit_android_audio.py` reads APK ZIP members and ELF/DEX structures
using the Python standard library. It records the APK hash and every packaged
native library's hash, ABI, dynamic dependencies and load layout. Each requested
ABI must include the DSP library and C++ shared runtime. The 64-bit libraries
must have 16 KB ELF load alignment and uncompressed, 16 KB-aligned ZIP entries.
Required JNI symbols must be reachable through the loader's real symbol/hash
tables and point into executable segments. The DEX class must retain all eight
native method names/signatures and their proper declaration kinds, so an R8
build cannot pass merely because a class name survives as an unused string.

The packaged `libc++_shared.so` must match the installed, pinned NDK's bytes,
either directly or after that NDK's own `llvm-strip --strip-unneeded` operation
on the trusted installed source file. The report records that transformation
and tool hash. APK library contents are never executed or supplied to a tool.

Before Flutter packages its assets, `prepare-notices` collects the exact
installed `NOTICE`, `NOTICE.toolchain` and `source.properties` files. It writes
their original bytes and hashes to build evidence and generates the app's
`assets/licenses/ANDROID-NDK.txt`. Inspection then requires that exact asset
inside the final APK. The checked-in explanatory placeholder cannot pass.
These aggregate notices describe build tools as well as the packaged runtime;
their inclusion does not mean those tools are shipped or linked into the app.

Source evidence checks run **before** this generated asset replacement. The
prepared asset is verified against the final artifact instead of silently
updating the source manifest to match a generated file. CI publishes the
original notices, asset, hashes and reports. The signed release path inspects
the staged APK that will be published, after signing and before publication.

These checks supply APK packaging evidence. They do not claim a reproducible
source-to-binary build, validate AAB/store delivery, or approve a release. Actual
ExoPlayer/AudioTrack behavior still needs device checks for rate changes,
seeking, buffering, completion, audio focus and long-book source-clock accuracy.
The existing JNI tests execute the real processors but do not replace that
complete player/decoder/output-path test.

Local validation in this Linux workspace includes the actual native core,
Java/Media3 lifecycle and host-JVM JNI execution. It does not include an
Android APK build or Android-device execution because the SDK/NDK is not
installed here. Consult the exact commit's PR checks for those results.

## Compare sound before choosing a default

Use the native package's WAV comparison renderer to produce the same passage
with Sonic, Bungee Basic and Signalsmith at identical requested rates. Start
with clean narration, then music-backed narration, several voices/languages,
and short chapter transitions. Compare intelligibility, consonants, transients,
noise and fatigue at 1.25×, 1.5×, 2× and 3×. Check CPU/battery use, seeking,
pause/resume, headphone changes and background interruptions on target devices.

Synthetic correctness tests establish usable timing and signal transport.
They do not establish a best-sounding processor. Sonic remains the default
until a listening comparison gives a reason to change that decision.

Primary upstream descriptions: [Sonic](https://github.com/waywardgeek/sonic),
[Bungee](https://github.com/bungee-audio-stretch/bungee), and
[Signalsmith Stretch](https://github.com/Signalsmith-Audio/signalsmith-stretch).
The source manifest and retained licenses are authoritative for the exact
versions used here, rather than whatever a project may publish later.
