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
require a policy decision.

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
