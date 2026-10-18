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

    def test_internal_enrollment_is_scoped_to_group_instead_of_global_email_match(self):
        user = {'attributes': {'username': 'member@example.com', 'firstName': 'Test', 'lastName': 'Member'}}
        tester = {'id': 'correct-app-tester'}
        with patch.object(testflight_internal, 'all_rows', side_effect=[[user], [tester]]) as rows, \
                patch.object(testflight_internal, 'api', return_value={}) as api:
            result = testflight_internal.enroll_internal_tester('this-app-group', 'member@example.com')
        self.assertEqual(result, [tester])
        self.assertEqual(rows.call_args_list[0].args[0], 'users?limit=200')
        self.assertEqual(rows.call_args_list[1].args[0], 'betaGroups/this-app-group/betaTesters?limit=200')
        self.assertEqual(api.call_args.args[:2], ('betaTesters', 'POST'))
        self.assertEqual(api.call_args.args[2]['data']['relationships']['betaGroups']['data'],
                         [{'type': 'betaGroups', 'id': 'this-app-group'}])

    def test_internal_enrollment_rejects_email_outside_asc_team(self):
        with patch.object(testflight_internal, 'all_rows', return_value=[]), \
                patch.object(testflight_internal, 'api') as api:
            with self.assertRaisesRegex(RuntimeError, 'team member'):
                testflight_internal.enroll_internal_tester('group', 'outsider@example.com')
        api.assert_not_called()

    def test_release_rejects_deployment_target_below_ios_15(self):
        with self.assertRaisesRegex(RuntimeError, 'below 15.0'):
            ios_signing.validate_app_configuration({'MinimumOSVersion': '14.0'})
        ios_signing.validate_app_configuration({'MinimumOSVersion': '15.0'})

    def test_document_import_configuration_must_be_explicit_and_boolean(self):
        info = {'MinimumOSVersion': '15.0', 'CFBundleDocumentTypes': [{'CFBundleTypeName': 'Audiobook'}]}
        with self.assertRaisesRegex(RuntimeError, 'document-opening'):
            ios_signing.validate_app_configuration(info)
        with self.assertRaisesRegex(RuntimeError, 'document-opening'):
            ios_signing.validate_app_configuration(dict(info, LSSupportsOpeningDocumentsInPlace='NO'))
        ios_signing.validate_app_configuration(dict(info, LSSupportsOpeningDocumentsInPlace=False))
        ios_signing.validate_app_configuration(dict(info, LSSupportsOpeningDocumentsInPlace=True))
        ios_signing.validate_app_configuration(dict(info, UISupportsDocumentBrowser=True))

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
