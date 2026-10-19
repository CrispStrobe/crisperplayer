#!/usr/bin/env python3
"""Prepare draft iOS listing metadata. Never submits review or releases an app."""
import argparse
import json
from pathlib import Path
from testflight_internal import api, query

APP = '6824160419'
BUNDLE = 'com.crispstrobe.crisperplayer'


def patch(resource, row, attributes):
    api(resource + '/' + row['id'], 'PATCH', {'data': {
        'type': resource, 'id': row['id'], 'attributes': attributes}})


def prepare(write=False):
    data = Path('docs/store/en-US')
    metadata = json.loads((data / 'metadata.json').read_text())
    description = (data / 'description.txt').read_text().strip()
    assert len(description) <= 4000 and len(metadata['keywords']) <= 100 and len(metadata['subtitle']) <= 30
    app = api('apps/' + APP)['data']
    if app['attributes']['bundleId'] != BUNDLE:
        raise RuntimeError('App Store identity mismatch')
    versions = api(query('apps/' + APP + '/appStoreVersions', **{'filter[platform]': 'IOS', 'limit': 50}))['data']
    draft = [v for v in versions if v['attributes']['appStoreState'] == 'PREPARE_FOR_SUBMISSION']
    if len(draft) != 1:
        raise RuntimeError('Expected one editable iOS draft; will not create or change a submitted version')
    version = draft[0]
    localizations = api('appStoreVersions/' + version['id'] + '/appStoreVersionLocalizations')['data']
    locale = next(row for row in localizations if row['attributes']['locale'] == 'en-US')
    infos = api('apps/' + APP + '/appInfos')['data']
    editable = [row for row in infos if row['attributes']['appStoreState'] == 'PREPARE_FOR_SUBMISSION']
    if len(editable) != 1:
        raise RuntimeError('Expected one editable app-info draft')
    info_localizations = api('appInfos/' + editable[0]['id'] + '/appInfoLocalizations')['data']
    info_locale = next(row for row in info_localizations if row['attributes']['locale'] == 'en-US')
    listing = {key: metadata[key] for key in ['keywords', 'supportUrl', 'marketingUrl']}
    listing['description'] = description
    info_attributes = {key: metadata[key] for key in ['subtitle', 'privacyPolicyUrl']}
    if write:
        patch('appStoreVersions', version, {'versionString': metadata['version'], 'copyright': metadata['copyright']})
        patch('appStoreVersionLocalizations', locale, listing)
        patch('appInfoLocalizations', info_locale, info_attributes)
        for resource, row, expected in [('appStoreVersionLocalizations', locale, listing), ('appInfoLocalizations', info_locale, info_attributes)]:
            actual = api(resource + '/' + row['id'])['data']['attributes']
            if not all(actual[key] == value for key, value in expected.items()):
                raise RuntimeError('App Store metadata readback did not match')
        print('Draft iOS 0.1.0 listing updated and verified. No review submission or public release.')
    else:
        print('Editable iOS listing found. Planned metadata comes from docs/store/en-US; use --write to apply.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    prepare(parser.parse_args().write)
