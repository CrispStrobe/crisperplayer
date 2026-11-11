#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build the source-pinned non-GPL audio candidate in an MSYS2 UCRT64 shell.

This uses the same reviewed sources and portable filter as the Linux recipe.
It does not install packages, replace a system library, or approve release use.
"""
import subprocess
import sys
import tarfile
from build_linux_audio import main

if __name__ == '__main__':
    try:
        raise SystemExit(main('windows'))
    except (OSError, ValueError, tarfile.TarError, subprocess.CalledProcessError) as error:
        print(f'Windows LGPL audio candidate build stopped: {error}', file=sys.stderr)
        raise SystemExit(1)
