#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compile exactly the offline native DSP source closure using a host C/C++ compiler."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import urlparse

CORE = Path(__file__).resolve().parents[1]
REPO = CORE.parents[3]


def verify_vendor():
    vendor = CORE / 'vendor'
    manifest = json.loads((vendor / 'manifest.json').read_text())
    expected = set()
    for component in manifest['components']:
        if not re.fullmatch(r'[0-9a-f]{40}', component.get('revision', '')):
            raise RuntimeError('Missing upstream source pin')
        git_files = component.get('source_type', 'archive') == 'git-files'
        if git_files:
            if not re.fullmatch(r'[0-9a-f]{40}', component.get('git_tree_sha1', '')):
                raise RuntimeError('Missing exact upstream Git tree pin')
        elif component.get('source_type', 'archive') != 'archive' or not re.fullmatch(r'[0-9a-f]{64}', component.get('archive_sha256', '')):
            raise RuntimeError('Missing upstream source archive pin')
        for item in component['files']:
            path = vendor / item['path']
            if not path.resolve().is_relative_to(vendor.resolve()):
                raise RuntimeError('Vendored file escapes source directory')
            expected.add(item['path'])
            data = path.read_bytes() if path.is_file() else b''
            if not path.is_file() or hashlib.sha256(data).hexdigest() != item['sha256']:
                raise RuntimeError(f'Unreviewed/missing vendored file: {path}')
            if git_files:
                upstream = item.get('upstream_path', '')
                source = urlparse(item.get('source_url', ''))
                clean_path = upstream and not upstream.startswith('/') and all(p not in ('', '.', '..') for p in upstream.split('/'))
                if not clean_path or source.scheme != 'https' or not source.netloc or source.query or source.fragment or component['revision'] not in source.path.split('/') or not source.path.endswith('/' + upstream):
                    raise RuntimeError(f'Invalid pinned Git source URL: {path}')
                blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
                if blob != item.get('git_blob_sha1'):
                    raise RuntimeError(f'Upstream Git blob hash does not match: {path}')
    actual = {str(p.relative_to(vendor)) for p in vendor.rglob('*') if p.is_file()} - {'manifest.json'}
    if actual != expected:
        raise RuntimeError(f'Unreviewed source closure: {sorted(actual ^ expected)}')
    if (vendor / 'eigen/unsupported').exists():
        raise RuntimeError('Unsupported Eigen modules are not part of the reviewed closure')
    return manifest


def run(command):
    process = subprocess.run(command, capture_output=True, text=True)
    if process.returncode:
        raise RuntimeError(' '.join(command) + '\n' + process.stdout + process.stderr)
    return process


def build(out, cc, cxx, jobs):
    verify_vendor()
    out.mkdir(parents=True, exist_ok=True)
    c_sources = ['vendor/sonic/sonic.c', 'vendor/pffft/pffft.c', 'vendor/pffft/fftpack.c']
    cpp_sources = ['crisper_dsp.cpp', 'wsola/wsola.cpp'] + [str(p.relative_to(CORE)) for p in sorted((CORE / 'vendor/bungee/src').glob('*.cpp'))]
    cmake = (CORE / 'CMakeLists.txt').read_text()
    for source in c_sources + cpp_sources:
        if source not in cmake:
            raise RuntimeError(f'Host/Android CMake source lists differ: {source}')
    includes = [str(CORE / d) for d in ('.', 'vendor/bungee', 'vendor/eigen', 'vendor/pffft', 'vendor/sonic', 'vendor/signalsmith-stretch', 'vendor')]
    definitions = ['-DEIGEN_MPL2_ONLY=1', '-DEIGEN_DONT_PARALLELIZE=1', '-DBUNGEE_SELF_TEST=0', '-DBUNGEE_VISIBILITY=', '-DBUNGEE_VERSION="61f52bf34be577d189d388772ddfa3696dee77d8"', '-Deigen_assert=BUNGEE_ASSERT1']
    commands = []
    objects = []
    for source in c_sources + cpp_sources:
        obj = out / (source.replace('/', '_') + '.o')
        objects.append(str(obj))
        compiler = cc if source.endswith('.c') else cxx
        flags = [] if source.endswith('.c') else ['-std=c++20', '-fwrapv']
        command = [compiler, '-O2', '-g', '-fPIC', '-fvisibility=hidden', *flags, *definitions, *['-I' + i for i in includes], '-c', str(CORE / source), '-o', str(obj)]
        commands.append(command)
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        list(pool.map(run, commands))
    library = out / 'libcrisper_dsp.so'
    link = [cxx, '-shared', '-Wl,--no-undefined', *objects, '-lm', '-o', str(library)]
    run(link)
    search_test = out / 'test-wsola-search'
    search_test_command = [cxx, '-O2', '-std=c++20', '-I' + str(CORE),
                           str(CORE / 'tools/test_wsola_search.cpp'),
                           str(out / 'wsola_wsola.cpp.o'), '-o', str(search_test)]
    run(search_test_command)
    search_result = json.loads(run([str(search_test)]).stdout)
    report = {
        'scope': 'Linux host build; not an Android ABI or device validation',
        'compiler_c': run([cc, '--version']).stdout.splitlines()[0],
        'compiler_cxx': run([cxx, '--version']).stdout.splitlines()[0],
        'source_manifest_sha256': hashlib.sha256((CORE / 'vendor/manifest.json').read_bytes()).hexdigest(),
        'adapter_sha256': hashlib.sha256((CORE / 'crisper_dsp.cpp').read_bytes()).hexdigest(),
        'wsola_source_sha256': {name: hashlib.sha256((CORE / name).read_bytes()).hexdigest() for name in ('wsola/wsola.h', 'wsola/wsola.cpp')},
        'build_input_sha256': {
            name: hashlib.sha256((CORE / name).read_bytes()).hexdigest()
            for name in ('CMakeLists.txt', 'crisper_dsp.h', 'crisper_dsp.cpp',
                         'wsola/wsola.h', 'wsola/wsola.cpp',
                         'tools/build_host.py', 'tools/test_wsola_search.cpp')
        },
        'library': str(library),
        'library_sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
        'wsola_search_checks': search_result,
        'commands': commands + [link, search_test_command, [str(search_test)]],
    }
    (out / 'build-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ('scope', 'compiler_cxx', 'library', 'library_sha256')}, indent=2))
    return library


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, default=REPO / 'build/native-dsp')
    parser.add_argument('--cc', default=os.environ.get('CC', 'gcc'))
    parser.add_argument('--cxx', default=os.environ.get('CXX', 'g++'))
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    try:
        build(args.build_dir.resolve(), args.cc, args.cxx, args.jobs)
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
