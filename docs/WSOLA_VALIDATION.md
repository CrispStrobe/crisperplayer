# WSOLA fork: implementation and validation

Recorded 10 November 2026. The Android app now offers **WSOLA** under
**Speed → Speed processing**. Selection applies after restart; Sonic stays the
default. WSOLA uses native engine ID `3`, preserving all existing stored values
and processor IDs. The portable core and comparison renderer run on the host;
iOS/macOS still use AVFoundation and desktop still uses its existing backend.

## What is maintained here

The compiled fork is in
[`packages/just_audio/native/crisper_dsp/wsola`](../packages/just_audio/native/crisper_dsp/wsola).
It derives from Chromium revision
`ddd30ef8aa98443509bf4ce006cb36b4e2296c0b`, retaining **BSD-3-Clause** attribution.
The six unchanged source/license originals have both SHA-256 hashes and Git
blob IDs, verified against the upstream Git tree. The complete origin map and
intentional differences are in the [fork provenance](../packages/just_audio/native/crisper_dsp/wsola/UPSTREAM.md).

Only the portable matching, windowing and overlap-add implementation enters the
app. The original Chromium renderer and test-only framework shims do not.
The independent streaming/JNI adapter remains MIT. This addition does not use
an external GPL/AGPL grant or an application-owner license exception.

The fork includes per-channel correlation with shared stereo alignment,
bounded preallocated working buffers, compile-time SSE2/NEON/scalar dot products,
64-bit positions, signed exclusions and valid negative-score fallback. A unity
rate uses the existing exact PCM bypass. Delivered output drives the source
clock, preserving recording coordinates for resume and listening memory.

## Verification performed

| Check | Observed result | Scope |
| --- | --- | --- |
| Native streaming suite | 15 test methods passed; 96 rate/channel/sample-rate cases | Actual four-engine C/C++ library, GCC 14.2, Linux host |
| Portable WSOLA search regressions | 8 checks passed | Actual compiled search implementation |
| Preserved-original reference comparison | 12 test methods passed | Unchanged Chromium scalar helper with test-only shims versus production SSE2 helper |
| Android Java/Media3 lifecycle | 11 tests passed | Complete plugin Java compilation and actual Media3 1.4.1 pipeline on host JVM |
| Actual JNI/native execution | 5 tests passed | Real JNI bridge linked to the final core; no processor test double |
| Flutter configuration and speed controls | 25 tests passed | Android/Apple method-channel transport, settings and accessible UI |
| Full Flutter analysis | No issues | Resolved app and local package |
| Repository Python suite | 93 tests passed | Includes 37 license/source-checker and 22 APK-audit tests |
| Four-engine comparison render | All produced exactly 192,000 frames from 288,000 input frames at 1.5×; zero saturated PCM samples | Synthetic tones/transients, not a speech-quality assessment |

The 96-case matrix covers four processors, 44.1/48 kHz, mono/stereo, and
0.5×, 1×, 1.25×, 1.5×, 2× and 3×. Additional tests cover 8/192 kHz,
fractional rates, tiny/empty clips, arbitrary input/output chunks, pitch,
backpressure, exact PCM16/float unity, finite drain, reset isolation and source
clocks excluding queued input. WSOLA-specific cases cover opposite-phase stereo,
a silent first channel, quiet/DC/silent input and complete/partial final hops.
The Flutter widget test also selects WSOLA at 320 px width and 200% text size.

The reference comparison preserves the original stereo search fixture,
asymmetric dot sum, 99 dot-product remainder lengths, energy/interpolation
fixtures and Hann complement. It separately verifies intentional changes such
as choosing a valid negative-score candidate instead of an excluded index zero.
It does not assert full Chromium renderer output or random search bit identity.

The final tested core SHA-256 is
`4e28d4f77bd41771344deeca4deb26295dbf912f3971a9d4b31b3ef3b9b00652`.
The final host JNI bridge SHA-256 is
`e607a13cbac33d5df344014c7bd21bd359ce0909be940ceac1c5f411d6fe0257`.
The [recorded evidence](../licensing/evidence/wsola_host_2026-11-10.json)
contains source and binary hashes, commands, measurements and explicit scope.

## End-of-stream correction

An initial implementation could omit an isolated marker in the final source
frames at accelerated rates. The corrected adapter holds enough input ahead
of each live output hop to know the end before committing the final hop. At
EOS, it blends the ordinary WSOLA continuation into the real ending segment
with complementary half-cosine weights and reaches the actual last sample.
The rule depends on the boundary, not on detecting or transplanting a marker.

The correction keeps output duration exact and remains independent of chunk
sizes. The maximum blend lasts one output hop, approximately 10 ms. Media3 may
drain a segment when changing speed, so listening checks should include those
transitions as well as track endings. Synthetic tests establish timing and
boundary handling; they cannot establish that every splice is inaudible.

## Host workload observations

Two seconds of synthetic stereo input produced these measured render times,
including the Python/ctypes transport overhead:

| Input | Rate | Render time |
| --- | --- | --- |
| 48 kHz stereo | 0.75× | 0.0119 s |
| 48 kHz stereo | 3.00× | 0.0124 s |
| 192 kHz stereo | 1.50× | 0.1065 s |

These are single host observations, not Android CPU/battery figures or a
comparative quality ranking. Device architecture, thermal state, decoder load,
background playback and output buffering can change the result.

## Reproduce

From the repository root, with Python 3 and a C/C++20 toolchain:

```sh
python3 packages/just_audio/native/crisper_dsp/tools/build_host.py --jobs 2
python3 packages/just_audio/native/crisper_dsp/tools/test_streaming.py \
  --library build/native-dsp/libcrisper_dsp.so \
  --report build/native-dsp/test-report.json
python3 packages/just_audio/native/crisper_dsp/tools/test_wsola_reference.py
python3 packages/just_audio/native/crisper_dsp/tools/render_ab.py \
  --input /absolute/path/passage.wav --output-dir build/dsp-ab --rate 1.5
```

The renderer accepts mono/stereo signed PCM16 WAV and writes the same passage
through Sonic C, Bungee Basic, Signalsmith Stretch and WSOLA. Omitting `--input`
uses explicitly labeled synthetic material. Sonic C is a comparison baseline,
not a bit-exact reproduction of the Android Media3 default.

The [Android workflow](../.github/workflows/android-audio.yml) runs the native
and reference checks, APK builds/inspection and emulator JNI tests. Its SDK
setup now requests `platform-tools` explicitly because the action's previous
default also requested the retired package named `tools`.

## Remaining validation boundaries

The host passes do not certify an Android APK, full ExoPlayer/AudioTrack output
path, subjective speech quality or App Store distribution. Android artifact
and runtime evidence remains separate in the license inventory and exact
commit's CI results. WSOLA remains experimental; skip silence is available with
Sonic, while saved skip-silence preferences are retained in native modes.

Before changing the default, compare real narration at the speeds people use,
including consonants, first/last words, mixed music, stereo, seeking, parameter
changes, interruptions and battery use. The source is now available to maintain
and improve without adding Chromium's runtime dependency graph.
