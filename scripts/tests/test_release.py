import datetime
import hashlib
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ios_signing
import testflight_internal


class ReleaseTests(unittest.TestCase):
    def test_restore_group_preserves_exported_identity_and_other_entitlements(self):
        current = {'application-identifier': 'TEAM.' + ios_signing.BUNDLE_ID,
                   'beta-reports-active': True, 'keychain-access-groups': ['TEAM.shared']}
        authorized = {**current, 'com.apple.security.application-groups': [ios_signing.APP_GROUP]}
        restored = ios_signing.group_entitlements(current, authorized)
        self.assertEqual(restored['com.apple.security.application-groups'], [ios_signing.APP_GROUP])
        self.assertTrue(restored['beta-reports-active'])
        self.assertEqual(restored['keychain-access-groups'], ['TEAM.shared'])
        self.assertNotIn('com.apple.security.application-groups', current)

    def test_restore_group_rejects_profile_that_does_not_authorize_it(self):
        current = {'application-identifier': 'TEAM.app'}
        with self.assertRaisesRegex(RuntimeError, 'authorize'):
            ios_signing.group_entitlements(current, current)

    def test_selects_exact_ios_release_instead_of_same_number_macos_build(self):
        builds = [{'id': name, 'relationships': {'preReleaseVersion': {'data': {'id': name}}}}
                  for name in ['mac', 'old-ios', 'wanted-ios']]
        releases = [{'id': name, 'type': 'preReleaseVersions', 'attributes': attrs} for name, attrs in [
            ('mac', {'platform': 'MAC_OS', 'version': '0.1.0'}),
            ('old-ios', {'platform': 'IOS', 'version': '0.0.9'}),
            ('wanted-ios', {'platform': 'IOS', 'version': '0.1.0'})]]
        with patch.object(testflight_internal, 'api', return_value={'data': builds, 'included': releases}):
            selected = testflight_internal.find_build('app-id', '0.1.0', '2')
        self.assertEqual(selected['id'], 'wanted-ios')

    def test_does_not_accept_another_marketing_version(self):
        response = {'data': [{'id': 'old', 'relationships': {'preReleaseVersion': {'data': {'id': 'old'}}}}],
            'included': [{'id': 'old', 'type': 'preReleaseVersions',
                          'attributes': {'platform': 'IOS', 'version': '0.0.9'}}]}
        with patch.object(testflight_internal, 'api', return_value=response):
            self.assertIsNone(testflight_internal.find_build('app-id', '0.1.0', '2'))

    def valid_profile(self):
        return {'Entitlements': {'application-identifier': 'TEAM.' + ios_signing.BUNDLE_ID,
            'com.apple.security.application-groups': [ios_signing.APP_GROUP], 'get-task-allow': False},
            'ExpirationDate': datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) + datetime.timedelta(days=1),
            'DeveloperCertificates': [b'certificate']}

    def test_rejects_profile_without_the_browser_assigned_app_group(self):
        profile = self.valid_profile()
        profile['Entitlements']['com.apple.security.application-groups'] = []
        with self.assertRaisesRegex(RuntimeError, 'assigned App Group'):
            ios_signing.validate_profile(profile, ios_signing.BUNDLE_ID, 'TEAM')

    def test_rejects_profile_for_the_other_bundle(self):
        with self.assertRaisesRegex(RuntimeError, 'identity mismatch'):
            ios_signing.validate_profile(self.valid_profile(), ios_signing.EXTENSION_ID, 'TEAM')

    def test_rejects_noncanonical_certificate(self):
        with self.assertRaisesRegex(RuntimeError, 'canonical Distribution certificate'):
            ios_signing.validate_profile(self.valid_profile(), ios_signing.BUNDLE_ID, 'TEAM')

    def test_accepts_store_profile_with_matching_identity_group_and_certificate(self):
        fingerprint = hashlib.sha1(b'certificate').hexdigest().upper()
        with patch.object(ios_signing, 'CANONICAL_CERT_SHA1', fingerprint):
            ios_signing.validate_profile(self.valid_profile(), ios_signing.BUNDLE_ID, 'TEAM')


if __name__ == '__main__':
    unittest.main()
