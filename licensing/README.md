# Recorded distribution evidence

The project policy is described in [LICENSE_POLICY.md](../docs/LICENSE_POLICY.md).
The external-dependency restriction applies to third-party components. The
user explicitly confirmed ownership of CrisperPlayer and `crisp_storage`,
dual-licensing authority, and existing section 7 App Store exemptions. Those two
exact identities are outside the external GPL/AGPL restriction. Their existing
license notices remain unchanged, and the inventory records the user's
instruction as its policy basis, without inventing published exception text.
External native provenance and distribution requirements remain unresolved.

After resolving the committed dependencies with `flutter pub get`, run:

```sh
python3 scripts/check_distribution_licenses.py --report --platform all \
  --output build/licensing/report.json
python3 scripts/check_distribution_licenses.py --enforce --platform ios \
  --output build/licensing/ios-report.json
```

Report mode exits successfully even when it reports blockers, so routine CI
can preserve an evidence report. Enforce mode exits with status 1 when any
blocker remains. Missing or malformed input is a blocker. Neither mode
certifies an IPA, APK, desktop executable, compliance with every license
obligation, or acceptance by an app store.

## What is checked

`dependencies.json` records the actual production dependency closure from
`.dart_tool/package_graph.json`. The checker follows every transitive
`dependencies` edge and excludes branches reachable only through
`devDependencies`. A test-named package reached through a production dependency
is still included. All platform implementations in that graph remain in scope;
the script does not assume that tree shaking removes an unwanted license.

Each package entry identifies the exact version, hosted archive hash or Git
commit, package metadata hash, and the exact license files inspected. Local
vendor packages also carry a source-tree hash. The SDK has separate Flutter,
Dart, framework, and engine pins. Recorded Gradle, CocoaPods, CMake, Swift
package, and native build-hook inputs are hashed so that changed native
dependency declarations require another review.

`review_status: reviewed` on a package means its **recorded package-level grant**
was identified. It does not approve separate native payloads, copied third-party
code, patent rights, signing restrictions, or uninspected transitive build
dependencies. `sky_engine` is an aggregate notice and remains unclassified;
mentions of GPL in BSD compatibility language or MPL definitions are not proof
that a particular GPL component is shipped.

`native_artifacts.json` records the separate native evidence and unresolved
distribution requirements. Target selection applies to these components and
their build inputs. Missing required components, unknown grants, incomplete
reviews, and explicit provenance blockers all prevent an enforced pass. The
checker validates recorded evidence and local evidence-file hashes; it does not
download, build, load, or inspect a release binary. Use the artifact-specific
audit tools and record their results before completing a native review.

