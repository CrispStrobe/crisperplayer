# SPDX-License-Identifier: MIT
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "audit_native_audio", Path(__file__).parents[1] / "audit_native_audio.py"
)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


class NativeAudioAuditTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.bundle = self.root / "bundle"
        self.bundle.mkdir()

    def put(self, name, data=b"test bytes"):
        path = self.bundle / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def glint_manifest(self):
        manifest = {"commit": "a" * 40, "selected_files": [],
                    "patch_file": "UPSTREAM.patch", "provenance_files": []}
        for name in ("LICENSE", "src/mp3_decoder.cpp", "src/aac_decoder.cpp",
                     "src/aac_tables.hpp", "tools/gen_aac_tables.py"):
            source = self.put(name, name.encode())
            manifest["selected_files"].append({"path": name, "vendored_sha256": audit.sha256(source)})
        manifest["patch_sha256"] = audit.sha256(self.put("UPSTREAM.patch"))
        self.put("UPSTREAM.md")
        self.put("UPSTREAM.json", json.dumps(manifest).encode())
        return manifest

    def provenance(self, name, kind="source_input"):
        entry = {"path": name, "sha256": audit.sha256(self.put(name)),
                 "kind": kind, "license": "Apache-2.0"}
        if kind in ("source_input", "license", "notice"):
            entry["source_url"] = "https://example.com/repo/" + "a" * 40 + "/" + name
        return entry

    def test_linux_and_windows_exact_bundle_paths(self):
        linux = self.put("lib/libcrisper_audio.so")
        found, report = audit.discover_bundle(self.bundle, "linux")
        self.assertEqual(found, linux.resolve())
        self.assertEqual(report["native_library"], "lib/libcrisper_audio.so")
        linux.unlink()
        windows = self.put("crisper_audio.dll")
        self.assertEqual(audit.discover_bundle(self.bundle, "win32")[0], windows.resolve())

    def test_missing_packaged_library_never_falls_back_to_system(self):
        external = self.root / audit.expected_name(sys.platform)
        external.write_bytes(b"some other installed library")
        with patch.object(audit, "run_probe") as probe, patch.dict(
            "os.environ", {"CRISPER_AUDIO_LIBRARY_PATH": str(external)}
        ):
            report = audit.audit(bundle=self.bundle)
        self.assertEqual(report["status"], "failed")
        self.assertIn("exactly one", report["findings"][0])
        probe.assert_not_called()

    def test_wrong_location_or_platform_does_not_pass(self):
        self.put("libcrisper_audio.so")
        with self.assertRaisesRegex(audit.AuditError, "Expected bundled library"):
            audit.discover_bundle(self.bundle, "linux")
        with self.assertRaisesRegex(audit.AuditError, "Expected bundled library"):
            audit.discover_bundle(self.bundle, "win32")

    def test_duplicate_native_libraries_fail(self):
        self.put("lib/libcrisper_audio.so")
        self.put("old/libcrisper_audio.so")
        with self.assertRaisesRegex(audit.AuditError, "exactly one"):
            audit.discover_bundle(self.bundle, "linux")

    def test_forbidden_payload_families_and_case_are_rejected(self):
        self.put("lib/libcrisper_audio.so")
        for name in (
            "libmpv.so.2", "libmpv-2.dll", "AVCODEC-61.DLL", "libavformat.so.61",
            "libavfilter.so", "libavutil.59.dylib", "libswresample.so.5",
            "swscale-8.dll", "libpostproc.a", "ffmpeg.exe", "ffprobe", "ffplay",
        ):
            with self.subTest(name=name):
                path = self.put("lib/" + name)
                with self.assertRaisesRegex(audit.AuditError, "Forbidden bundled audio payload"):
                    audit.discover_bundle(self.bundle, "linux")
                path.unlink()

    def test_license_notes_are_not_misidentified_as_linked_payload(self):
        self.put("lib/libcrisper_audio.so")
        self.put("data/flutter_assets/licenses/FFMPEG-LICENSE.txt")
        _, report = audit.discover_bundle(self.bundle, "linux")
        self.assertEqual(report["forbidden_payloads"], [])

    def test_library_symlink_cannot_escape_the_bundle(self):
        target = self.root / "outside.so"
        target.write_bytes(b"external")
        link = self.bundle / "lib/libcrisper_audio.so"
        link.parent.mkdir()
        try:
            link.symlink_to(target)
        except OSError as error:
            self.skipTest(f"This test environment cannot create symlinks: {error}")
        with self.assertRaisesRegex(audit.AuditError, "escapes the bundle"):
            audit.discover_bundle(self.bundle, "linux")

    def test_binary_hash_mismatch_fails_before_runtime_probe(self):
        library = self.put(audit.expected_name(sys.platform))
        expected = audit.sha256(library)
        library.write_bytes(b"changed artifact")
        with patch.object(audit, "run_probe") as probe:
            report = audit.audit(library=library, expected_sha256=expected)
        self.assertEqual(report["status"], "failed")
        self.assertIn("expected SHA-256", report["findings"][0])
        probe.assert_not_called()

    def test_source_hash_mismatch_and_path_escape_fail(self):
        source = self.put("source.c", b"source")
        digest = audit.sha256(source)
        self.assertEqual(audit.checked_file(self.bundle, "source.c", digest), source)
        source.write_bytes(b"mutated source")
        with self.assertRaisesRegex(audit.AuditError, "Source hash mismatch"):
            audit.checked_file(self.bundle, "source.c", digest)
        for name in ("../outside", "/absolute", "nested/../file", "nested//file"):
            with self.subTest(name=name), self.assertRaises(audit.AuditError):
                audit.checked_file(self.bundle, name, digest)

    def test_provenance_sources_and_local_evidence_are_hash_verified(self):
        manifest = self.glint_manifest()
        manifest["provenance_files"] = [
            self.provenance("provenance/input.c"),
            self.provenance("provenance/COPYING", "license"),
            self.provenance("provenance/NOTICE", "notice"),
            self.provenance("provenance/evidence.json", "evidence"),
            self.provenance("provenance/README.md", "documentation"),
        ]
        selected, provenance = audit.verify_glint_sources(self.bundle, manifest)
        self.assertEqual(len(selected), 5)
        self.assertEqual(len(provenance), 5)
        for entry in manifest["provenance_files"]:
            with self.subTest(path=entry["path"]):
                source = self.bundle / entry["path"]
                original = source.read_bytes()
                source.write_bytes(b"changed provenance")
                with self.assertRaisesRegex(audit.AuditError, "Source hash mismatch"):
                    audit.verify_glint_sources(self.bundle, manifest)
                source.write_bytes(original)

    def test_provenance_closure_rejects_unlisted_or_duplicate_files(self):
        manifest = self.glint_manifest()
        entry = self.provenance("provenance/input.c")
        with self.assertRaisesRegex(audit.AuditError, "Unlisted or missing"):
            audit.verify_glint_sources(self.bundle, manifest)
        manifest["provenance_files"] = [entry, entry]
        with self.assertRaisesRegex(audit.AuditError, "Duplicate Glint provenance"):
            audit.verify_glint_sources(self.bundle, manifest)
        manifest["provenance_files"] = [entry]
        manifest["selected_files"].append({"path": entry["path"], "vendored_sha256": entry["sha256"]})
        with self.assertRaisesRegex(audit.AuditError, "Duplicate Glint provenance"):
            audit.verify_glint_sources(self.bundle, manifest)

    def test_external_provenance_requires_license_and_immutable_source(self):
        manifest = self.glint_manifest()
        entry = self.provenance("provenance/input.c")
        manifest["provenance_files"] = [entry]
        for field, value, message in (
            ("source_url", "https://example.com/repo/main/input.c", "immutable"),
            ("license", "", "license"),
            ("kind", "unreviewed", "Unknown"),
        ):
            with self.subTest(field=field):
                original = entry[field]
                entry[field] = value
                with self.assertRaisesRegex(audit.AuditError, message):
                    audit.verify_glint_sources(self.bundle, manifest)
                entry[field] = original

    def test_offline_regeneration_failure_or_unapproved_command_cannot_pass(self):
        manifest = self.glint_manifest()
        manifest["provenance_files"] = [self.provenance("provenance/input.c")]
        manifest["regeneration"] = {
            "output": "src/aac_tables.hpp",
            "command": ["python3", "tools/gen_aac_tables.py", "--check"],
            "requires_network": False,
            "inputs": ["provenance/input.c"],
        }
        audit.verify_glint_sources(self.bundle, manifest)
        failed = subprocess.CompletedProcess([], 1, stdout="", stderr="generated header differs")
        with patch.object(audit.subprocess, "run", return_value=failed) as run:
            with self.assertRaisesRegex(audit.AuditError, "generated header differs"):
                audit.verify_glint_regeneration(self.bundle, manifest)
        self.assertEqual(run.call_args.kwargs["cwd"], self.bundle)
        self.assertEqual(run.call_args.args[0],
                         [sys.executable, "-B", "tools/gen_aac_tables.py", "--check"])
        for field, value in (("requires_network", True), ("command", ["python3", "other.py"])):
            original = manifest["regeneration"][field]
            manifest["regeneration"][field] = value
            with patch.object(audit.subprocess, "run") as run:
                with self.assertRaisesRegex(audit.AuditError, "regeneration contract"):
                    audit.verify_glint_regeneration(self.bundle, manifest)
                run.assert_not_called()
            manifest["regeneration"][field] = original
        manifest["regeneration"]["inputs"] = ["unlisted/input.c"]
        with patch.object(audit.subprocess, "run") as run:
            with self.assertRaisesRegex(audit.AuditError, "inputs do not match verified"):
                audit.verify_glint_regeneration(self.bundle, manifest)
            run.assert_not_called()

    def test_old_source_manifest_needs_no_generator_execution(self):
        manifest = self.glint_manifest()
        with patch.object(audit.subprocess, "run") as run:
            self.assertIsNone(audit.verify_glint_regeneration(self.bundle, manifest))
            run.assert_not_called()

    def test_native_crash_or_missing_success_cannot_pass(self):
        for result in (
            subprocess.CompletedProcess([], -11, stdout="", stderr="native crash"),
            subprocess.CompletedProcess([], 1, stdout="", stderr="missing exported symbol"),
            subprocess.CompletedProcess([], 0, stdout="{}", stderr=""),
        ):
            with self.subTest(code=result.returncode), patch.object(
                audit.subprocess, "run", return_value=result
            ), self.assertRaises(audit.AuditError):
                audit.run_probe(self.root / "libcrisper_audio.so")

    def test_negative_native_eof_status_is_an_error_not_completion(self):
        self.assertFalse(audit.checked_ended(0, "sonic"))
        self.assertTrue(audit.checked_ended(1, "sonic"))
        for state in (-1, -2, 2):
            with self.subTest(state=state), self.assertRaisesRegex(
                audit.AuditError, "invalid drain state"
            ):
                audit.checked_ended(state, "sonic")

    def test_runtime_failure_preserves_failed_audit(self):
        library = self.put(audit.expected_name(sys.platform))
        with patch.object(audit, "verify_source_manifests", return_value={"verified": True, "glint": {"flac_required": False}}), \
             patch.object(audit, "run_probe", side_effect=audit.AuditError("DSP bypassed speed")):
            report = audit.audit(library=library)
        self.assertEqual(report["status"], "failed")
        self.assertFalse(report["release_approved"])
        self.assertIn("DSP bypassed speed", report["findings"])

    def test_flac_source_requirement_cannot_be_silently_skipped(self):
        result = subprocess.CompletedProcess(
            [], 0, stdout='{"passed": true, "glint_decoders": ["mp3", "aac-lc"]}', stderr=""
        )
        with patch.object(audit.subprocess, "run", return_value=result) as run:
            with self.assertRaisesRegex(audit.AuditError, "requires FLAC"):
                audit.run_probe(self.root / "libcrisper_audio.so", require_flac=True)
        self.assertIn("--require-flac", run.call_args.args[0])

    def test_runtime_success_is_not_blanket_license_clearance(self):
        library = self.put(audit.expected_name(sys.platform))
        with patch.object(audit, "verify_source_manifests", return_value={"verified": True, "glint": {"flac_required": False}}), \
             patch.object(audit, "run_probe", return_value={"passed": True}):
            report = audit.audit(library=library)
        self.assertEqual(report["status"], "passed")
        self.assertFalse(report["release_approved"])
        self.assertTrue(any("statically linked" in line for line in report["limitations"]))


if __name__ == "__main__":
    unittest.main()
