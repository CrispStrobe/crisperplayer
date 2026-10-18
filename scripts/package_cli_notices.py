"""Include the bundled SMB library's license and corresponding-source notice."""
import json
from pathlib import Path
import sys
from urllib.parse import unquote, urljoin, urlparse

config = Path('.dart_tool/package_config.json').resolve()
packages = json.loads(config.read_text())['packages']
storage = next(p for p in packages if p['name'] == 'crisp_storage')
root = Path(unquote(urlparse(urljoin(config.as_uri(), storage['rootUri'] + '/')).path))
bundle = Path(sys.argv[1])
if not (bundle / 'bin').is_dir():
    raise SystemExit('Build the CLI bundle first.')
(bundle / 'NOTICE-LIBSMB2.txt').write_bytes((root / 'NOTICE-LIBSMB2.txt').read_bytes())
