#!/usr/bin/env python3
"""Run native Mac tests against an isolated SMB fixture using Brickwright signing."""
import argparse
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urljoin, urlparse
import wave


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python', default=os.environ.get('CRISPER_SMB_PYTHON', sys.executable),
                        help='Python interpreter with impacket installed')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('This smoke test requires macOS.')
    root = Path(__file__).resolve().parents[1]
    config = root / '.dart_tool/package_config.json'
    packages = json.loads(config.read_text())['packages']
    storage = next(p for p in packages if p['name'] == 'crisp_storage')
    package = Path(unquote(urlparse(urljoin(config.as_uri(), storage['rootUri'] + '/')).path))
    with tempfile.TemporaryDirectory(prefix='crisper-native-smb-') as directory:
        with wave.open(str(Path(directory) / 'SMB audio.wav'), 'wb') as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(8000)
            output.writeframes(bytes(12 * 8000 * 2))
        fixture = subprocess.Popen(
            [args.python, str(package / 'tool/smb_fixture.py'), directory],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            if not select.select([fixture.stdout], [], [], 20)[0]:
                raise RuntimeError('SMB fixture startup timed out.')
            first = fixture.stdout.readline()
            if not first:
                raise RuntimeError('SMB fixture failed; install impacket in the selected Python.')
            port = json.loads(first)['port']
            environment = dict(os.environ, CRISPER_SMB_TEST_URL=f'smb://127.0.0.1:{port}/books/')
            return subprocess.run(
                ['caffeinate', '-diu', sys.executable, 'scripts/macos_local.py', 'test'],
                cwd=root, env=environment).returncode
        finally:
            fixture.terminate()
            try:
                fixture.wait(timeout=10)
            except subprocess.TimeoutExpired:
                fixture.kill()
                fixture.wait()


if __name__ == '__main__':
    raise SystemExit(main())
