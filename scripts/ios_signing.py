#!/usr/bin/env python3
"""Validate signing inputs and the actual exported IPA before uploading it."""
import base64
import datetime
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

CANONICAL_CERT_SHA1 = '56D3B7D782F2CEF0BBEFEEE30D98C6BA0F31C632'
BUNDLE_ID = 'com.crispstrobe.crisperplayer'
EXTENSION_ID = BUNDLE_ID + '.ShareExtension'
APP_GROUP = 'group.' + BUNDLE_ID


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def profile_data(path):
    return plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(path)]))


def validate_profile(profile, bundle_id, team):
    entitlements = profile['Entitlements']
    require(entitlements['application-identifier'] == team + '.' + bundle_id, 'Profile identity mismatch')
    require(APP_GROUP in entitlements.get('com.apple.security.application-groups', []),
            'Profile lacks the assigned App Group; finish Developer portal setup before creating profiles')
    require(not entitlements.get('get-task-allow', False), 'Development profile cannot ship to TestFlight')
    require('ProvisionedDevices' not in profile, 'An App Store profile is required')
    require(profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
            'Provisioning profile is expired')
    require(any(hashlib.sha1(cert).hexdigest().upper() == CANONICAL_CERT_SHA1
                for cert in profile['DeveloperCertificates']), 'Profile does not contain the canonical Distribution certificate')


def install():
    team = os.environ['ASC_TEAM_ID']
    temp = Path(os.environ['RUNNER_TEMP'])
    names = {}
    for secret, bundle_id, stem in [('IOS_PROFILE_APP_BASE64', BUNDLE_ID, 'host'),
                                    ('IOS_PROFILE_EXT_BASE64', EXTENSION_ID, 'extension')]:
        path = temp / (stem + '.mobileprovision')
        path.write_bytes(base64.b64decode(os.environ[secret], validate=True))
        profile = profile_data(path)
        validate_profile(profile, bundle_id, team)
        names[bundle_id] = profile['Name']
        for folder in ['Library/MobileDevice/Provisioning Profiles',
                       'Library/Developer/Xcode/UserData/Provisioning Profiles']:
            directory = Path.home() / folder
            directory.mkdir(parents=True, exist_ok=True)
            (directory / (profile['UUID'] + '.mobileprovision')).write_bytes(path.read_bytes())
        print('Installed validated App Store profile:', bundle_id, profile['UUID'])
    options = {'method': 'app-store-connect', 'teamID': team, 'signingStyle': 'manual',
        'signingCertificate': 'Apple Distribution', 'provisioningProfiles': names,
        'destination': 'export', 'manageAppVersionAndBuildNumber': False}
    (temp / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))


def expected_version():
    match = re.search(r'^version:\s*([0-9.]+)\+([0-9]+)\s*$', Path('pubspec.yaml').read_text(), re.M)
    require(match is not None, 'pubspec.yaml must specify version and a numeric build')
    return match.group(1), match.group(2)


def verify():
    ipas = list(Path('build/ios/ipa').glob('*.ipa'))
    require(len(ipas) == 1, 'Expected exactly one newly exported IPA')
    ipa = ipas[0].resolve()
    expected, number = expected_version()
    with tempfile.TemporaryDirectory(prefix='crisper-ipa-') as folder:
        subprocess.run(['ditto', '-x', '-k', str(ipa), folder], check=True)
        host = Path(folder) / 'Payload/Runner.app'
        require(host.is_dir(), 'IPA has no Runner.app')
        for bundle, identifier in [(host, BUNDLE_ID), (host / 'PlugIns/ShareExtension.appex', EXTENSION_ID)]:
            info = plistlib.loads((bundle / 'Info.plist').read_bytes())
            require(info['CFBundleIdentifier'] == identifier, 'Exported bundle identifier mismatch')
            require(info['CFBundleShortVersionString'] == expected, 'Exported marketing version mismatch')
            require(info['CFBundleVersion'] == number, 'Exported build number mismatch')
            minimum = tuple(int(part) for part in info['MinimumOSVersion'].split('.'))
            require(minimum >= (14, 0), 'Exported minimum iOS version is below 14.0')
            require(info.get('ITSAppUsesNonExemptEncryption') is False, 'Export compliance declaration is missing')
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
            entitlements = plistlib.loads(subprocess.check_output(
                ['codesign', '-d', '--entitlements', ':-', str(bundle)], stderr=subprocess.DEVNULL))
            require(APP_GROUP in entitlements.get('com.apple.security.application-groups', []),
                    'Export stripped the App Group entitlement')
            profile = profile_data(bundle / 'embedded.mobileprovision')
            validate_profile(profile, identifier, profile['TeamIdentifier'][0])
        print('Verified IPA identity, versions, minimum iOS, signatures, both profiles and App Group entitlements.')
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a') as output:
            output.write(f'IPA={ipa}\nBUNDLE_VERSION={expected}\nBUNDLE_BUILD={number}\n')


def check_app():
    from testflight_internal import api, query
    app_id = os.environ['ASC_APP_ID']
    app = api('apps/' + app_id)['data']
    require(app['attributes']['bundleId'] == BUNDLE_ID, 'ASC_APP_ID belongs to a different app')
    resolved = api(query('apps', **{'filter[bundleId]': BUNDLE_ID}))['data']
    require(len(resolved) == 1 and resolved[0]['id'] == app_id, 'App Store app identity was not confirmed')
    print('Confirmed App Store app:', app_id, BUNDLE_ID)


if __name__ == '__main__':
    {'install': install, 'verify': verify, 'check-app': check_app}[sys.argv[1]]()
