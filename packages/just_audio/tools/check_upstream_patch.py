"""Check retained upstream bytes and the complete, reviewed just_audio patch."""

import argparse
import difflib
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream', type=Path, required=True)
    args = parser.parse_args()
    vendor = Path(__file__).resolve().parents[1]
    manifest = json.loads((vendor / 'UPSTREAM_SHA256.json').read_text())
    differences = []
    modified = []
    for name, expected in manifest.items():
        original = (args.upstream / name).read_bytes()
        if hashlib.sha256(original).hexdigest() != expected:
            raise SystemExit(f'Original upstream hash mismatch: {name}')
        current = (vendor / name).read_bytes()
        if original != current:
            modified.append(name)
            differences.extend(difflib.unified_diff(
                original.decode().splitlines(keepends=True),
                current.decode().splitlines(keepends=True),
                fromfile=f'a/{name}', tofile=f'b/{name}',
            ))
    additions = json.loads((vendor / 'LOCAL_ADDITIONS.json').read_text())
    for name in additions:
        if name in manifest or (args.upstream / name).exists():
            raise SystemExit(f'Local addition shadows an upstream file: {name}')
        current = (vendor / name).read_text()
        differences.extend(difflib.unified_diff(
            [], current.splitlines(keepends=True),
            fromfile='/dev/null', tofile=f'b/{name}',
        ))
    actual = ''.join(differences)
    if actual != (vendor / 'UPSTREAM.patch').read_text():
        raise SystemExit('Vendored changes differ from the reviewed UPSTREAM.patch')
    print(f'Verified {len(manifest)} upstream hashes, {len(modified)} patched files, '
          f'and {len(additions)} local additions.')


if __name__ == '__main__':
    main()
