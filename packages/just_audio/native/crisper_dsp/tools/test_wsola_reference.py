#!/usr/bin/env python3
# Copyright 2012 The Chromium Authors
# Copyright 2026 CrisperPlayer contributors
# SPDX-License-Identifier: BSD-3-Clause
"""Compare unchanged Chromium helpers with the maintained portable extraction.

Search, energy and interpolation fixtures derive from the pinned upstream
audio_renderer_algorithm_unittest.cc. Its notice is in
../vendor/chromium-wsola/LICENSE. Only Python's stdlib and a C++20 compiler are
needed. See wsola_reference/README.md for the test-only shim boundaries.
"""
import argparse
import ctypes as C
import hashlib
import json
import math
import os
from pathlib import Path
import shlex
import subprocess
import sys
import time
import unittest

NATIVE = Path(__file__).resolve().parents[1]
REPO = Path(__file__).resolve().parents[5]
HELPERS = NATIVE / 'tools/wsola_reference'
VENDOR = NATIVE / 'vendor/chromium-wsola'
REVISION = 'ddd30ef8aa98443509bf4ce006cb36b4e2296c0b'
F = C.POINTER(C.c_float)
ORIGINAL = PORT = None
MEASUREMENTS = []


def floats(values):
    return (C.c_float * len(values))(*values)


def search(frames, targets, exclusion=(45, 63), mode=0, decimation=5,
           portable=False, preferred=0):
    channels = len(frames[0])
    a = floats([value for frame in frames for value in frame])
    b = floats([value for frame in targets for value in frame])
    args = (a, len(frames), b, len(targets), channels, *exclusion)
    if portable:
        return PORT.portable_search(*args, preferred)
    return ORIGINAL.reference_search(*args, mode, decimation)


def bind(original_path, port_path):
    original, port = C.CDLL(str(original_path)), C.CDLL(str(port_path))
    original.reference_search.argtypes = [F, C.c_int, F, C.c_int, C.c_int,
                                          C.c_int64, C.c_int64, C.c_int, C.c_int]
    original.reference_search.restype = C.c_int
    for name, args in {
        'dot': [F, F, C.c_int, C.c_int, F],
        'energy': [F, C.c_int, C.c_int, C.c_int, F],
        'quadratic': [F, F],
        'hann': [F, C.c_int],
    }.items():
        function = getattr(original, 'reference_' + name)
        function.argtypes, function.restype = args, None
    port.portable_search.argtypes = [F, C.c_int, F, C.c_int, C.c_int,
                                     C.c_int, C.c_int, C.c_int]
    port.portable_search.restype = C.c_int
    port.portable_dot.argtypes, port.portable_dot.restype = [F, F, C.c_int], C.c_float
    port.portable_hann.argtypes, port.portable_hann.restype = [F, C.c_int], None
    port.portable_simd_name.argtypes, port.portable_simd_name.restype = [], C.c_char_p
    return original, port


def stereo_fixture():
    left = [0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0]
    right = [0, 0, 0, 0, 0, 0, 0, .1, 1, .1, 0, 0]
    return list(zip(left, right)), list(zip([1, 1, 1, 0], [0, 1, .1, 1]))


