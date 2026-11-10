import importlib.util
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    "audit_desktop_audio", Path(__file__).parents[1] / "audit_desktop_audio.py"
)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


def evidence(*, license_name="LGPL version 3 or later", flags="--disable-gpl --disable-nonfree"):
    return b"\0".join(
        item.encode() for item in [
            "mpv v0.36.0-403-g652a1dd907", "-Dgpl=false -Dlibmpv=true",
            flags,
            *(f"{name} license: {license_name}" for name in sorted(audit.REQUIRED_FFMPEG_LIBRARIES)),
            "A diagnostic happens to mention memtest86 (GPLd).",
        ]
    )


class NativeAudioEvidenceTest(unittest.TestCase):
    def test_lgpl_markers_do_not_grant_release_approval(self):
        report = audit.inspect_bytes(evidence(), role="combined")
        self.assertEqual(report["marker_verdict"], "compatible_markers")
        self.assertFalse(report["release_approved"])
        self.assertEqual(report["findings"], [])

    def test_mixed_gpl_ffmpeg_build_is_rejected_despite_lgpl_mpv(self):
        report = audit.inspect_bytes(evidence(license_name="GPL version 3 or later", flags="--enable-gpl --disable-nonfree"), role="combined")
        self.assertEqual(report["marker_verdict"], "forbidden_markers")

    def test_nonfree_build_is_rejected_even_if_license_text_claims_lgpl(self):
        report = audit.inspect_bytes(evidence(flags="--disable-gpl --enable-nonfree"), role="combined")
        self.assertEqual(report["marker_verdict"], "forbidden_markers")

    def test_missing_library_evidence_is_not_a_pass(self):
        payload = evidence().replace(b"libswscale license:", b"removed_license:")
        report = audit.inspect_bytes(payload, role="combined")
        self.assertEqual(report["marker_verdict"], "insufficient_evidence")

    def test_unknown_binary_does_not_pass(self):
        self.assertEqual(audit.inspect_bytes(b"not the expected native library", role="combined")["marker_verdict"], "insufficient_evidence")

    def test_changed_binary_fails_even_with_compatible_markers(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "libmpv-2.dll"
            path.write_bytes(evidence())
            old_digest = audit.sha256(path)
            path.write_bytes(evidence() + b"modified")
            report = audit.inspect(path, role="combined", expected_sha256=old_digest)
            self.assertEqual(report["marker_verdict"], "artifact_mismatch")


if __name__ == "__main__":
    unittest.main()
