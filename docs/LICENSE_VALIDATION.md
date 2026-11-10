# License audit and native processing validation

Verified on 10 November 2026 with Flutter 3.44.4 and Dart 3.12.2 on the
`feature/return-trail` branch. No release, store upload or source relicensing
was performed.

| Check | Observed result |
| --- | --- |
| Full `flutter analyze --no-pub`, including the maintained adapter | No issues found |
| Combined playback/journal/map/trail/speed/accessibility regression run | 190 passed; one optional journal screenshot capture skipped |
| All Python release, evidence and candidate-build checks | 67 passed, including 33 distribution-checker tests |
| just_audio provenance verifier | 38 retained upstream hashes, nine modified original files and 20 local adapter additions verified |
| Compiled CLI and executable help, earlier branch checkpoint | Passed; not rerun for the Android processor addition |
| Flutter web build, earlier branch checkpoint | Passed; this target remains the native app availability notice; not rerun for the Android processor addition |
| Modified workflow YAML and `git diff --check` | Passed |
| Native C++ streaming core | GCC/G++ 14.2 compile/link passed; 11 test methods passed, including 72 rate/channel/sample-rate combinations |
| Android plugin Java and Media3 lifecycle | Complete plugin compiled against Media3 1.4.1 and the current Flutter embedding; 10 lifecycle tests passed using the real Media3 pipeline |
| Actual JNI integration on host JVM | Four tests passed with real Bungee/Signalsmith output, including the native core in the real Media3 pipeline |
| Native source closure | All 252 selected upstream files verified against the pinned manifest; original notices included in the app |
| WAV comparison renderer | Six-second synthetic input produced exact four-second output at 1.5× for all three engines; no saturated PCM samples |
| Actual Flutter Apple processing preview | Inspected at 390 × 844; active and pending modes are distinct and the restart requirement is visible |
| Real-checkout distribution report | 168 production packages and 12 native components inventoried; remaining external artifact evidence is reported separately from reviewed DSP source |
| Enforce-mode check | Reports incomplete external evidence; project-owned grants are covered by the owner's confirmed distribution authority |
| Windows audio artifact | Exact archive and DLL hashes checked; LGPL-compatible native configuration/license markers found |
| Controlled Linux source preparation | Four pinned archives verified and safely unpacked; build plan and negative checks passed |

The combined Flutter command is in
[journal and speed validation](JOURNAL_SPEED_VALIDATION.md); this run also includes
`test/android_speed_processing_test.dart`. The 22 focused Android/Apple/speed
cases are included in the 190 total and must not be added to it. Python checks run with:

```sh
python3 -m unittest discover -s scripts/tests -v
```

The license checker is exercised against fixtures with forbidden grants,
tampered source/license hashes, changed dependencies, the exact PFFFT grant,
LLVM exception pairs, native source-closure changes, missing native evidence,
malformed input, dev-only exclusions, transitive production dependencies, and
cross-platform file URIs. Artifact tests cover GPL/nonfree build flags, missing
native markers and a changed DLL even when its strings still look compatible.
Candidate-build tests cover source-cache tampering, safe extraction, explicit
build flags, PCM measurements and the app's actual legacy speed-filter mapping.

## Android validation and remaining device checks

The Android settings and transport tests verify every enum value, native-player
recreation, active versus pending settings, saved skip-silence preferences and
the unchanged Sonic default. Both Bungee Basic and Signalsmith Stretch are
explicit experimental opt-ins.

Host JNI execution uses actual Media3 1.4.1 classes and the compiled native core.
A host-only Android Build constants shim is needed because Android framework
native methods cannot run on the desktop JVM. Development headers and that shim
are not part of the application. The tests validate signal/transport invariants,
not device sound, battery consumption or an algorithm quality ranking. The
[recorded host evidence](../licensing/evidence/native_dsp_host_2026-11-10.json)
retains source hashes and individual synthetic measurements.

The dedicated Android workflow builds arm64/x86-64 APK integration, exercises
Media3 lifecycle tests, and runs the same actual JNI tests on an API 35 emulator.
The Android SDK/NDK is not installed in this workspace, so Android ABI, APK and
device checks have not been executed locally. Check the exact PR commit for
those CI results. See [Android processor details](ANDROID_AUDIO_PROCESSORS.md).

## Other checks still required on native runners

The Apple workflow compiles both the macOS and iOS AVFoundation paths, runs the
macOS native XCTest assertions, and compiles the iOS test target. Those assertions
inspect real AVPlayerItem properties for absent/default configuration, Time
Domain, Spectral and loop copies. They do not assess audio fidelity. These
native tests cannot run in this Linux workspace; consult the current
[PR checks](https://github.com/CrispStrobe/crisperplayer/pull/1) for their result.

The Linux candidate build was not completed. Its preflight explicitly stops at
the missing Meson toolchain in this environment; required development libraries
are also absent. The real PCM smoke harness is supplied but has not run against
a controlled candidate here. The app still uses its existing desktop loader;
no unbuilt candidate is represented as an installed engine.

No target-device listening comparison, CPU/battery measurement, or blanket
App Store compatibility finding is claimed. The owner has confirmed authority
to distribute their own CrisperPlayer and `crisp_storage` code, including App
Store additional permissions; no relicensing or further confirmation is needed.
Signed distribution still requires review of the exact external native payloads
and their corresponding-source, notice and modification rights.
See [the policy](LICENSE_POLICY.md), [recorded evidence](../licensing/README.md),
and [desktop artifact findings](DESKTOP_AUDIO_BUILD.md).
