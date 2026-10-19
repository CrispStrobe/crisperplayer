#!/usr/bin/env python3
"""Capture real simulator screens from an isolated Flutter integration fixture."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
import subprocess
import threading

NAMES = {'01-library', '02-player', '03-chapters', '04-bookmarks', '05-sleep-timer'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True, help='A dedicated booted iOS Simulator UUID')
    parser.add_argument('--device-class', choices=['iphone-6.9', 'ipad-13'], required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Fa-f0-9-]{36}', args.device):
        parser.error('Use an explicit simulator UUID.')
    output = Path('docs/store/screenshots') / args.device_class
    output.mkdir(parents=True, exist_ok=True)
    captured = set()

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            name = self.path.removeprefix('/screenshot/')
            if name not in NAMES or self.path != '/screenshot/' + name:
                self.send_error(400)
                return
            try:
                subprocess.run(['xcrun', 'simctl', 'io', args.device, 'screenshot', '--type=jpeg',
                                str(output / (name + '.jpg'))], check=True, timeout=30,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                captured.add(name)
                self.send_response(204)
                self.end_headers()
            except (subprocess.SubprocessError, OSError):
                self.send_error(500)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        subprocess.run(['flutter', 'test', 'integration_test/store_screenshots_test.dart', '-d', args.device,
            '--dart-define=STORE_SCREENSHOT_URL=http://127.0.0.1:' + str(server.server_port)], check=True)
        if captured != NAMES:
            raise RuntimeError('Not all store screens were captured.')
        print(f'Captured and verified {len(captured)} real {args.device_class} screens in {output}')
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
