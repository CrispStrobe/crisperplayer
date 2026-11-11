#!/usr/bin/env python3
"""Generate assets/licenses/RUST-SMB.txt for the bundled Rust SMB bridge.

Reads crisp_storage's reviewed Cargo inventory (licensing/rust_dependencies.json),
locates every crate with `cargo metadata`, verifies each recorded license file
against its pinned SHA-256 and writes the license texts for the selected grant.
Identical texts are emitted once with the list of crates they cover.

Usage: scripts/rust_smb_notice.py [--check]  (run `flutter pub get` first)
--check fails when the committed notice differs from a fresh generation.
"""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse, unquote

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'assets/licenses/RUST-SMB.txt'
MIT_BODY = """Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""


def crisp_storage_root():
    config = json.loads((ROOT / '.dart_tool/package_config.json').read_text())
    entry = next(p for p in config['packages'] if p['name'] == 'crisp_storage')
    uri = entry['rootUri']
    if uri.startswith('file:'):
        return Path(unquote(urlparse(uri).path))
    return (ROOT / '.dart_tool' / uri).resolve()


def crate_dirs(storage):
    out = subprocess.run(
        ['cargo', 'metadata', '--format-version', '1', '--locked',
         '--manifest-path', str(storage / 'rust/Cargo.toml')],
        check=True, capture_output=True, text=True).stdout
    return {(p['name'], p['version']): Path(p['manifest_path']).parent
            for p in json.loads(out)['packages']}


def wanted(path, grant):
    name = Path(path).name.upper()
    tokens = {'MIT': ('MIT',), 'Apache-2.0': ('APACHE',),
              'Unicode-3.0': ('UNICODE',)}
    parts = [g.strip() for g in grant.split('AND')]
    matches = any(t in name for g in parts for t in tokens.get(g, ()))
    generic = name in ('LICENSE', 'LICENSE.MD', 'LICENSE.TXT', 'COPYING')
    return matches or generic


def generate():
    storage = crisp_storage_root()
    inventory = json.loads((storage / 'licensing/rust_dependencies.json').read_text())
    dirs = crate_dirs(storage)
    texts = {}
    for pkg in inventory['packages']:
        key = (pkg['name'], pkg['version'])
        label = f"{pkg['name']} {pkg['version']} ({pkg['selected_grant']}; offered: {pkg['license_expression']})"
        chosen = []
        for item in pkg.get('license_files', []):
            path = item['path']
            base = storage if path.startswith('licensing/') else dirs.get(key)
            if base is None:
                raise SystemExit(f'{key}: crate not in cargo metadata')
            file = base / path
            data = file.read_bytes()
            if hashlib.sha256(data).hexdigest() != item['sha256']:
                raise SystemExit(f'{key}: {path} differs from its reviewed hash')
            if pkg['evidence_source'] == 'crate-archive-declaration-and-authors':
                if Path(path).name == 'AUTHORS':
                    chosen.append('Copyright the r-efi authors:\n'
                                  + data.decode().strip() + '\n\n' + MIT_BODY)
                continue
            if path.startswith('licensing/upstream/') or wanted(path, pkg['selected_grant']):
                chosen.append(data.decode('utf-8', 'replace').replace('\r\n', '\n').strip() + '\n')
        if not chosen:
            raise SystemExit(f'{key}: no license text for {pkg["selected_grant"]}')
        for text in chosen:
            texts.setdefault(text, []).append(label)
    lines = [
        'Rust SMB backend (crisp_smb / crisp_smb_bridge)',
        '',
        'CrisperPlayer bundles the crisp_smb_bridge native library from',
        'https://github.com/CrispStrobe/CrispCloud (packages/crisp_storage),',
        'licensed MIT OR Apache-2.0. It is built from the Rust crates below; for',
        'crates offering several licenses the selected grant is named first.',
        f'Inventory: {inventory["scope"]}',
        '',
    ]
    for text, crates in sorted(texts.items(), key=lambda kv: sorted(kv[1])[0]):
        lines.append('=' * 78)
        lines.extend(sorted(crates))
        lines.append('-' * 78)
        lines.append(text.rstrip())
        lines.append('')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    content = generate()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text() != content:
            sys.exit(f'{OUTPUT.relative_to(ROOT)} is stale; run scripts/rust_smb_notice.py')
        print('Rust SMB notice is current.')
        return
    OUTPUT.write_text(content)
    print(f'Wrote {OUTPUT.relative_to(ROOT)} ({len(content)} bytes)')


if __name__ == '__main__':
    main()
