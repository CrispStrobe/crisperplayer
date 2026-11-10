# License audit and Apple processing validation

Verified on 10 November 2026 with Flutter 3.44.4 and Dart 3.12.2 on the
`feature/return-trail` branch. No release, store upload or source relicensing
was performed.

| Check | Observed result |
| --- | --- |
| Full `flutter analyze --no-pub`, including the maintained adapter | No issues found |
| Combined playback/journal/map/trail/speed/accessibility regression run | 181 passed; one optional journal screenshot capture skipped |
| All Python release, evidence and candidate-build checks | 53 passed |
| just_audio provenance verifier | All 38 retained upstream file hashes and the complete seven-file patch verified |
| Compiled CLI and executable help | Passed |
| Flutter web build | Passed; this target remains the native app availability notice |
| Modified workflow YAML and `git diff --check` | Passed |
| Actual Flutter Apple processing preview | Inspected at 390 × 844; active and pending modes are distinct and the restart requirement is visible |
| Real-checkout distribution report | 168 production packages and 10 native components inventoried; result intentionally blocked |
| Enforce-mode check | Reports incomplete external evidence; project-owned grants are covered by the owner's confirmed distribution authority |
| Windows audio artifact | Exact archive and DLL hashes checked; LGPL-compatible native configuration/license markers found |
| Controlled Linux source preparation | Four pinned archives verified and safely unpacked; build plan and negative checks passed |

The combined Flutter command is in
[journal and speed validation](JOURNAL_SPEED_VALIDATION.md). Focused results
overlap that total and must not be added to it. Python checks run with:

```sh
python3 -m unittest discover -s scripts/tests -v
```

The license checker is exercised against fixtures with forbidden grants,
tampered source/license hashes, changed dependencies, missing native evidence,
malformed input, dev-only exclusions, transitive production dependencies, and
cross-platform file URIs. Artifact tests cover GPL/nonfree build flags, missing
native markers and a changed DLL even when its strings still look compatible.
Candidate-build tests cover source-cache tampering, safe extraction, explicit
build flags, PCM measurements and the app's actual legacy speed-filter mapping.

## Checks still required on native runners

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