The license policy reads explicit SPDX metadata instead of searching legal
prose for the letters `GPL`. LGPL-3.0 incorporates the GPL-3.0 text; that does
not make an LGPL-only component a forbidden GPL component. External GPL/AGPL
identifiers are blocked. An external dual-license offer containing a forbidden grant must
have an explicitly reviewed selection of an allowed grant in the inventory;
the checker does not select one automatically. Unknown licenses and exceptions
require a policy decision. The exact `Apache-2.0 WITH LLVM-exception` pair is
recognized as a permissive grant; the exception does not approve a different
base license or any uninspected LLVM third-party code. See the
[upstream LLVM grant](https://llvm.org/LICENSE.txt).

## Shared native processor source evidence

The `portable-native-speed-processors` entry is required on Android, iOS,
macOS, Linux and Windows. It separates three review states:

| Evidence | Current scope |
| --- | --- |
| Source review | Reviewed: seven exact upstream revisions, six archive hashes and the Chromium Git snapshot, with 258 original source and notice files verified against the vendored manifest. |
| License review | Reviewed: independent MIT core/Apple adapters; Sonic Apache-2.0; Signalsmith Stretch/Linear MIT; Chromium WSOLA BSD-3-Clause; Bungee Basic MPL-2.0; selected Eigen Core MPL-2.0 with retained BSD/Apache notices; exact permissive PFFFT/FFTPACK notice. Desktop wrappers and linked mpv/FFmpeg retain their separate grants. |
| Target artifact review | Pending: Android ABI/APK checks, Apple library/application builds and controlled desktop libmpv builds each need packaged native hashes, dependency inspection, source/build correspondence, notices and playback validation. |

The checker reads the pinned native source manifest as well as the bundle's
top-level license declaration. A new or changed file, stale manifest, missing
source pin, or forbidden transitive declaration is a blocker. The app package
also pins the complete vendor tree, reviewed upstream patch, local additions,
Gradle/CMake/CocoaPods/SwiftPM recipes, JNI/Java/Apple adapters and source-test
files. The vendored desktop adapter has its own original hashes and source-tree
pin. Shared DSP notices and license registration are separately hashed as
evidence. The asset keeps its historical `ANDROID-DSP.txt` filename while
identifying all platforms that use the shared core.

`LicenseRef-PFFFT-FFTPACK` identifies the actual NCAR/UCAR permissive notice;
it is not substituted with an inaccurate standard license name. The checker
recognizes that reference only for the exact portable DSP component, PFFFT
source component, notice path and SHA-256 already reviewed. Copying the string
into another package or native component does not create an approval.

The source files match the [immutable published vendor tree](https://github.com/CrispStrobe/crisperplayer/tree/bea68aca9a357ce713e83653c269de7937e9fc63/packages/just_audio/native/crisper_dsp/vendor).
The original MPL-covered files are unmodified. Unsupported and GPL-only Eigen
modules are omitted, and the build enforces `EIGEN_MPL2_ONLY`. The app preserves the
upstream notices and gives the corresponding-source URL. Host signal and
Media3/JNI results are retained in
[native_dsp_host_2026-11-10.json](evidence/native_dsp_host_2026-11-10.json),
which explicitly does not approve a release artifact.

The pinned NDK `28.2.13676358` and its `libc++_shared.so` are a separate native
component. The [official NDK documentation](https://developer.android.com/ndk/guides/cpp-support)
identifies the upstream LLVM grant and explains that this shared runtime must
ship in the app. Exact redistributed runtime bytes, third-party notices and
APK dependency resolution still need artifact evidence. Neither the DSP source
review nor an allowed upstream runtime license removes that requirement.

Machine reports expose `native_source_reviews` separately from distribution
findings. A verified source manifest is not an artifact approval; an explicitly
pending artifact cannot pass merely by changing an overall review label.
When a vendored source manifest is shared by several targets, a reviewed entry
must include an exact artifact hash identified with each selected `platform`.
A Linux artifact cannot satisfy an iOS, macOS, Android or Windows review just
because the source files are the same.

## Exact ownership scope

`ownership_authorization` records the explicit user instruction for
`crisperplayer` at the application root and `crisp_storage` at the recorded
CrispCloud repository, package path, and commit. The checker matches those
identities against a narrow policy allowlist. Merely adding a `user_owned`
label to another inventory row, reusing a package name from a different source,
or naming an owner namespace does not create an exemption.

Ownership affects only the external GPL/AGPL restriction. Version/source pins,
metadata and license-file hashes, malformed or missing grants, and every
external transitive dependency remain checked. The report lists the two
applied policy exemptions explicitly. This authorization neither inherits to
their dependencies nor extends to native components. No additional ownership
confirmation or relicensing action is required for these two components.

## Updating the evidence

1. Inspect the exact changed package sources and native dependency recipes.
   Preserve their original copyright, license, and notice files.
2. Verify source archives, immutable revisions, build configuration, binary
   hashes, and corresponding-source material for any native payload.
3. Review the actual distribution obligations, including MPL source disclosure
   and LGPL replacement/relinking obligations where applicable. A permissive
   wrapper never substitutes for the payload's own review.
4. Update the relevant entry and its evidence only after that review. There is
   deliberately no command that silently regenerates approvals from a new
   lockfile. Keep `needs_review` and specific blockers when evidence is missing.
5. Run the Python tests and inspect the report for every release platform:

```sh
python3 -m unittest scripts.tests.test_distribution_licenses
```

Hashes cover exact file bytes. Preserve source line endings when preparing a
checkout; an unexpected hash difference must be investigated before updating
the recorded hash. A result of `recorded_checks_passed` means only that the
recorded checks passed for the current resolved checkout.
