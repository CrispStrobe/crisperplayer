#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise actual af_crisper callbacks against the compiled native core.

The host pin/frame model isolates duration, PTS and lifecycle behavior. It does
not replace the full source-built libmpv PCM integration tests in CI.
"""
import argparse
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--build-dir', type=Path, required=True)
    parser.add_argument('--cc', default='cc')
    args = parser.parse_args()
    output = args.build_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    for name in ('audio/aframe.h', 'audio/format.h', 'common/common.h',
                 'filters/f_autoconvert.h', 'filters/filter_internal.h',
                 'filters/user_filters.h', 'options/m_option.h'):
        header = output / 'include' / name
        header.parent.mkdir(parents=True, exist_ok=True)
        header.write_text('#include "test_api.h"\n')
    exe = output / 'test-mpv-filter'
    subprocess.run([args.cc, '-std=c11', '-O2', '-I' + str(output / 'include'),
                    '-I' + str(HERE), '-I' + str(HERE.parents[1] / 'crisper_dsp'),
                    str(HERE / 'filter_contract.c'), str(args.library.resolve()),
                    '-Wl,-rpath,' + str(args.library.resolve().parent), '-lm',
                    '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