class ReferenceSemantics(unittest.TestCase):
    def test_asymmetric_dot_sum(self):
        a, b, result = floats(list(range(1, 9))), floats([1] * 8), floats([0])
        ORIGINAL.reference_dot(a, b, 8, 1, result)
        self.assertEqual(result[0], 36)
        self.assertEqual(PORT.portable_dot(a, b, 8), 36)
        MEASUREMENTS.append({'case': 'asymmetric-eight-lane-dot', 'value': 36})

    def test_scalar_original_against_port_dot_remainders(self):
        maximum_error = 0
        for frames in range(1, 100):
            a = floats([math.sin(i * .23) for i in range(frames)])
            b = floats([math.cos(i * .31) for i in range(frames)])
            result = floats([0])
            ORIGINAL.reference_dot(a, b, frames, 1, result)
            error = abs(PORT.portable_dot(a, b, frames) - result[0])
            maximum_error = max(maximum_error, error)
            self.assertLess(error, 1e-5, f'frames={frames}')
        MEASUREMENTS.append({'case': 'scalar-vs-port-dot', 'frame_sizes': 99,
                             'max_absolute_error': maximum_error})

    def test_original_dot_preserves_channel_polarity(self):
        a = floats([value for i in range(1, 9) for value in (i, -i)])
        b = floats([1] * 16)
        result = floats([0, 0])
        ORIGINAL.reference_dot(a, b, 8, 2, result)
        self.assertEqual(list(result), [36, -36])

    def test_original_sliding_energy_fixture(self):
        samples = floats([value for n in range(20) for value in (n, 19 - n)])
        energies = floats([0] * 36)
        ORIGINAL.reference_energy(samples, 20, 2, 3, energies)
        expected = [sum((n + k if c == 0 else 19 - n - k) ** 2 for k in range(3))
                    for n in range(18) for c in range(2)]
        self.assertEqual(list(energies), expected)
        MEASUREMENTS.append({'case': 'original-stereo-moving-energy', 'values_checked': 36})

    def test_original_stereo_search_fixture(self):
        source, target = stereo_fixture()
        observed = {
            'full': search(source, target, mode=1),
            'full_excluded': search(source, target, (2, 5), mode=1),
            'decimated4': search(source, target, mode=2, decimation=4),
            'optimal': search(source, target),
        }
        self.assertEqual(observed, {'full': 5, 'full_excluded': 7,
                                    'decimated4': 4, 'optimal': 5})
        MEASUREMENTS.append({'case': 'original-stereo-search', **observed})

    def test_port_matches_original_stereo_fixture(self):
        source, target = stereo_fixture()
        self.assertEqual(search(source, target, portable=True), search(source, target))
        self.assertEqual(search(source, target, (2, 5), portable=True),
                         search(source, target, (2, 5), mode=1))

    def test_original_quadratic_and_flat_interpolation(self):
        result = floats([0, 0])
        ORIGINAL.reference_quadratic(floats([.7 - 1.2 + .8, .8, .7 + 1.2 + .8]), result)
        x = -1.2 / (2 * .7)
        y = .7 * x * x + 1.2 * x + .8
        self.assertAlmostEqual(result[0], x, delta=1e-6)
        self.assertAlmostEqual(result[1], y, delta=1e-6)
        ORIGINAL.reference_quadratic(floats([1, 1, 1]), result)
        self.assertEqual(list(result), [0, 1])

    def test_port_shared_stereo_match_without_downmix_cancellation(self):
        values = [math.sin(i * .37) + .2 * math.sin(i * .71) for i in range(120)]
        opposite = [(value, -value) for value in values]
        self.assertEqual(search(opposite, opposite[19:59], (1000, 1100),
                                portable=True, preferred=40), 19)

    def test_intentional_negative_correlation_fallback_fix(self):
        source, target = [[-1]] * 4, [[1]]
        # The exact upstream FullSearch returns its excluded initial index when
        # every score is negative. Preserve that observation and require the fix.
        old = search(source, target, (0, 0), mode=1)
        new = search(source, target, (0, 0), portable=True, preferred=2)
        self.assertEqual(old, 0)
        self.assertEqual(new, 2)
        MEASUREMENTS.append({'case': 'intentional-negative-correlation-fix',
                             'original_excluded_index': old, 'port_valid_index': new})

    def test_port_signed_exclusions_and_single_valid_candidate(self):
        self.assertEqual(search([[0]] * 6, [[0]], (-10, 2), portable=True), 3)
        self.assertEqual(search([[0]] * 6, [[0]], (-10, 10), portable=True), -1)
        self.assertEqual(search([[0]] * 6, [[0]], (1, 10), portable=True, preferred=5), 0)

    def test_port_silence_prefers_requested_center(self):
        for preferred in (0, 1, 8, 19):
            self.assertEqual(search([[0]] * 20, [[0]], (30, 40),
                                    portable=True, preferred=preferred), preferred)

    def test_hann_windows_match_with_documented_precision_tolerance(self):
        maximum_difference = maximum_pair_error = 0
        sizes = (2, 160, 320, 882, 960, 3840)
        for size in sizes:
            original, port = floats([0] * size), floats([0] * size)
            ORIGINAL.reference_hann(original, size)
            PORT.portable_hann(port, size)
            difference = max(abs(a - b) for a, b in zip(original, port))
            pair_error = max(abs(port[n] + port[n + size // 2] - 1)
                             for n in range(size // 2))
            self.assertLess(difference, 5e-7, f'size={size}')
            self.assertLess(pair_error, 1e-6, f'size={size}')
            maximum_difference = max(maximum_difference, difference)
            maximum_pair_error = max(maximum_pair_error, pair_error)
        MEASUREMENTS.append({'case': 'hann-original-vs-double-precision-port',
                             'sizes': len(sizes), 'max_absolute_difference': maximum_difference,
                             'max_overlap_pair_error': maximum_pair_error})


def verified_sources():
    manifest = json.loads((NATIVE / 'vendor/manifest.json').read_text())
    component = next(item for item in manifest['components'] if item['id'] == 'chromium-wsola')
    if component['revision'] != REVISION:
        raise RuntimeError('Review the reference fixtures when changing the Chromium revision')
    result = []
    for item in component['files']:
        data = (NATIVE / 'vendor' / item['path']).read_bytes()
        sha256 = hashlib.sha256(data).hexdigest()
        blob = hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest()
        if sha256 != item['sha256'] or blob != item['git_blob_sha1']:
            raise RuntimeError(f'Upstream original is modified: {item["path"]}')
        result.append({'path': item['upstream_path'], 'sha256': sha256, 'git_blob_sha1': blob})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', default=os.environ.get('CXX', 'c++'))
    parser.add_argument('--build-dir', type=Path, default=REPO / 'build/native-dsp/wsola-reference')
    parser.add_argument('--report', type=Path, default=REPO / 'build/native-dsp/wsola-reference-report.json')
    args = parser.parse_args()
    source_identity = verified_sources()
    args.build_dir.mkdir(parents=True, exist_ok=True)
    extension = '.dylib' if sys.platform == 'darwin' else '.so'
    original_path = args.build_dir.resolve() / ('libchromium_wsola_reference' + extension)
    port_path = args.build_dir.resolve() / ('libportable_wsola_semantics' + extension)
    compiler = shlex.split(args.compiler)
    if not compiler:
        parser.error('--compiler must name a C++20 compiler')
    compiler_version = subprocess.run(compiler + ['--version'], check=True,
                                      capture_output=True, text=True).stdout.splitlines()[0]
    flags = ['-std=c++20', '-O2', '-fPIC', '-dynamiclib' if sys.platform == 'darwin' else '-shared']
    commands = [
        compiler + flags + ['-I' + str(HELPERS / 'shims'), '-I' + str(VENDOR),
                            str(VENDOR / 'media/filters/wsola_internals.cc'),
                            str(HELPERS / 'reference_bridge.cpp'), '-o', str(original_path)],
        compiler + flags + [str(HELPERS / 'portable_bridge.cpp'), '-o', str(port_path)],
    ]
    for command in commands:
        subprocess.run(command, check=True)
    global ORIGINAL, PORT
    ORIGINAL, PORT = bind(original_path, port_path)
    started = time.monotonic()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ReferenceSemantics)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    report = {
        'upstream_revision': REVISION,
        'scope': 'Unchanged upstream scalar helper path with test-only framework shims versus the compiled portable implementation; not a full Chromium renderer, Android device or listening-quality test.',
        'compiler': compiler_version,
        'portable_dot_path': PORT.portable_simd_name().decode(),
        'upstream_sources': source_identity,
        'original_library_sha256': hashlib.sha256(original_path.read_bytes()).hexdigest(),
        'portable_library_sha256': hashlib.sha256(port_path.read_bytes()).hexdigest(),
        'portable_source_sha256': hashlib.sha256((NATIVE / 'wsola/wsola.cpp').read_bytes()).hexdigest(),
        'test_methods': result.testsRun,
        'failures': len(result.failures),
        'errors': len(result.errors),
        'seconds': time.monotonic() - started,
        'measurements': MEASUREMENTS,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(f'Reference evidence: {args.report}')
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(main())
