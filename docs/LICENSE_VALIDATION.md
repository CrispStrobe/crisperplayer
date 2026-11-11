# License audit and native processing validation

## Direct Dart/native desktop checkpoint — 11 November 2026

Work on `feature/portable-speed-engines` replaces the Windows/Linux mpv path
with Dart transport, bounded Glint decoding, the shared four-engine DSP core
and native output. Android and Apple retain their existing platform adapters.
No release or store upload was performed. The current implementation and its
codec limits are described in [portable processing](PORTABLE_AUDIO_PROCESSORS.md).

| Current check | Observed result |
| --- | --- |
| Full root `flutter analyze --no-pub` after decoder/parser integration | No issues found |
| Required-library Dart decoder/parser/player/clock/app-adapter suite | 64 passed, no skips; uses the compiled native library |
| Native output checks | 13,455 passed, including bounded queues, manual output and a real null-device callback thread |
| Native sanitizers | AddressSanitizer and UndefinedBehaviorSanitizer passed; LeakSanitizer could not run under this environment's ptrace setup |
| Python evidence/release/audit regressions | 110 passed |
| Flutter web build | Passed; this target remains the native-app availability notice |
| Broader root Flutter suite | 383 passed, five skipped, 11 failed in browser-upload setup because this environment could not enumerate network interfaces (`Bad value for ai_flags`); this is not recorded as a full-suite pass |
| Source and runtime inventory | 159 production packages, ten active native components; retired desktop mpv/FFmpeg identities remain historical evidence |
| AAC table provenance | Offline regeneration from immutable Apache-2.0 vo-aacenc inputs; all 45 arrays and 3,229 numerical values unchanged, full notices retained |
| Distribution report | 226 recorded native build/evidence inputs; no source/version/hash drift or forbidden-declared-grant finding; 31 package/runtime artifact and distribution review findings remain explicit |

The 64 native Dart checks include 24 decoder tests, 19 MP4 parser tests,
15 player/probe tests, three source-clock tests and three actual app-adapter
tests. They cover exact FLAC PCM at 16/24 bits, compressed-window refills,
MP3/AAC/M4B seeking, MP4 offsets beyond 4 GiB, bounded tables with millions of
packets, 64-bit edit arithmetic, local media references, cancellation, queue
reset, finite tails and source time through all four engines. The synthetic
M4B fixture decodes 176,400 frames and retains its expected tones; this is a
functional regression, not a listening-quality ranking.

The native artifact audit verifies the retained DSP, Glint and miniaudio
source hashes, loads the actual ABI and exercises the four processors plus
decoder/output contracts. Bundle checks additionally reject misplaced,
duplicate or legacy mpv/FFmpeg-family payloads. The native clock accounts for
estimated backend buffering; it does not measure hardware/DAC presentation.

