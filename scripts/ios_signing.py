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
WIDGET_ID = BUNDLE_ID + '.PlayerWidget'
WATCH_ID = BUNDLE_ID + '.watchkitapp'


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def profile_data(path):
    return plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(path)]))


def validate_profile(profile, bundle_id, team):
    entitlements = profile['Entitlements']
    require(entitlements['application-identifier'] == team + '.' + bundle_id, 'Profile identity mismatch')
    if bundle_id != WATCH_ID:
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
    specs = [('IOS_PROFILE_APP_BASE64', BUNDLE_ID, 'host'),
             ('IOS_PROFILE_EXT_BASE64', EXTENSION_ID, 'extension')]
    flags = []
    for secret, bundle_id, stem, flag in [
        ('IOS_PROFILE_WIDGET_BASE64', WIDGET_ID, 'widget', '--widget'),
        ('IOS_PROFILE_WATCH_BASE64', WATCH_ID, 'watch', '--watch')]:
        if os.environ.get(secret):
            specs.append((secret, bundle_id, stem))
            flags.append(flag)
    for secret, bundle_id, stem in specs:
        path = temp / (stem + '.mobileprovision')
        path.write_bytes(base64.b64decode(os.environ[secret], validate=True))
        profile = profile_data(path)
        validate_profile(profile, bundle_id, team)
        names[bundle_id] = profile['Name']
        if bundle_id == BUNDLE_ID and profile['Entitlements'].get('com.apple.developer.carplay-audio') is True:
            path_entitlements = Path('ios/Runner/Runner.entitlements')
            entitlements = plistlib.loads(path_entitlements.read_bytes())
            entitlements['com.apple.developer.carplay-audio'] = True
            path_entitlements.write_bytes(plistlib.dumps(entitlements))
            info_path = Path('ios/Runner/Info.plist')
            info = plistlib.loads(info_path.read_bytes())
            info['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes'] = True
            info_path.write_bytes(plistlib.dumps(info))
        for folder in ['Library/MobileDevice/Provisioning Profiles',
                       'Library/Developer/Xcode/UserData/Provisioning Profiles']:
            directory = Path.home() / folder
            directory.mkdir(parents=True, exist_ok=True)
            (directory / (profile['UUID'] + '.mobileprovision')).write_bytes(path.read_bytes())
        print('Installed validated App Store profile:', bundle_id, profile['UUID'])
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a') as output:
            output.write('APPLE_COMPANION_FLAGS=' + ' '.join(flags) + '\n')
    options = {'method': 'app-store-connect', 'teamID': team, 'signingStyle': 'manual',
        'signingCertificate': 'Apple Distribution', 'provisioningProfiles': names,
        'destination': 'export', 'manageAppVersionAndBuildNumber': False}
    (temp / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))


def expected_version():
    match = re.search(r'^version:\s*([0-9.]+)\+([0-9]+)\s*$', Path('pubspec.yaml').read_text(), re.M)
    require(match is not None, 'pubspec.yaml must specify version and a numeric build')
    return match.group(1), match.group(2)


def group_entitlements(current, authorized):
    require(current.get('application-identifier') == authorized['application-identifier'],
            'Signed bundle identity does not match its profile')
    require(not current.get('get-task-allow', False), 'Cannot re-sign a development bundle for TestFlight')
    allowed = authorized.get('com.apple.security.application-groups', [])
    require(APP_GROUP in allowed, 'Profile does not authorize the required App Group')
    groups = list(current.get('com.apple.security.application-groups', []))
    require(set(groups).issubset(allowed), 'Signed bundle has an unauthorized App Group')
    if APP_GROUP not in groups:
        groups.append(APP_GROUP)
    return {**current, 'com.apple.security.application-groups': groups}


def restore_groups():
    """Unsigned archives lose custom entitlements at export; restore them using
    the already-installed canonical identity, nested extension before host.
    See ../appstore.md, 'profile carrying the app group is NOT enough'.
    """
    ipas = list(Path('build/ios/ipa').glob('*.ipa'))
    require(len(ipas) == 1, 'Expected exactly one newly exported IPA')
    ipa = ipas[0].resolve()
    with tempfile.TemporaryDirectory(prefix='crisper-sign-') as folder:
        root = Path(folder) / 'contents'
        subprocess.run(['ditto', '-x', '-k', str(ipa), str(root)], check=True)
        host = root / 'Payload/Runner.app'
        grouped = [(host / 'PlugIns/ShareExtension.appex', EXTENSION_ID)]
        if (host / 'PlugIns/PlayerWidget.appex').exists():
            grouped.append((host / 'PlugIns/PlayerWidget.appex', WIDGET_ID))
        grouped.append((host, BUNDLE_ID))
        for bundle, identifier in grouped:
            profile = profile_data(bundle / 'embedded.mobileprovision')
            validate_profile(profile, identifier, profile['TeamIdentifier'][0])
            current = plistlib.loads(subprocess.check_output(
                ['codesign', '-d', '--entitlements', ':-', str(bundle)], stderr=subprocess.DEVNULL))
            entitlements = group_entitlements(current, profile['Entitlements'])
            if identifier == BUNDLE_ID and profile['Entitlements'].get('com.apple.developer.carplay-audio') is True:
                entitlements['com.apple.developer.carplay-audio'] = True
            path = Path(folder) / (bundle.name + '.entitlements')
            path.write_bytes(plistlib.dumps(entitlements))
            subprocess.run(['codesign', '--force', '--sign', CANONICAL_CERT_SHA1,
                '--preserve-metadata=identifier,requirements,flags', '--generate-entitlement-der',
                '--entitlements', str(path), str(bundle)], check=True)
        updated = Path(folder) / 'signed.ipa'
        subprocess.run(['ditto', '-c', '-k', '--norsrc', str(root), str(updated)], check=True)
        # The unpacking directory may be on a different filesystem from build/.
        import shutil
        shutil.copyfile(updated, ipa)
    print('Restored authorized App Group entitlements in extension and host with the canonical identity.')


