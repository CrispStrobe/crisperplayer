# WSOLA reference comparison

From the repository root, run:

```sh
python3 packages/just_audio/native/crisper_dsp/tools/test_wsola_reference.py
```

This needs Python's standard library and a C++20 compiler (`CXX` or
`--compiler`, default `c++`). It builds two small host libraries in the ignored
`build/native-dsp/wsola-reference/` directory and writes
`build/native-dsp/wsola-reference-report.json`. `--build-dir` and `--report`
override those paths. There is no network download or extra package dependency.

The reference library compiles the **unchanged** pinned
`vendor/chromium-wsola/media/filters/wsola_internals.cc`. Before compilation the
runner verifies every retained Chromium source's SHA-256 and Git blob identity
against the vendor manifest. Updating the pinned revision requires reviewing
the fixtures and updating the runner's revision guard.

## Test boundary

The `shims/` directory supplies only the framework interfaces used by these
helpers: planar owned channel arrays, `std::span`, assertions and the bounded
checked subtraction used by valid fixtures. Architecture macros are left
undefined deliberately, selecting Chromium's scalar dot-product function. The
shim is not a replacement implementation of Chromium's algorithms, general
`base` library or `AudioBus` behavior. It must not enter an app build.

The second library includes the production portable source unchanged in a
test-only translation unit. This makes its internal dot product and Hann
window available for comparison, alongside the public search object. Its
normal compile-time SIMD selection remains active: SSE2, NEON or scalar. The
report records the selected path. Small documented tolerances allow different
floating-point accumulation order and the port's double-precision window
construction; output bit identity is not required.

The twelve tests cover asymmetric vector sums, 99 dot-product remainder
lengths, the original stereo search fixture and excluded match, a shared
opposite-polarity stereo match, Hann overlap complement, signed exclusions,
silence tie-breaking and the deliberate negative-correlation fallback fix.
Original-only block-energy and interpolation fixtures also check the behavior
of the compiled reference/shim setup; they are not represented as direct
comparisons of standalone portable functions. The port integrates those
operations into its search routine.

The fixture derived from upstream `FullSearch` deliberately observes its
excluded-index-zero fallback for all-negative scores, then requires the port
to select a valid negative candidate. That is an intentional maintenance
difference. The test runner does not require random search outputs or full
renderer output to be identical across implementations.

This suite does not exercise Chromium's AVX2 implementation, its browser
renderer, the streaming queues, JNI/Media3, an Android device, or perceptual
audio quality. Run the separate streaming suite for duration, source clocks,
stereo output, reset, short-input and end-of-stream contracts.

## Attribution

The search/energy/interpolation fixtures in `test_wsola_reference.py` derive
from Chromium's `audio_renderer_algorithm_unittest.cc` at revision
`ddd30ef8aa98443509bf4ce006cb36b4e2296c0b` and retain BSD-3-Clause attribution.
The full notice is preserved in `../../vendor/chromium-wsola/LICENSE`.
The bridge and compatibility shims are independently written MIT test support;
they do not change the BSD license of the sources included in the test builds.
