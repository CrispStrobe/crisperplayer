#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Launch an installed/development app with a controlled portable-audio build.

This affects only the child process. It neither replaces system libraries nor
changes the release license gate. Build the prefix with build_linux_audio.py or
build_windows_audio.py first, then pass the normal app or flutter run command.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', type=Path, required=True)
    parser.add_argument('--runtime-bin', type=Path, action='append', default=[],
                        help='Additional Windows runtime directory, e.g. MSYS2 ucrt64/bin.')
    parser.add_argument('command', nargs=argparse.REMAINDER,
                        help='App command after --, e.g. -- flutter run -d linux')
    args = parser.parse_args()
    command = args.command
    if command[:1] == ['--']:
        command = command[1:]
    if not command:
        parser.error('Pass the app command after --.')
    if sys.platform not in ('linux', 'win32'):
        parser.error('This launcher supports Linux and Windows desktop builds.')
    prefix = args.prefix.resolve()
    windows = sys.platform == 'win32'
    native_dir = prefix / ('bin' if windows else 'lib')
    library = native_dir / ('libmpv-2.dll' if windows else 'libmpv.so')
    if not library.is_file():
        parser.error(f'The controlled libmpv was not found: {library}')
    runtime_dirs = [directory.resolve() for directory in args.runtime_bin]
    if any(not directory.is_dir() for directory in runtime_dirs):
        parser.error('Every --runtime-bin must name an existing directory.')
    environment = dict(os.environ)
    environment['LIBMPV_LIBRARY_PATH'] = str(library)
    search_key = 'PATH' if windows else 'LD_LIBRARY_PATH'
    environment[search_key] = os.pathsep.join([
        str(native_dir),
        *[str(directory) for directory in runtime_dirs],
        *([environment[search_key]] if environment.get(search_key) else []),
    ])
    try:
        return subprocess.call(command, env=environment)
    except OSError as error:
        print(f'Could not launch the app: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
