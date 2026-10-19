#!/usr/bin/env python3
"""Upload verified real screenshots to the editable draft, without submitting it."""
import argparse
import hashlib
import time
from pathlib import Path
import urllib.parse
import urllib.request
from testflight_internal import api, query

APP = '6824160419'
BUNDLE = 'com.crispstrobe.crisperplayer'
# Legacy App Store Connect enums also accept the current 6.9/13-inch dimensions.
SETS = {'iphone-6.9': 'APP_IPHONE_67', 'ipad-13': 'APP_IPAD_PRO_3GEN_129'}


def upload(write=False):
    assert api('apps/' + APP)['data']['attributes']['bundleId'] == BUNDLE
    versions = api(query('apps/' + APP + '/appStoreVersions', **{'filter[platform]': 'IOS', 'limit': 50}))['data']
    drafts = [v for v in versions if v['attributes']['appStoreState'] == 'PREPARE_FOR_SUBMISSION' and v['attributes']['versionString'] == '0.1.0']
    if len(drafts) != 1:
        raise RuntimeError('Expected one editable iOS 0.1.0 draft')
    locales = api('appStoreVersions/' + drafts[0]['id'] + '/appStoreVersionLocalizations')['data']
    locale = next(row for row in locales if row['attributes']['locale'] == 'en-US')
    sets = api('appStoreVersionLocalizations/' + locale['id'] + '/appScreenshotSets')['data']
    for device, display_type in SETS.items():
        images = sorted((Path('docs/store/screenshots') / device).glob('*.jpg'))
        if len(images) != 5:
            raise RuntimeError('Capture five native JPEG screens for ' + device)
        if not write:
            print(f'Prepared {len(images)} real {device} screenshots; --write uploads to the draft.')
            continue
        current = next((s for s in sets if s['attributes']['screenshotDisplayType'] == display_type), None)
        if current is None:
            current = api('appScreenshotSets', 'POST', {'data': {'type': 'appScreenshotSets',
                'attributes': {'screenshotDisplayType': display_type},
                'relationships': {'appStoreVersionLocalization': {'data': {'type': 'appStoreVersionLocalizations', 'id': locale['id']}}}}})['data']
        existing = api('appScreenshotSets/' + current['id'] + '/appScreenshots')['data']
        if len(existing) + len(images) > 10 and not all(any(row['attributes']['fileName'] == image.name for row in existing) for image in images):
            raise RuntimeError('Screenshot set already contains user assets; refusing to replace them.')
        for image in images:
            content = image.read_bytes()
            if content[:2] != b'\xff\xd8':
                raise RuntimeError('Use unmodified native JPEG simulator captures')
            checksum = hashlib.md5(content).hexdigest()  # Apple upload-integrity protocol, not encryption.
            same = next((row for row in existing if row['attributes']['fileName'] == image.name and row['attributes'].get('sourceFileChecksum') == checksum), None)
            if same is not None:
                record = same
            else:
                record = api('appScreenshots', 'POST', {'data': {'type': 'appScreenshots',
                    'attributes': {'fileName': image.name, 'fileSize': len(content)},
                    'relationships': {'appScreenshotSet': {'data': {'type': 'appScreenshotSets', 'id': current['id']}}}}})['data']
                for operation in record['attributes']['uploadOperations']:
                    target = urllib.parse.urlparse(operation['url'])
                    if target.scheme != 'https' or target.username or target.password:
                        raise RuntimeError('Unsafe Apple asset-upload URL')
                    offset, length = operation['offset'], operation['length']
                    if offset < 0 or length <= 0 or offset + length > len(content):
                        raise RuntimeError('Invalid Apple upload byte range')
                    request = urllib.request.Request(operation['url'], data=content[offset:offset + length],
                        method=operation['method'], headers={h['name']: h['value'] for h in operation['requestHeaders']})
                    # Only the operation-specific upload headers are sent. The
                    # App Store Connect bearer token never leaves its API host.
                    with urllib.request.urlopen(request, timeout=60) as response:
                        response.read()
                api('appScreenshots/' + record['id'], 'PATCH', {'data': {'type': 'appScreenshots', 'id': record['id'],
                    'attributes': {'uploaded': True, 'sourceFileChecksum': checksum}}})
            for attempt in range(30):
                actual = api('appScreenshots/' + record['id'])['data']
                state = actual['attributes']['assetDeliveryState']['state']
                if state == 'COMPLETE':
                    break
                if state == 'FAILED':
                    raise RuntimeError('Apple rejected screenshot ' + device + '/' + image.name + ': ' + str(actual['attributes']['assetDeliveryState'].get('errors')))
                time.sleep(2)
            else:
                raise RuntimeError('Apple screenshot processing did not complete: ' + image.name)
            print('Verified screenshot:', device, image.name, state)
    if write:
        print('Screenshots attached to editable draft. No review submission or public release.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    upload(parser.parse_args().write)
