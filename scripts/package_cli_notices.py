"""Include the bundled SMB library's license and corresponding-source notice."""
import json
from pathlib import Path
import sys
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname

config = Path('.dart_tool/package_config.json').resolve()
packages = json.loads(config.read_text())['packages']
storage = next(p for p in packages if p['name'] == 'crisp_storage')
root = Path(url2pathname(urlparse(urljoin(config.as_uri(), storage['rootUri'] + '/')).path))
bundle = Path(sys.argv[1])
if not (bundle / 'bin').is_dir():
    raise SystemExit('Build the CLI bundle first.')
(bundle / 'NOTICE-LIBSMB2.txt').write_bytes((root / 'NOTICE-LIBSMB2.txt').read_bytes())

# Compiled Dart executables also redistribute third-party package code.
notices = bundle / 'licenses'
notices.mkdir(exist_ok=True)
for package in packages:
    root = Path(url2pathname(urlparse(urljoin(config.as_uri(), package['rootUri'] + '/')).path))
    license_file = root / 'LICENSE'
    if license_file.is_file():
        (notices / (package['name'] + '-LICENSE.txt')).write_bytes(license_file.read_bytes())
