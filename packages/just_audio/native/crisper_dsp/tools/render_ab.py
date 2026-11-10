#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Render the same PCM16 WAV through pinned Sonic, Bungee Basic and Signalsmith.

The outputs share one source; adjust listening loudness equally when comparing. Synthetic input
is a reproducible engineering fixture, not a speech-quality benchmark. This tool
uses the actual streaming adapter and has no FFmpeg or codec dependency.
"""
from array import array
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import time
import wave

from dsp import DEFAULT_LIBRARY, ENGINES, Library


def make_fixture(path):
    sr, seconds = 48000, 6
    samples = array('h')
    # Alternating harmonic bursts, isolated transient markers and silence expose
    # onset/tail behavior. These are generated tones, not synthesized speech.
    for i in range(sr * seconds):
        t = i / sr
        envelope = .45 * max(0, math.sin(2 * math.pi * 2.7 * t)) ** 2
        fundamental = 150 + 35 * math.sin(2 * math.pi * .3 * t)
        value = envelope * (math.sin(2 * math.pi * fundamental * t) + .25 * math.sin(4 * math.pi * fundamental * t))
        if 2 < t < 2.4 or 4 < t < 4.3:
            value = 0
        if i in (20, sr * 3, sr * seconds - 21):
            value = .8
        samples.append(round(32767 * value))
    if sys.byteorder != 'little':
        samples.byteswap()
    with wave.open(str(path), 'wb') as target:
        target.setparams((1, 2, sr, 0, 'NONE', 'not compressed'))
        target.writeframes(samples.tobytes())


def render_file(library, source, target, engine, rate):
    started = time.perf_counter()
    peak = clipped = output_frames = input_frames = 0
    with wave.open(str(source), 'rb') as original:
        if original.getsampwidth() != 2 or original.getcomptype() != 'NONE':
            raise ValueError('Input must be uncompressed signed PCM16 WAV')
        channels, sr = original.getnchannels(), original.getframerate()
        with library.create(engine, sr, channels, rate) as processor, wave.open(str(target), 'wb') as result:
            result.setparams((channels, 2, sr, 0, 'NONE', 'not compressed'))

            def drain():
                nonlocal peak, clipped, output_frames
                values = processor.read(4096, pcm16=True)
                if not values:
                    return 0
                output_frames += len(values) // channels
                peak = max(peak, max(map(abs, values)))
                clipped += sum(v in (-32768, 32767) for v in values)
                if sys.byteorder != 'little':
                    values.byteswap()
                result.writeframesraw(values.tobytes())
                return len(values) // channels

            while data := original.readframes(4096):
                values = array('h')
                values.frombytes(data)
                if sys.byteorder != 'little':
                    values.byteswap()
                offset = 0
                frames = len(values) // channels
                while offset < frames:
                    count = processor.write(values, offset)
                    offset += count
                    input_frames += count
                    delivered = drain()
                    if not count and not delivered:
                        raise RuntimeError('Native stream stopped making progress')
            processor.finish()
            for _ in range(4096):
                if processor.stat('ended'):
                    break
                drain()
            else:
                raise RuntimeError('Native end-of-stream drain did not finish')
            source_frames = processor.stat('source_frames')
    expected = math.floor(input_frames / rate + .5)
    if output_frames != expected or source_frames != input_frames:
        raise RuntimeError('Native frame accounting did not preserve source duration')
    return {
        'engine': engine, 'rate': rate, 'sample_rate': sr, 'channels': channels,
        'input_frames': input_frames, 'output_frames': output_frames,
        'output_seconds': output_frames / sr,
        'render_seconds': time.perf_counter() - started,
        'peak_pcm16': peak, 'saturated_samples': clipped,
        'file': target.name, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, default=DEFAULT_LIBRARY)
    parser.add_argument('--input', type=Path, help='Your uncompressed mono/stereo PCM16 WAV; otherwise generate a synthetic fixture')
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--rate', type=float, default=1.5)
    parser.add_argument('--engine', choices=list(ENGINES), action='append')
    args = parser.parse_args()
    if not math.isfinite(args.rate) or not .5 <= args.rate <= 3:
        parser.error('--rate must be 0.5..3.0')
    args.output_dir.mkdir(parents=True, exist_ok=True)
    source = args.input
    generated = source is None
    if generated:
        source = args.output_dir / 'synthetic-input.wav'
        make_fixture(source)
    library = Library(args.library)
    results = []
    for engine in args.engine or ENGINES:
        name = f'{source.stem}-{engine}-{args.rate:g}x.wav'
        target = args.output_dir / name
        if target.resolve() == source.resolve():
            raise ValueError('Output would overwrite the input')
        results.append(render_file(library, source, target, engine, args.rate))
    report = {
        'scope': 'Same-input actual native DSP render; no automatic perceptual ranking',
        'input_kind': 'synthetic tones/transients; not speech' if generated else 'user-supplied PCM16 WAV',
        'input': str(source), 'input_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'library_sha256': hashlib.sha256(args.library.read_bytes()).hexdigest(),
        'notes': [
            'Sonic C comparison is not a bit-exact replica of Android Media3 Sonic.',
            'Signalsmith is recommended upstream mainly for moderate time stretch; inspect speech at your chosen rate.',
            'Listen at equal loudness, including first/last words, consonants, breaths, music, stereo image and rapid speed changes.',
        ],
        'results': results,
    }
    (args.output_dir / 'render-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
