import contextlib
import copy
import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_distribution_licenses as check


class DistributionLicenseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / ".dart_tool").mkdir()
        (self.root / "licensing").mkdir()
        (self.root / "pubspec.yaml").write_text("name: app\nversion: 1.0.0\n")
        (self.root / "LICENSE").write_text("Application MIT grant")
        self.graph = {
            "roots": ["app"],
            "packages": [{"name": "app", "version": "1.0.0", "dependencies": ["dependency"], "devDependencies": ["dev_tool"]}],
        }
        self.config = {
            "packages": [{"name": "app", "rootUri": "../"}],
            "flutterVersion": "3.44.4", "generatorVersion": "3.12.2",
            "flutterRoot": (self.root / "sdk").as_uri(),
        }
        self.sdk = {
            "flutter_version": "3.44.4", "dart_version": "3.12.2",
            "frameworkRevision": "a" * 40, "engineRevision": "b" * 40,
            "engineContentHash": "c" * 40,
        }
        sdk_file = self.root / "sdk/bin/cache/flutter.version.json"
        sdk_file.parent.mkdir(parents=True)
        sdk_file.write_text(json.dumps(self.sdk))
        self.inventory = {
            "schema_version": 1, "root_package": "app", "sdk": self.sdk,
            "root_pubspec_sha256": check.digest(self.root / "pubspec.yaml"),
            "packages": [self.entry("app", self.root, {"type": "root"})],
            "required_native_components": [{"id": "native", "platforms": ["ios"]}],
        }
        self.locks = {}
        self.add_package("dependency", dependencies=["transitive"])
        self.add_package("transitive")
        self.add_package("dev_tool", inventoried=False)
        self.native = {
            "schema_version": 1,
            "components": [{
                "id": "native", "platforms": ["ios"], "version": "1.0",
                "license_expression": "LGPL-2.1-or-later", "review_status": "reviewed",
                "artifact": {"url": "https://example.invalid/library", "sha256": "d" * 64},
                "source": {"repository": "https://example.invalid/source", "revision": "e" * 40},
                "evidence": [{"url": "https://example.invalid/review"}], "blockers": [],
            }],
        }
        self.save()

    def entry(self, name, source_root, source):
        return {
            "name": name, "version": "1.0.0", "source": source,
            "pubspec_sha256": check.digest(source_root / "pubspec.yaml"),
            "license_expression": "MIT", "review_status": "reviewed",
            "license_files": [{"path": "LICENSE", "sha256": check.digest(source_root / "LICENSE")}],
        }

    def add_package(self, name, dependencies=None, inventoried=True):
        source_root = self.root / "cache" / name
        source_root.mkdir(parents=True)
        (source_root / "pubspec.yaml").write_text(f"name: {name}\nversion: 1.0.0\n")
        (source_root / "LICENSE").write_text(f"MIT grant for {name}")
        source = {"type": "hosted", "name": name, "url": "https://pub.dev", "sha256": "f" * 64}
        self.locks[name] = source
        self.config["packages"].append({"name": name, "rootUri": source_root.as_uri()})
        self.graph["packages"].append({"name": name, "version": "1.0.0", "dependencies": dependencies or []})
        if inventoried:
            self.inventory["packages"].append(self.entry(name, source_root, source))

    def recorded(self, name):
        return next(row for row in self.inventory["packages"] if row["name"] == name)

    def authorize_owned_components(self):
        # Model the two exact identities authorized by the user's instruction,
        # while keeping the fixture's external dependency graph intact.
        self.graph["roots"] = ["crisperplayer"]
        self.graph["packages"][0]["name"] = "crisperplayer"
        self.graph["packages"][0]["dependencies"].append("crisp_storage")
        self.config["packages"][0]["name"] = "crisperplayer"
        self.inventory["root_package"] = "crisperplayer"
        (self.root / "pubspec.yaml").write_text("name: crisperplayer\nversion: 1.0.0\n")
        root_entry = self.recorded("app")
        root_entry["name"] = "crisperplayer"
        root_entry["pubspec_sha256"] = check.digest(self.root / "pubspec.yaml")
        self.inventory["root_pubspec_sha256"] = root_entry["pubspec_sha256"]
        self.add_package("crisp_storage", dependencies=["transitive"])
        source = copy.deepcopy(check.OWNED_COMPONENT_SOURCES["crisp_storage"])
        self.locks["crisp_storage"] = source
        self.recorded("crisp_storage")["source"] = source
        for name in ("crisperplayer", "crisp_storage"):
            entry = self.recorded(name)
            entry["license_expression"] = "AGPL-3.0-only"
            entry["license_policy_scope"] = "user_owned"
            entry["ownership_authorization"] = check.OWNERSHIP_AUTHORIZATION_ID
        self.inventory["ownership_authorization"] = {
            "id": check.OWNERSHIP_AUTHORIZATION_ID,
            "basis_type": "user_instruction",
            "basis": "User explicitly owns these components; external license policy still applies to their dependencies.",
            "components": [
                {"name": name, "source": copy.deepcopy(source)}
                for name, source in check.OWNED_COMPONENT_SOURCES.items()
            ],
        }

    def save(self):
        for path, value in (
            (".dart_tool/package_graph.json", self.graph),
            (".dart_tool/package_config.json", self.config),
            ("licensing/dependencies.json", self.inventory),
            ("licensing/native_artifacts.json", self.native),
        ):
            (self.root / path).write_text(json.dumps(value))
        lines = ["# Generated by pub", "packages:"]
        for name, source in self.locks.items():
            lines += [f"  {name}:", "    dependency: transitive", "    description:"]
            for key, value in source.items():
                if key != "type":
                    lines.append(f"      {key}: {json.dumps(value)}")
            lines += [f"    source: {source['type']}", '    version: "1.0.0"']
        lines += ["sdks:", '  dart: ">=3.12.0 <4.0.0"']
        (self.root / "pubspec.lock").write_text("\n".join(lines) + "\n")

    def findings(self, platform="all"):
        self.save()
        return check.audit(self.root, platform)["findings"]

    def codes(self, platform="all"):
        return {row["code"] for row in self.findings(platform)}

    def test_allowed_transitive_graph_passes_and_dev_only_is_excluded(self):
        report = check.audit(self.root)
        self.assertEqual(report["result"], "recorded_checks_passed")
        self.assertEqual(report["runtime_package_count"], 3)
        self.assertNotIn("dev_tool", {row["component"] for row in report["findings"]})

    def test_transitive_agpl_is_forbidden_even_under_a_permissive_wrapper(self):
        self.recorded("transitive")["license_expression"] = "AGPL-3.0-only"
        findings = self.findings()
        self.assertTrue(any(row["component"] == "transitive" and "Forbidden" in row["message"] for row in findings))

    def test_application_license_is_checked_independently(self):
        self.recorded("app")["license_expression"] = "AGPL-3.0-only"
        self.assertIn("license_policy", self.codes())

    def test_exact_user_owned_agpl_components_pass_without_rewriting_notices(self):
        self.authorize_owned_components()
        notices = [(self.root / "LICENSE"), (self.root / "cache/crisp_storage/LICENSE")]
        before = [path.read_bytes() for path in notices]
        self.assertEqual(self.findings(), [])
        report = check.audit(self.root)
        self.assertEqual({item["component"] for item in report["owned_policy_exemptions"]}, {"crisperplayer", "crisp_storage"})
        self.assertEqual([path.read_bytes() for path in notices], before)

    def test_external_agpl_under_owned_storage_is_still_blocked(self):
        self.authorize_owned_components()
        self.graph["packages"][1]["dependencies"] = []
        self.recorded("transitive")["license_expression"] = "AGPL-3.0-only"
        policy_findings = [item for item in self.findings() if item["code"] == "license_policy"]
        self.assertEqual([item["component"] for item in policy_findings], ["transitive"])

    def test_external_component_cannot_forge_an_owned_scope(self):
        self.authorize_owned_components()
        external = self.recorded("transitive")
        external.update({"license_expression": "AGPL-3.0-only", "license_policy_scope": "user_owned", "ownership_authorization": check.OWNERSHIP_AUTHORIZATION_ID})
        self.inventory["ownership_authorization"]["components"].append({"name": "transitive", "source": external["source"]})
        codes = self.codes()
        self.assertIn("unauthorized_ownership_scope", codes)
        self.assertIn("license_policy", codes)

    def test_namespace_and_other_source_exemptions_do_not_spread(self):
        self.authorize_owned_components()
        self.inventory["ownership_authorization"]["components"].append({"name": "CrispStrobe/*", "source": {"type": "git"}})
        self.assertIn("unauthorized_ownership_scope", self.codes())
        source = {**self.locks["crisp_storage"], "url": "https://github.com/CrispStrobe/another-package"}
        self.locks["crisp_storage"] = source
        self.recorded("crisp_storage")["source"] = source
        self.assertTrue(any(item["code"] == "license_policy" and item["component"] == "crisp_storage" for item in self.findings()))

    def test_owned_license_and_source_hash_checks_remain_active(self):
        self.authorize_owned_components()
        (self.root / "LICENSE").write_text("Changed published notice")
        self.assertIn("license_evidence_changed", self.codes())
        self.locks["crisp_storage"] = {**self.locks["crisp_storage"], "resolved-ref": "1" * 40}
        codes = self.codes()
        self.assertTrue({"source_changed", "unauthorized_ownership_scope", "license_policy"}.issubset(codes))

    def test_missing_ownership_instruction_does_not_create_an_exemption(self):
        self.authorize_owned_components()
        del self.inventory["ownership_authorization"]
        self.assertTrue({"unauthorized_ownership_scope", "license_policy"}.issubset(self.codes()))

    def test_owned_package_scope_does_not_exempt_native_components(self):
        self.authorize_owned_components()
        self.native["components"][0].update({"license_expression": "AGPL-3.0-only", "license_policy_scope": "user_owned", "ownership_authorization": check.OWNERSHIP_AUTHORIZATION_ID})
        self.assertIn("native_license_policy", self.codes())

    def test_lgpl_is_not_confused_with_the_gpl_text_it_incorporates(self):
        source_root = self.root / "cache/transitive"
        (source_root / "LICENSE").write_text("LGPL version 3.0. Incorporates GNU GENERAL PUBLIC LICENSE version 3.")
        entry = self.recorded("transitive")
        entry["license_expression"] = "LGPL-3.0-or-later"
        entry["license_files"][0]["sha256"] = check.digest(source_root / "LICENSE")
        self.assertEqual(self.findings(), [])

    def test_spdx_parser_rejects_gpl_and_unknown_or_malformed_grants(self):
        for expression in ("GPL-2.0-or-later", "MIT AND AGPL-3.0-only", "MIT OR GPL-3.0-only", "GPL-3.0-only WITH GCC-exception-3.1", "LicenseRef-Unknown", "MIT Apache-2.0", "MIT AND", "(MIT", ""):
            with self.subTest(expression=expression):
                self.assertIsNotNone(check.license_problem(expression))
        for expression in ("MIT", "MPL-2.0", "LGPL-2.1-or-later", "(MIT OR BSD-3-Clause) AND Apache-2.0"):
            with self.subTest(expression=expression):
                self.assertIsNone(check.license_problem(expression))

    def test_llvm_exception_is_permitted_only_with_its_reviewed_apache_grant(self):
        self.assertIsNone(check.license_problem("Apache-2.0 WITH LLVM-exception"))
        for expression in ("MIT WITH LLVM-exception", "GPL-2.0-only WITH LLVM-exception", "Apache-2.0 WITH Unknown-exception"):
            with self.subTest(expression=expression):
                self.assertIsNotNone(check.license_problem(expression))

    def add_native_source_manifest(self):
        base = self.root / "licensing/native-source"
        base.mkdir()
        (base / "source.cpp").write_text("// source under MIT\n")
        (base / "LICENSE").write_text("MIT source notice")
        manifest = {
            "schema_version": 1,
            "components": [{
                "id": "upstream", "revision": "a" * 40,
                "archive_sha256": "b" * 64, "license_expression": "MIT",
                "files": [{"path": name, "sha256": check.digest(base / name)}
                          for name in ("source.cpp", "LICENSE")],
            }],
        }
        path = base / "manifest.json"
        path.write_text(json.dumps(manifest))
        self.native["components"][0].update({
            "source_review_status": "reviewed", "license_review_status": "reviewed",
            "artifact_review_status": "reviewed",
            "source_manifest": {"path": str(path.relative_to(self.root)), "sha256": check.digest(path)},
        })
        return path, manifest

    def test_reviewed_source_and_license_do_not_approve_a_pending_native_artifact(self):
        self.add_native_source_manifest()
        self.native["components"][0].update({"review_status": "needs_review", "artifact_review_status": "pending_android_artifact_validation"})
        self.assertEqual(self.codes(), {"native_review_required"})
        report = check.audit(self.root)
        self.assertTrue(report["native_source_reviews"][0]["source_manifest_verified"])
        self.assertEqual(report["native_source_reviews"][0]["license_review_status"], "reviewed")
        # An accidental overall approval cannot hide an explicitly pending artifact.
        self.native["components"][0]["review_status"] = "reviewed"
        self.assertIn("native_artifact_review_required", self.codes())

    def test_native_manifest_checks_transitive_grants_not_only_bundle_label(self):
        path, manifest = self.add_native_source_manifest()
        self.assertEqual(self.findings(), [])
        manifest["components"][0]["license_expression"] = "AGPL-3.0-only"
        path.write_text(json.dumps(manifest))
        self.native["components"][0]["source_manifest"]["sha256"] = check.digest(path)
        self.assertIn("native_source_license_policy", self.codes())

    def test_native_manifest_detects_changed_and_unlisted_source_files(self):
        path, _ = self.add_native_source_manifest()
        self.assertEqual(self.findings(), [])
        (path.parent / "source.cpp").write_text("different native source")
        (path.parent / "unlisted.cpp").write_text("new transitive native source")
        self.assertTrue({"native_source_file_changed", "native_source_closure_changed"}.issubset(self.codes()))

    def test_source_review_without_manifest_or_with_stale_manifest_is_blocked(self):
        path, _ = self.add_native_source_manifest()
        path.write_text(path.read_text() + "\n")
        self.assertIn("invalid_native_source_manifest", self.codes())
        del self.native["components"][0]["source_manifest"]
        self.assertIn("missing_native_source_manifest", self.codes())

    def add_native_git_file_snapshot(self):
        path, manifest = self.add_native_source_manifest()
        source = manifest["components"][0]
        del source["archive_sha256"]
        source.update(source_type="git-files", git_tree_sha1="c" * 40)
        for item in source["files"]:
            data = (path.parent / item["path"]).read_bytes()
            item.update(
                upstream_path=item["path"],
                source_url=f'https://example.invalid/repo/+/{source["revision"]}/{item["path"]}',
                git_blob_sha1=hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest(),
            )
        self.write_native_source_manifest(path, manifest)
        return path, manifest

    def write_native_source_manifest(self, path, manifest):
        path.write_text(json.dumps(manifest))
        self.native["components"][0]["source_manifest"]["sha256"] = check.digest(path)

    def test_native_git_files_use_real_blob_identity_without_an_archive_claim(self):
        self.add_native_git_file_snapshot()
        self.assertEqual(self.findings(), [])

    def test_native_git_files_detect_blob_changes_even_with_new_sha256(self):
        path, manifest = self.add_native_git_file_snapshot()
        source = path.parent / "source.cpp"
        source.write_text("// locally edited, no longer the original Git object\n")
        manifest["components"][0]["files"][0]["sha256"] = check.digest(source)
        self.write_native_source_manifest(path, manifest)
        self.assertIn("native_source_git_blob_changed", self.codes())

    def test_native_git_files_require_immutable_urls_and_safe_original_paths(self):
        path, manifest = self.add_native_git_file_snapshot()
        original = copy.deepcopy(manifest)
        for changes in (
            {"source_url": "https://example.invalid/repo/+/main/source.cpp"},
            {"source_url": f'https://example.invalid/repo/+/{"a" * 40}/other.cpp'},
            {"upstream_path": "../source.cpp"},
            {"git_blob_sha1": "not-a-git-object"},
        ):
            with self.subTest(changes=changes):
                candidate = copy.deepcopy(original)
                candidate["components"][0]["files"][0].update(changes)
                self.write_native_source_manifest(path, candidate)
                self.assertIn("invalid_native_source_manifest", self.codes())

    def test_native_source_rejects_unknown_provenance_and_mixed_archive_claims(self):
        path, manifest = self.add_native_git_file_snapshot()
        original = copy.deepcopy(manifest)
        for changes in (
            {"source_type": "unverified-download"},
            {"git_tree_sha1": "main"},
            {"archive_sha256": "b" * 64},
        ):
            with self.subTest(changes=changes):
                candidate = copy.deepcopy(original)
                candidate["components"][0].update(changes)
                self.write_native_source_manifest(path, candidate)
                self.assertIn("invalid_native_source_manifest", self.codes())

    def add_reviewed_pffft_notice(self):
        component = "android-native-speed-processors"
        identifier = "LicenseRef-PFFFT-FFTPACK"
        policy = check.REVIEWED_NATIVE_LICENSE_REFS[(component, identifier)]
        repository = Path(__file__).resolve().parents[2]
        path = self.root / policy["path"]
        path.parent.mkdir(parents=True)
        path.write_bytes((repository / policy["path"]).read_bytes())
        entry = self.native["components"][0]
        entry.update({"id": component, "platforms": ["android"], "license_expression": identifier,
                      "license_refs": [{"id": identifier, "path": policy["path"], "sha256": policy["sha256"]}]})
        self.inventory["required_native_components"] = [{"id": component, "platforms": ["android"]}]
        return path

    def test_custom_permissive_notice_requires_exact_component_and_bytes(self):
        path = self.add_reviewed_pffft_notice()
        self.assertEqual(self.findings(), [])
        path.write_text("A different grant using the same identifier")
        self.assertTrue({"native_license_ref_changed", "native_license_policy"}.issubset(self.codes()))

    def test_custom_license_reference_cannot_spread_to_other_native_or_dart_components(self):
        self.add_reviewed_pffft_notice()
        self.recorded("transitive")["license_expression"] = "LicenseRef-PFFFT-FFTPACK"
        self.assertIn("license_policy", self.codes())
        self.native["components"][0]["id"] = "unrelated-native"
        self.inventory["required_native_components"][0]["id"] = "unrelated-native"
        self.assertTrue({"invalid_native_license_ref", "native_license_policy"}.issubset(self.codes()))

    def test_changed_license_bytes_block_even_when_version_is_unchanged(self):
        (self.root / "cache/transitive/LICENSE").write_text("New different grant")
        self.assertIn("license_evidence_changed", self.codes())

    def test_unknown_new_transitive_dependency_requires_review(self):
        self.add_package("new_dependency", inventoried=False)
        self.graph["packages"][1]["dependencies"].append("new_dependency")
        self.assertIn("unreviewed_package", self.codes())

    def test_archive_hash_change_and_stale_resolution_block(self):
        self.locks["dependency"] = {**self.locks["dependency"], "sha256": "1" * 64}
        self.graph["packages"][1]["version"] = "2.0.0"
        codes = self.codes()
        self.assertTrue({"source_changed", "version_changed", "stale_resolution"}.issubset(codes))

    def test_unresolved_root_dependency_change_cannot_reuse_old_graph(self):
        (self.root / "pubspec.yaml").write_text("name: app\nnew-dependency: pending\n")
        self.assertIn("root_manifest_changed", self.codes())

    def test_local_vendor_edits_need_explicit_review(self):
        source_root = self.root / "cache/dependency"
        source = {"type": "path", "path": "cache/dependency", "relative": True}
        self.locks["dependency"] = source
        entry = self.recorded("dependency")
        entry["source"] = source
        entry["source_tree_sha256"] = check.tree_digest(source_root)
        self.assertEqual(self.findings(), [])
        for generated in (
            "build/generated/output.so",
            "tools/__pycache__/helper.pyc",
            "android/.cxx/Debug/arm64-v8a/build.ninja",
            "android/.gradle/8.9/executionHistory/executionHistory.bin",
        ):
            with self.subTest(generated=generated):
                path = source_root / generated
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("generated cache content")
                self.assertEqual(check.tree_digest(source_root), entry["source_tree_sha256"])
                self.assertEqual(self.findings(), [])
        (source_root / "copied_native.c").write_text("new native dependency")
        self.assertIn("local_source_changed", self.codes())

    def test_sdk_pin_change_blocks(self):
        self.config["flutterVersion"] = "9.9.9"
        self.assertIn("sdk_changed", self.codes())

    def test_file_uris_decode_with_platform_converter_and_reject_remote_hosts(self):
        with patch.object(check, "url2pathname", return_value=str(self.root)) as convert:
            self.assertEqual(check.local_uri_path("file:///C:/reviewed%20cache"), self.root)
            convert.assert_called_once_with("/C:/reviewed%20cache")
        for uri in ("file://untrusted-server/share/package", "https://example.invalid/source", "file:///tmp/package?ref=new"):
            with self.subTest(uri=uri), self.assertRaises(ValueError):
                check.local_uri_path(uri)

    def test_native_policy_is_scoped_to_target_but_missing_review_blocks(self):
        self.native["components"].append({
            "id": "linux-only", "platforms": ["linux"], "version": "uncontrolled",
            "license_expression": "GPL-2.0-or-later", "review_status": "needs_review",
            "blockers": ["System build is not pinned"],
        })
        self.assertEqual(self.findings("ios"), [])
        codes = self.codes("linux")
        self.assertTrue({"native_license_policy", "native_review_required", "native_provenance"}.issubset(codes))

    def test_mit_wrapper_does_not_approve_missing_native_payload(self):
        self.native["components"] = []
        self.assertIn("missing_native_component", self.codes("ios"))

    def test_review_label_without_artifact_hash_is_insufficient(self):
        del self.native["components"][0]["artifact"]["sha256"]
        self.assertIn("missing_native_hash", self.codes())

    def test_native_local_evidence_is_pinned(self):
        path = self.root / "licensing/build-evidence.json"
        path.write_text('{"verified": true}')
        self.native["components"][0]["evidence"] = [{"path": "licensing/build-evidence.json", "sha256": check.digest(path)}]
        self.assertEqual(self.findings(), [])
        path.write_text('{"verified": false}')
        self.assertIn("native_evidence_changed", self.codes())

    def test_native_build_dependency_changes_require_review(self):
        path = self.root / "cache/dependency/android/build.gradle"
        path.parent.mkdir()
        path.write_text("implementation 'native:library:1.0'")
        self.inventory["native_build_inputs"] = [{
            "package": "dependency", "path": "android/build.gradle",
            "sha256": check.digest(path), "platforms": ["android"],
        }]
        self.assertEqual(self.findings(), [])
        path.write_text("implementation 'native:library:2.0'")
        self.assertIn("native_build_input_changed", self.codes("android"))
        self.assertEqual(self.findings("ios"), [])

    def test_missing_resolution_fails_closed_but_report_mode_is_nonblocking(self):
        (self.root / ".dart_tool/package_graph.json").unlink()
        output = self.root / "reports/licenses.json"
        common = ["--root", str(self.root), "--platform", "ios", "--output", str(output)]
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(check.main([*common, "--report"]), 0)
            self.assertEqual(check.main([*common, "--enforce"]), 1)
        report = json.loads(output.read_text())
        self.assertEqual(report["result"], "blocked")
        self.assertEqual(report["findings"][0]["code"], "audit_incomplete")

    def test_malformed_inventory_and_graph_are_not_silently_ignored(self):
        self.graph["packages"][1]["dependencies"].append("missing")
        self.assertIn("audit_incomplete", self.codes())
        (self.root / "licensing/dependencies.json").write_text("{bad json")
        self.assertEqual(check.audit(self.root)["result"], "blocked")


if __name__ == "__main__":
    unittest.main()