def validate_app_configuration(info):
    minimum = tuple(int(part) for part in info['MinimumOSVersion'].split('.'))
    require(minimum >= (15, 0), 'Exported minimum iOS version is below 15.0')
    if info.get('CFBundleDocumentTypes'):
        require(info.get('UISupportsDocumentBrowser') is True or
                isinstance(info.get('LSSupportsOpeningDocumentsInPlace'), bool),
                'Document types require an explicit document-opening configuration')


def verify():
    ipas = list(Path('build/ios/ipa').glob('*.ipa'))
    require(len(ipas) == 1, 'Expected exactly one newly exported IPA')
    ipa = ipas[0].resolve()
    expected, number = expected_version()
    with tempfile.TemporaryDirectory(prefix='crisper-ipa-') as folder:
        subprocess.run(['ditto', '-x', '-k', str(ipa), folder], check=True)
        host = Path(folder) / 'Payload/Runner.app'
        require(host.is_dir(), 'IPA has no Runner.app')
        bundles = [(host, BUNDLE_ID), (host / 'PlugIns/ShareExtension.appex', EXTENSION_ID)]
        for relative, identifier, secret in [
            ('PlugIns/PlayerWidget.appex', WIDGET_ID, 'IOS_PROFILE_WIDGET_BASE64'),
            ('Watch/PlayerWatch.app', WATCH_ID, 'IOS_PROFILE_WATCH_BASE64')]:
            candidate = host / relative
            flag = '--widget' if identifier == WIDGET_ID else '--watch'
            if os.environ.get(secret) or flag in os.environ.get('APPLE_COMPANION_FLAGS', '').split():
                require(candidate.is_dir(), 'Configured companion missing from exported IPA: ' + identifier)
            if candidate.exists():
                bundles.append((candidate, identifier))
        for bundle, identifier in bundles:
            info = plistlib.loads((bundle / 'Info.plist').read_bytes())
            require(info['CFBundleIdentifier'] == identifier, 'Exported bundle identifier mismatch')
            require(info['CFBundleShortVersionString'] == expected, 'Exported marketing version mismatch')
            require(info['CFBundleVersion'] == number, 'Exported build number mismatch')
            if identifier == WATCH_ID:
                require(info.get('WKCompanionAppBundleIdentifier') == BUNDLE_ID, 'Watch companion points at another app')
                require(float('.'.join(info['MinimumOSVersion'].split('.')[:2])) >= 10, 'Watch deployment target too low')
            else:
                validate_app_configuration(info)
            require(info.get('ITSAppUsesNonExemptEncryption') is False, 'Export compliance declaration is missing')
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
            entitlements = plistlib.loads(subprocess.check_output(
                ['codesign', '-d', '--entitlements', ':-', str(bundle)], stderr=subprocess.DEVNULL))
            if identifier != WATCH_ID:
                require(APP_GROUP in entitlements.get('com.apple.security.application-groups', []),
                        'Export stripped the App Group entitlement')
            profile = profile_data(bundle / 'embedded.mobileprovision')
            validate_profile(profile, identifier, profile['TeamIdentifier'][0])
            if identifier == BUNDLE_ID and profile['Entitlements'].get('com.apple.developer.carplay-audio') is True:
                require(entitlements.get('com.apple.developer.carplay-audio') is True,
                        'Export stripped the authorized CarPlay audio entitlement')
                require(info.get('UIApplicationSceneManifest', {}).get('UIApplicationSupportsMultipleScenes') is True,
                        'CarPlay requires simultaneous phone/car scenes')
        print('Verified IPA identity, versions, deployment targets, signatures, profiles and required entitlements.')
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
    {'install': install, 'restore-groups': restore_groups, 'verify': verify, 'check-app': check_app}[sys.argv[1]]()
