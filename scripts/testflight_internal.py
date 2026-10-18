#!/usr/bin/env python3
"""Wait for the exact iOS build, populate beta metadata and verify group delivery."""
import argparse
import base64
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils


def token():
    key = serialization.load_pem_private_key(
        base64.b64decode(os.environ['ASC_API_KEY_P8_BASE64']), password=None)
    now = int(time.time())
    def b64(data):
        return base64.urlsafe_b64encode(data).rstrip(b'=').decode()
    header = b64(json.dumps({'alg': 'ES256', 'kid': os.environ['ASC_KEY_ID'], 'typ': 'JWT'}).encode())
    claims = b64(json.dumps({'iss': os.environ['ASC_ISSUER_ID'], 'iat': now,
                            'exp': now + 900, 'aud': 'appstoreconnect-v1'}).encode())
    message = header + '.' + claims
    r, s = utils.decode_dss_signature(key.sign(message.encode(), ec.ECDSA(hashes.SHA256())))
    return message + '.' + b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))


def api(path, method='GET', payload=None):
    request = urllib.request.Request('https://api.appstoreconnect.apple.com/v1/' + path,
        data=None if payload is None else json.dumps(payload).encode(), method=method,
        headers={'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raise RuntimeError(f'ASC {method} {path}: {error.code} {error.read().decode()}') from error


def all_rows(path):
    rows = []
    while path:
        result = api(path)
        rows.extend(result['data'])
        next_url = result.get('links', {}).get('next')
        path = next_url.split('/v1/', 1)[1] if next_url else None
    return rows


def query(resource, **params):
    return resource + '?' + urllib.parse.urlencode(params)


def find_build(app_id, version, number):
    result = api(query('builds', **{'filter[app]': app_id, 'filter[version]': number,
                                   'include': 'preReleaseVersion', 'limit': 200}))
    versions = {row['id']: row for row in result.get('included', []) if row['type'] == 'preReleaseVersions'}
    for build in result['data']:
        relationship = build['relationships']['preReleaseVersion']['data']
        release = versions.get(relationship['id']) or api('preReleaseVersions/' + relationship['id'])['data']
        if release['attributes']['platform'] == 'IOS' and release['attributes']['version'] == version:
            return build
    return None


def distribute(app_id, build, locale, notes, tester_email=None):
    build_id = build['id']
    if build['attributes'].get('usesNonExemptEncryption') is not False:
        api('builds/' + build_id, 'PATCH', {'data': {'type': 'builds', 'id': build_id,
            'attributes': {'usesNonExemptEncryption': False}}})
    localizations = all_rows(f'apps/{app_id}/betaAppLocalizations?limit=200')
    attributes = {'description': 'CrisperPlayer is an offline audiobook player with local imports, '
        'resume positions, chapters, bookmarks and background playback.',
        'feedbackEmail': 'cstr+apple@mailbox.org'}
    existing = next((row for row in localizations if row['attributes']['locale'] == locale), None)
    if existing:
        api('betaAppLocalizations/' + existing['id'], 'PATCH', {'data': {
            'type': 'betaAppLocalizations', 'id': existing['id'], 'attributes': attributes}})
    else:
        api('betaAppLocalizations', 'POST', {'data': {'type': 'betaAppLocalizations',
            'attributes': dict(attributes, locale=locale),
            'relationships': {'app': {'data': {'type': 'apps', 'id': app_id}}}}})
    existing_notes = all_rows(f'builds/{build_id}/betaBuildLocalizations?limit=200')
    existing = next((row for row in existing_notes if row['attributes']['locale'] == locale), None)
    if existing:
        api('betaBuildLocalizations/' + existing['id'], 'PATCH', {'data': {
            'type': 'betaBuildLocalizations', 'id': existing['id'], 'attributes': {'whatsNew': notes}}})
    else:
        api('betaBuildLocalizations', 'POST', {'data': {'type': 'betaBuildLocalizations',
            'attributes': {'locale': locale, 'whatsNew': notes},
            'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}})
    groups = all_rows(f'apps/{app_id}/betaGroups?limit=200')
    groups = [row for row in groups if row['attributes']['isInternalGroup']]
    if not groups:
        groups = [api('betaGroups', 'POST', {'data': {'type': 'betaGroups',
            'attributes': {'name': 'Internal Testers', 'isInternalGroup': True,
                           'hasAccessToAllBuilds': True},
            'relationships': {'app': {'data': {'type': 'apps', 'id': app_id}}}}})['data']]
    for group in groups:
        group_id = group['id']
        assigned = all_rows(f'betaGroups/{group_id}/builds?limit=200')
        if not any(row['id'] == build_id for row in assigned):
            api(f'betaGroups/{group_id}/relationships/builds', 'POST',
                {'data': [{'type': 'builds', 'id': build_id}]})
        assigned = all_rows(f'betaGroups/{group_id}/builds?limit=200')
        if not any(row['id'] == build_id for row in assigned):
            raise RuntimeError('Internal group assignment was not confirmed')
        testers = all_rows(f'betaGroups/{group_id}/betaTesters?limit=200')
        if tester_email and not any(t['attributes']['email'].lower() == tester_email.lower() for t in testers):
            # Only an existing ASC team member may be enrolled in an internal group.
            users = all_rows('users?limit=200')
            user = next((u for u in users if u['attributes']['username'].lower() == tester_email.lower()), None)
            if user is None:
                raise RuntimeError('Requested internal tester is not an App Store Connect team member')
            matches = all_rows(query('betaTesters', **{'filter[email]': tester_email, 'limit': 200}))
            if matches:
                api(f'betaGroups/{group_id}/relationships/betaTesters', 'POST',
                    {'data': [{'type': 'betaTesters', 'id': matches[0]['id']}]})
            else:
                api('betaTesters', 'POST', {'data': {'type': 'betaTesters',
                    'attributes': {'email': tester_email, 'firstName': user['attributes']['firstName'],
                                   'lastName': user['attributes']['lastName']},
                    'relationships': {'betaGroups': {'data': [{'type': 'betaGroups', 'id': group_id}]}}}})
            testers = all_rows(f'betaGroups/{group_id}/betaTesters?limit=200')
        if not testers:
            raise RuntimeError('Internal group has no testers; configure an ASC team member before distribution')
        print(f"Internal group {group['attributes']['name']}: build assigned, {len(testers)} testers")
    for attempt in range(20):
        detail = api(f'builds/{build_id}/buildBetaDetail')['data']
        state = detail['attributes']['internalBuildState']
        print('Internal TestFlight state:', state, flush=True)
        if state == 'IN_BETA_TESTING':
            break
        time.sleep(15)
    else:
        raise RuntimeError('Build is assigned but not yet IN_BETA_TESTING: ' + state)
    summary = f"iOS {build['attributes']['version']} ({build_id}) is VALID and IN_BETA_TESTING.\n"
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as output:
            output.write(summary)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app-id', required=True)
    parser.add_argument('--bundle-id', default='com.crispstrobe.crisperplayer')
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--notes', required=True, type=Path)
    parser.add_argument('--wait-minutes', type=int, default=40)
    parser.add_argument('--tester-email', default=os.environ.get('ASC_INTERNAL_TESTER_EMAIL'))
    args = parser.parse_args()
    app = api('apps/' + args.app_id)['data']
    if app['attributes']['bundleId'] != args.bundle_id:
        raise RuntimeError('ASC_APP_ID does not match the binary bundle identifier')
    deadline = time.monotonic() + args.wait_minutes * 60
    while time.monotonic() < deadline:
        build = find_build(args.app_id, args.version, args.build)
        state = build['attributes']['processingState'] if build else 'NOT_VISIBLE'
        print(f'iOS {args.version} ({args.build}): {state}', flush=True)
        if state == 'VALID':
            distribute(args.app_id, build, app['attributes']['primaryLocale'], args.notes.read_text()[:4000], args.tester_email)
            return
        if state in ('FAILED', 'INVALID'):
            raise RuntimeError('Apple rejected build processing: ' + state)
        time.sleep(30)
    raise TimeoutError('Apple processing is still pending; rerun distribution for this exact build')


if __name__ == '__main__':
    main()
