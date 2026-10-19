#!/usr/bin/env python3
"""Sign native bundles when release identities are configured; never mint keys."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def macos(app, cli, keychain, identity, notary_key, key_id, issuer):
    if not identity.startswith('Developer ID Application:'):
        raise ValueError('Public Mac downloads require Developer ID Application, not Apple Distribution.')
    if not keychain.is_file():
        raise ValueError('Use the explicitly selected build keychain.')
    identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning', str(keychain)], text=True)
    if f'"{identity}"' not in identities:
        raise ValueError('The selected keychain has no matching valid Developer ID identity.')
    for bundle in [app, cli]:
        # Sign inner Mach-O files before their containing frameworks/bundles.
        for path in sorted(bundle.rglob('*'), key=lambda p: len(p.parts), reverse=True):
            if path.is_symlink() or not path.is_file():
                continue
            kind = subprocess.check_output(['file', '-b', str(path)], text=True)
            if 'Mach-O' in kind:
                run('codesign', '--force', '--options', 'runtime', '--timestamp', '--keychain', keychain, '--sign', identity, path)
        for framework in sorted(bundle.rglob('*.framework'), key=lambda p: len(p.parts), reverse=True):
            run('codesign', '--force', '--options', 'runtime', '--timestamp', '--keychain', keychain, '--sign', identity, framework)
    run('codesign', '--force', '--options', 'runtime', '--timestamp', '--keychain', keychain,
        '--sign', identity, '--entitlements', 'macos/Runner/Release.entitlements', app)
    run('codesign', '--verify', '--deep', '--strict', app)
    if not all([notary_key, key_id, issuer]) or not notary_key.is_file():
        raise ValueError('A signed public Mac release also requires notarization API credentials.')
    # Notarize the same app and CLI payload that release.py subsequently packages.
    with tempfile.TemporaryDirectory(prefix='crisper-notary-') as directory:
        stage = Path(directory) / 'CrisperPlayer'
        stage.mkdir()
        run('ditto', app, stage / app.name)
        run('ditto', cli, stage / 'cli')
        archive = Path(directory) / 'CrisperPlayer.zip'
        run('ditto', '-c', '-k', '--keepParent', stage, archive)
        result = subprocess.check_output(['xcrun', 'notarytool', 'submit', str(archive), '--key', str(notary_key),
            '--key-id', key_id, '--issuer', issuer, '--wait', '--timeout', '30m', '--output-format', 'json'], text=True)
        data = json.loads(result)
        if data.get('status') != 'Accepted':
            raise RuntimeError('Apple notarization did not accept the bundle: ' + str(data.get('id')))
    run('xcrun', 'stapler', 'staple', app)
    run('xcrun', 'stapler', 'validate', app)
    run('spctl', '--assess', '--type', 'execute', '--verbose', app)
    print('Developer ID signature and notarization verified.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--cli', type=Path, required=True)
    parser.add_argument('--keychain', type=Path, required=True)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--notary-key', type=Path, required=True)
    parser.add_argument('--key-id', required=True)
    parser.add_argument('--issuer', required=True)
    args = parser.parse_args()
    macos(args.app.resolve(strict=True), args.cli.resolve(strict=True), args.keychain.resolve(strict=True),
          args.identity, args.notary_key, args.key_id, args.issuer)


if __name__ == '__main__':
    main()