Current target results belong to the exact commit's
[PR checks](https://github.com/CrispStrobe/crisperplayer/pull/2). Earlier runs
compiled the macOS application and shared SwiftPM processor target, and the
Linux workflow compiled the real Flutter bundle. Superseded Apple/Android
jobs were cancelled before all target tests completed. Passing a host build
does not establish physical-device output, interruption handling or latency.
Artifact and distribution review remains separate from these functional tests.
The [direct native host evidence](../licensing/evidence/direct_native_audio_2026-11-11.json)
records the exact library/source hashes, audit output and test scopes. Counts
from overlapping runs must not be added together.

## Historical listening-memory and native processor checkpoint

Verified on 10 November 2026 with Flutter 3.44.4 and Dart 3.12.2 on the
`feature/return-trail` branch. No release, store upload or source relicensing
was performed. The following results and desktop mpv observations describe
that earlier checkpoint; the current desktop path is documented above.

| Check | Observed result |
| --- | --- |
| Full `flutter analyze --no-pub`, including the maintained adapter | No issues found |
| Combined playback/journal/map/trail/speed/accessibility regression run, including passage reports | 216 passed at the preceding listening-memory checkpoint; one optional journal screenshot capture skipped |
| Current Android/Apple configuration and speed-control checks | 25 passed, including WSOLA selection at 320 px / 200% text |
| All Python release, evidence and candidate-build checks | 93 passed, including 37 distribution-checker tests and 22 Android APK-audit tests |
| just_audio provenance verifier | 38 retained upstream hashes, nine modified original files and 38 local adapter/fork/test additions verified |
| Compiled CLI and executable help, rerun with passage filtering | Passed |
| Flutter web build, rerun with passage reports | Passed; this target remains the native app availability notice |
| Modified workflow YAML and `git diff --check` | Passed |
| Native C++ streaming core | GCC/G++ 14.2 compile/link passed; 15 test methods passed, including 96 rate/channel/sample-rate combinations |
| WSOLA search and preserved-original comparison | Eight compiled search checks and 12 original-versus-port test methods passed; independent 300-case boundary review passed |
| Android plugin Java and Media3 lifecycle | Complete plugin compiled against Media3 1.4.1 and the current Flutter embedding; 11 lifecycle tests passed using the real Media3 pipeline |
| Actual JNI integration on host JVM | Five tests passed with real Bungee/Signalsmith/WSOLA output, including the native core in the real Media3 pipeline |
| Native source closure | All 258 selected upstream originals verified against the pinned manifest; derived WSOLA code is separately identified and original notices are included in the app |
| Android package inspector on synthetic fixtures | 22 checks passed for ELF/DEX/ZIP/JNI/NDK identity and failure cases; this is not an actual APK inspection |
| Package inspector on the existing actual host JNI ELF | Eight reachable JNI exports and four 16 KB load segments verified; host ELF is not an Android APK |
| WAV comparison renderer | Six-second synthetic input produced exact four-second output at 1.5× for all four engines; no saturated PCM samples |
| Actual Flutter Apple processing preview | Inspected at 390 × 844; active and pending modes are distinct and the restart requirement is visible |
| Real-checkout distribution report | 168 production packages and 12 native components inventoried; remaining external artifact evidence is reported separately from reviewed DSP source |
| Enforce-mode check | Reports incomplete external evidence; project-owned grants are covered by the owner's confirmed distribution authority |
| Windows audio artifact | Exact archive and DLL hashes checked; LGPL-compatible native configuration/license markers found |
| Controlled Linux source preparation | Four pinned archives verified and safely unpacked; build plan and negative checks passed |

The combined Flutter command is in
[journal and speed validation](JOURNAL_SPEED_VALIDATION.md). The focused runs
overlap with the earlier 216 total and must not be added to it. The latest WSOLA
implementation and exact native evidence are documented in
[WSOLA validation](WSOLA_VALIDATION.md). Python checks run with:

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

The final source report verifies 168 production packages, 12 native components
and 144 explicit native build/evidence inputs. No stale source hash, forbidden
declared grant or ownership-scope finding was introduced by this slice. Pending
artifact/provenance reviews remain visible and are not promoted based on script
fixtures. The generated NDK notice asset is inspected inside actual APKs;
source gates run before that build-time replacement.

## Android validation and remaining device checks

The Android settings and transport tests verify every enum value, native-player
recreation, active versus pending settings, saved skip-silence preferences and
the unchanged Sonic default. Bungee Basic, Signalsmith Stretch and WSOLA are
explicit experimental opt-ins.

Host JNI execution uses actual Media3 1.4.1 classes and the compiled native core.
A host-only Android Build constants shim is needed because Android framework
native methods cannot run on the desktop JVM. Development headers and that shim
are not part of the application. The tests validate signal/transport invariants,
not device sound, battery consumption or an algorithm quality ranking. The
[recorded WSOLA host evidence](../licensing/evidence/wsola_host_2026-11-10.json)
retains source hashes and individual synthetic measurements.

The dedicated Android workflow builds arm64/x86-64 APK integration, exercises
Media3 lifecycle tests, and runs the same actual JNI tests on an API 35 emulator.
The Android SDK/NDK is not installed in this workspace, so Android ABI, APK and
device checks have not been executed locally. Check the exact PR commit for
those CI results. See [Android processor details](ANDROID_AUDIO_PROCESSORS.md).

## Other checks still required on native runners

At `a8eef0650577b3a049d6a81a1b99011bcfe8fdb5`, Apple audio
[run 7](https://github.com/CrispStrobe/crisperplayer/actions/runs/42876463275)
successfully compiled macOS and ran all three native AVPlayerItem tests.
Its iOS build failed because the runner selected Xcode 16.4 while the pinned
`device_info_plus` 13.3.0 requires Xcode 26.1.1 or newer. The workflow now
selects installed Xcode 26.2 explicitly; its selection step passed on the next
run before that run was superseded by a newer feature-branch commit. Final iOS
and Android build results must come from the current commit's checks.

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
