#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Add CrisperPlayer's four optional tempo engines to a pinned libmpv source tree.

This only prepares an isolated source tree. It neither installs a library nor
changes the system mpv. It works with Linux and MinGW/Windows source builds.
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / 'packages/just_audio/native/crisper_dsp'
INTEGRATION = ROOT / 'packages/just_audio/native/mpv'


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(source: Path, evidence: Path) -> dict:
    source = source.resolve()
    if source == ROOT or source in ROOT.parents or (source / '.git').exists():
        raise ValueError('Use an isolated unpacked mpv source archive, not a working repository')
    pin = json.loads((INTEGRATION / 'upstream.json').read_text())
    originals = {}
    for name, expected in pin['files'].items():
        path = source / name
        if not path.is_file() or digest(path) != expected:
            raise ValueError(f'Unexpected mpv {pin["version"]} source: {name}')
        originals[name] = path.read_text()
    if (source / 'crisper-dsp').exists() or (source / 'audio/filter/af_crisper.c').exists():
        raise ValueError('Portable mpv integration already exists; use a fresh unpacked tree')

    spec = importlib.util.spec_from_file_location('crisper_source_check', CORE / 'tools/build_host.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.verify_vendor()

    changes = {
        'meson.build': (
            '    \'audio/filter/af_drop.c\',',
            '    \'audio/filter/af_crisper.c\',\n    \'audio/filter/af_drop.c\','),
        'filters/user_filters.c': ('    &af_scaletempo2,', '    &af_scaletempo2,\n    &af_crisper,'),
        'filters/user_filters.h': (
            'extern const struct mp_user_filter_entry af_scaletempo2;',
            'extern const struct mp_user_filter_entry af_scaletempo2;\n'
            'extern const struct mp_user_filter_entry af_crisper;'),
    }
    patched = {}
    for name, (before, after) in changes.items():
        if originals[name].count(before) != 1:
            raise ValueError(f'Ambiguous mpv patch location: {name}')
        text = originals[name].replace(before, after)
        if name == 'meson.build':
            # A static library is a build target. Meson requires all upstream
            # add_project_arguments/add_project_link_arguments calls to run
            # before it, while libmpv still needs our dependency at creation.
            marker = '# build targets'
            if text.count(marker) != 1:
                raise ValueError('Ambiguous mpv dependency insertion')
            text = text.replace(marker, "subdir('crisper-dsp')\n\n" + marker)
        patched[name] = text

    # Verify every prerequisite before changing the isolated source tree.
    destination = source / 'crisper-dsp'
    destination.mkdir()
    shutil.copytree(CORE, destination / 'core', ignore=shutil.ignore_patterns(
        '.git', '.build', 'build', '__pycache__', '*.pyc', '.cxx', '.gradle', '.dart_tool'))
    shutil.copy2(INTEGRATION / 'meson.build', destination / 'meson.build')
    shutil.copy2(INTEGRATION / 'af_crisper.c', source / 'audio/filter/af_crisper.c')
    patch = []
    for name, text in patched.items():
        (source / name).write_text(text)
        patch.extend(difflib.unified_diff(originals[name].splitlines(True),
                                         text.splitlines(True),
                                         fromfile='a/' + name, tofile='b/' + name))
    report = {
        'schema_version': 1,
        'status': 'source_prepared_not_release_approved',
        'mpv': pin,
        'integration_sources': {name: digest(INTEGRATION / name)
                                for name in ('af_crisper.c', 'meson.build', 'upstream.json')},
        'core_manifest_sha256': digest(CORE / 'vendor/manifest.json'),
        'prepared_files': {str(path.relative_to(source)): digest(path)
                          for path in sorted(destination.rglob('*')) if path.is_file()},
        'patched_files': {name: digest(source / name) for name in patched},
        'patch': ''.join(patch),
    }
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--evidence', required=True, type=Path)
    args = parser.parse_args()
    try:
        prepare(args.source, args.evidence)
    except (OSError, ValueError, RuntimeError) as error:
        parser.exit(1, f'Portable mpv preparation failed: {error}\n')
    print(f'Prepared optional Sonic, WSOLA, Signalsmith and Bungee filters in {args.source}')
