#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Actual native functional tests; synthetic signals are not a listening-quality verdict."""
from array import array
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import time
import unittest

from dsp import DEFAULT_LIBRARY, ENGINES, Library, render

LIBRARY = None
METRICS = []
IMPULSE_METRICS = []


def tone(sr, frames, channels=1, frequencies=(440, 880)):
    return array('f', (0.2 * math.sin(2 * math.pi * frequencies[c] * i / sr) for i in range(frames) for c in range(channels)))


def frequency(samples, sr, channels, channel):
    values = samples[int(0.15 * sr) * channels + channel:len(samples) - int(0.15 * sr) * channels:channels]
    crossings = [i for i in range(1, len(values)) if values[i - 1] < 0 <= values[i]]
    return (len(crossings) - 1) * sr / (crossings[-1] - crossings[0]) if len(crossings) > 2 else 0


class StreamingTests(unittest.TestCase):
    def test_duration_pitch_and_source_timing_matrix(self):
        for engine in ENGINES:
            for sr in (44100, 48000):
                for channels in (1, 2):
                    samples = tone(sr, sr * 2 + 137, channels)
                    for rate in (0.5, 1, 1.25, 1.5, 2, 3):
                        with self.subTest(engine=engine, sr=sr, channels=channels, rate=rate):
                            started = time.monotonic()
                            with LIBRARY.create(engine, sr, channels, rate) as p:
                                result = render(p, samples)
                                expected = math.floor((len(samples) // channels) / rate + 0.5)
                                self.assertEqual(len(result) // channels, expected)
                                self.assertEqual(p.stat('source_frames'), len(samples) // channels)
                                self.assertEqual(p.stat('output_frames'), expected)
                                self.assertEqual(p.stat('input_frames'), len(samples) // channels)
                                self.assertTrue(all(math.isfinite(v) for v in result))
                                self.assertLess(max(map(abs, result), default=0), 1)
                                frequencies = [frequency(result, sr, channels, c) for c in range(channels)]
                                for c, observed in enumerate(frequencies):
                                    self.assertAlmostEqual(observed, (440, 880)[c], delta=8)
                                METRICS.append({'engine': engine, 'sample_rate': sr, 'channels': channels, 'rate': rate, 'input_frames': p.stat('input_frames'), 'output_frames': expected, 'frequency_hz': frequencies, 'seconds': time.monotonic() - started, 'latency_source_frames': p.stat('latency_frames')})

    def test_unit_rate_is_bit_exact_for_float_and_pcm16(self):
        for engine in ENGINES:
            for channels in (1, 2):
                for code, samples in [('f', tone(48000, 9001, channels)), ('h', array('h', ((i * 977) % 65536 - 32768 for i in range(9001 * channels))))]:
                    with self.subTest(engine=engine, channels=channels, code=code), LIBRARY.create(engine, 48000, channels, 1) as p:
                        self.assertEqual(render(p, samples), samples)

    def test_short_inputs_empty_inputs_and_tiny_chunks(self):
        for engine in ENGINES:
            for rate in (0.5, 1.25, 3):
                for frames in (0, 1, 2, 7, 127, 511, 512, 513, 1000, 4097):
                    with self.subTest(engine=engine, rate=rate, frames=frames), LIBRARY.create(engine, 48000, 1, rate) as p:
                        result = render(p, tone(48000, frames), chunks=(1, 2, 7), read_sizes=(1, 13, 103))
                        self.assertEqual(len(result), math.floor(frames / rate + 0.5))
                        self.assertEqual(p.stat('source_frames'), frames)
                        self.assertTrue(all(math.isfinite(v) for v in result))
                        with self.assertRaises(RuntimeError):
                            p.write(array('f', [0]))

    def test_start_middle_and_end_impulses_survive_at_their_timestamps(self):
        sr, frames = 48000, 96000
        positions = (20, frames // 2, frames - 21)
        for engine in ENGINES:
            for rate in (0.5, 1.25, 1.5, 2, 3):
                with self.subTest(engine=engine, rate=rate), LIBRARY.create(engine, sr, 1, rate) as p:
                    samples = array('f', [0]) * frames
                    for position in positions:
                        samples[position] = 0.8
                    result = render(p, samples)
                    for position in positions:
                        expected = position / rate
                        begin, end = max(0, int(expected - sr * .08)), min(len(result), int(expected + sr * .08) + 1)
                        region = result[begin:end]
                        peak = max(map(abs, region), default=0)
                        IMPULSE_METRICS.append({'engine': engine, 'rate': rate, 'source_frame': position, 'peak': peak})
                        # Sonic can delete isolated samples in skipped pitch periods.
                        # Retain this baseline measurement; require preservation for
                        # the two new native alternatives, not a false Sonic claim.
                        if engine == 'sonic' and peak <= .005:
                            continue
                        self.assertGreater(peak, 0.005)
                        energy = sum(x * x for x in region)
                        center = sum((begin + i) * x * x for i, x in enumerate(region)) / energy
                        self.assertLess(abs(center - expected) / sr, .08)


    def test_sub_lookahead_tone_clips_remain_audible(self):
        for engine in ENGINES:
            for frames in (64, 511, 2048):
                with self.subTest(engine=engine, frames=frames), LIBRARY.create(engine, 48000, 1, 1.5) as p:
                    result = render(p, tone(48000, frames))
                    self.assertGreater(max(map(abs, result), default=0), .005)

    def test_boundary_tones_are_not_replaced_by_priming_or_padding(self):
        sr, frames = 48000, 96000
        samples = array('f', [0]) * frames
        for i in range(int(.15 * sr)):
            samples[i] = .2 * math.sin(2 * math.pi * 440 * i / sr)
            samples[frames - 1 - i] = .2 * math.sin(2 * math.pi * 880 * i / sr)
        for engine in ENGINES:
            for rate in (.5, 1.25, 1.5, 2, 3):
                with self.subTest(engine=engine, rate=rate), LIBRARY.create(engine, sr, 1, rate) as p:
                    result = render(p, samples)
                    window = int(.10 * sr / rate)
                    for region in (result[:window], result[-window:]):
                        rms = math.sqrt(sum(v * v for v in region) / len(region))
                        self.assertGreater(rms, .03)

    def test_arbitrary_chunks_have_identical_native_results(self):
        samples = tone(48000, 48379, 2)
        for engine in ENGINES:
            with self.subTest(engine=engine):
                with LIBRARY.create(engine, 48000, 2, 1.5) as p:
                    tiny = render(p, samples, chunks=(1, 7, 19), read_sizes=(1, 97))
                with LIBRARY.create(engine, 48000, 2, 1.5) as p:
                    large = render(p, samples, chunks=(32768,), read_sizes=(32768,))
                self.assertEqual(tiny, large)

    def test_partial_writes_backpressure_and_only_delivered_source_time(self):
        samples = tone(48000, 48000 * 10)
        for engine in ENGINES:
            with self.subTest(engine=engine), LIBRARY.create(engine, 48000, 1, 1.5) as p:
                accepted = 0
                for _ in range(2000):
                    n = p.write(samples, accepted)
                    accepted += n
                    if n == 0:
                        break
                else:
                    self.fail('Writer did not apply bounded backpressure')
                self.assertLess(accepted, len(samples))
                self.assertEqual(p.stat('source_frames'), 0)
                self.assertEqual(p.stat('output_frames'), 0)
                result = p.read(37)
                self.assertEqual(len(result), 37)
                self.assertEqual(p.stat('source_frames'), 55)
                self.assertEqual(p.stat('output_frames'), 37)
                # Native processing advances by a block/grain, not every sample.
                p.read(16384)
                self.assertGreater(p.write(samples, accepted), 0)

    def test_reset_removes_buffered_old_audio_and_invalid_reset_preserves_state(self):
        for engine in ENGINES:
            with self.subTest(engine=engine), LIBRARY.create(engine, 48000, 2, 1.5) as p:
                old = tone(48000, 20000, 2)
                offset = 0
                while offset < len(old) // 2:
                    offset += p.write(old, offset)
                self.assertGreater(p.stat('available'), 0)
                with self.assertRaises(RuntimeError):
                    p.reset(float('nan'))
                self.assertEqual(p.stat('input_frames'), 20000)
                p.reset(.75)
                self.assertEqual(p.stat('input_frames'), 0)
                self.assertEqual(p.stat('source_frames'), 0)
                self.assertEqual(p.stat('output_frames'), 0)
                fresh = render(p, array('f', [0]) * (48000 * 2))
                self.assertLess(max(map(abs, fresh), default=0), 1e-6)

    def test_invalid_arguments_and_nonfinite_input_are_rejected(self):
        for args in [(99, 48000, 1, 1), ('bungee', 0, 1, 1), ('bungee', 48000, 3, 1), ('signalsmith', 48000, 1, .49), ('signalsmith', 48000, 1, 3.01)]:
            with self.subTest(args=args), self.assertRaises((RuntimeError, TypeError)):
                LIBRARY.create(*args)
        for engine in ENGINES:
            with LIBRARY.create(engine, 48000, 1, 1.5) as p:
                with self.assertRaises(RuntimeError):
                    p.write(array('f', [0, float('nan')]))
                self.assertEqual(p.stat('input_frames'), 0)
                with self.assertRaises(RuntimeError):
                    p.write(array('f', [float('inf')]))
                self.assertEqual(p.stat('input_frames'), 0)

    def test_pcm16_native_output_and_high_sample_rate(self):
        for engine in ENGINES:
            with LIBRARY.create(engine, 48000, 2, 1.5) as p:
                samples = array('h', (round(v * 32767) for v in tone(48000, 48000, 2)))
                result = render(p, samples)
                self.assertEqual(len(result), 64000)
                self.assertGreater(max(result), 1000)
                self.assertLess(max(result), 32767)
            for sr in (8000, 192000):
                for rate in (.5, .75, 3):
                    with self.subTest(engine=engine, sr=sr, rate=rate), LIBRARY.create(engine, sr, 2, rate) as p:
                        result = render(p, tone(sr, 32000, 2))
                        self.assertEqual(len(result), 2 * math.floor(32000 / rate + .5))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, default=DEFAULT_LIBRARY)
    parser.add_argument('--report', type=Path)
    args, tests = parser.parse_known_args()
    LIBRARY = Library(args.library)
    started = time.monotonic()
    suite = unittest.defaultTestLoader.loadTestsFromNames(tests, sys.modules[__name__]) if tests else unittest.defaultTestLoader.loadTestsFromTestCase(StreamingTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    report = {'scope': 'Host streaming correctness and synthetic signal measurements; not perceptual quality or Android device certification', 'library_sha256': hashlib.sha256(args.library.read_bytes()).hexdigest(), 'test_methods': result.testsRun, 'failures': len(result.failures), 'errors': len(result.errors), 'seconds': time.monotonic() - started, 'measurements': METRICS, 'isolated_impulse_measurements': IMPULSE_METRICS}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    sys.exit(0 if result.wasSuccessful() else 1)
