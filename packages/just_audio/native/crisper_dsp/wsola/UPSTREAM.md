# Chromium WSOLA: maintained portable extraction

The WSOLA implementation in this directory derives its matching and
overlap-add behavior from Chromium. The compiled portable implementation lives
in `wsola.h` and `wsola.cpp`; CrisperPlayer's existing streaming adapter supplies
bounded input/output queues and its source-frame clock.

## Exact source identity

- Upstream: <https://chromium.googlesource.com/chromium/src.git>
- Retrieval mirror: <https://github.com/chromium/chromium>
- Revision: `ddd30ef8aa98443509bf4ce006cb36b4e2296c0b` (7 October 2026).
- Commit tree: `b0be693632ea3df0aedf514bb577ce5fce9b1e37`.
- License: **BSD-3-Clause**, with the original Chromium copyright, conditions
  and disclaimer retained. The original `LICENSE` SHA-256 is
  `368cca1106be99d39ecd32a38d8305585d802a475effb66380b91ffc9bcf709b`.

The six exact originals are retained under `../vendor/chromium-wsola/` and
listed in `../vendor/manifest.json`. Each source has an immutable URL, upstream
path, Git blob object ID and SHA-256. Their Git blob IDs were checked against
the upstream commit's tree, including the Git blob header and exact byte count.
The provenance method is an exact-file snapshot; no downloaded archive or
archive hash is asserted.

The selected revision includes Chromium's AVX2 dot-product reduction fix.
It corrected the omission of the upper four lanes during horizontal summation.
Our tests retain an asymmetric eight-lane sum case even when the portable
implementation selects a different vector or scalar path.

## Origin map

| Original file | Role in this extraction |
| --- | --- |
| [`LICENSE`](https://chromium.googlesource.com/chromium/src.git/+/ddd30ef8aa98443509bf4ce006cb36b4e2296c0b/LICENSE) | Full upstream BSD grant and notice. |
| [`media/filters/wsola_internals.cc`](https://chromium.googlesource.com/chromium/src.git/+/ddd30ef8aa98443509bf4ce006cb36b4e2296c0b/media/filters/wsola_internals.cc) | Per-channel dot products and normalized similarity, sliding block energy, quadratic peak interpolation, decimated search, local full-search refinement and periodic Hann window. |
| [`media/filters/wsola_internals.h`](https://chromium.googlesource.com/chromium/src.git/+/ddd30ef8aa98443509bf4ce006cb36b4e2296c0b/media/filters/wsola_internals.h) | Original helper contracts and interval/window definitions. |
| [`media/filters/audio_renderer_algorithm.cc`](https://chromium.googlesource.com/chromium/src.git/+/ddd30ef8aa98443509bf4ce006cb36b4e2296c0b/media/filters/audio_renderer_algorithm.cc) | Documented WSOLA iteration, 20 ms overlap window, 10 ms output hop, 30 ms search interval, natural-continuation target, transition blend and overlap-add sequencing. |
| [`media/filters/audio_renderer_algorithm.h`](https://chromium.googlesource.com/chromium/src.git/+/ddd30ef8aa98443509bf4ce006cb36b4e2296c0b/media/filters/audio_renderer_algorithm.h) | Reference for original buffering and state semantics. |
| [`media/filters/audio_renderer_algorithm_unittest.cc`](https://chromium.googlesource.com/chromium/src.git/+/ddd30ef8aa98443509bf4ce006cb36b4e2296c0b/media/filters/audio_renderer_algorithm_unittest.cc) | Synthetic dot-product, block-energy, search and interpolation fixture origins. |

The build compiles the portable extraction. Chromium's browser renderer,
`AudioBus`, `base` infrastructure, decoder, CPU-dispatch machinery and unrelated
third-party dependencies are outside its compilation closure. The BSD notice
covers the derived implementation; the independently written C ABI adapter
retains its MIT grant. Chromium is an external component and does not use the
application-owner licensing exemption.

## Maintained changes

The port adapts Chromium's planar-buffer operations to a small owned PCM view,
keeps one matching displacement for all channels, and preallocates working
storage. Its scheduler uses bounded buffers and 64-bit source coordinates.
Matching time is separate from the delivered-output source clock: a search
offset changes the waveform splice, while accepted input and delivered output
continue to determine the exact playback timeline.

Dot products use the compiler's baseline SSE2 or NEON path when available,
with a scalar fallback; Chromium's runtime CPU dispatch and AVX2 implementation
are not copied into the port. Coarse search retains the five-frame spacing and
quadratic peak estimate, explicitly evaluates the proposed candidate and
endpoints, then refines within five frames. Tied scores prefer the requested
search center. Window construction and energy accumulation use double
precision before storing float PCM/window values.

The extraction explicitly addresses edge conditions in the selected source:

- A valid negative correlation may win. The search uses an actual valid
  candidate and a lowest-score baseline, rather than a positive
  `numeric_limits<float>::min()` fallback to index zero.
- Excluded candidates cannot become the initial or fallback winner. Exclusion
  offsets retain signed bounds so intervals crossing zero do not wrap to a
  large unsigned position.
- Sliding-energy roundoff cannot feed a negative energy to a square root.
  Silence and near-silence retain finite, deterministic search behavior.
- The adapter defines short-input, beginning/end padding, finite drain and
  exact output-length behavior for a standalone streaming processor. Seeking
  or resetting discards previous overlap/search/output state.
- The first WSOLA hop uses the source samples directly, avoiding a fade
  against a fictitious preceding silent grain.

The independently written streaming adapter also reserves one source hop
beyond the mapped live output endpoint. At end of stream it blends the final
output segment (at most one hop) toward the actual final source segment with
complementary half-cosine weights. This makes the final output frame agree
with the final source frame whenever rounded output length is nonzero,
including tiny clips and partial hops. The rule is independent of signal
content and uses the same weight for every channel. It is a standalone
boundary policy, not behavior asserted to match Chromium's renderer.

These maintenance changes and the standalone queue lifecycle mean Chromium
bit-for-bit output identity is not a compatibility claim. The retained
synthetic fixtures check the inherited mathematical semantics, while streaming
tests separately check duration, pitch, channel coherence, chunk independence,
boundaries, drain, reset and source-clock behavior.

## Semantic and streaming acceptance

The minimum semantic cases are the original asymmetric dot-product sum,
opposed/correlated channels, sliding-energy values, the two-channel search
fixture (including an excluded best match), and flat/non-flat interpolation.
Additional cases cover all-negative correlations, signed exclusion bounds,
silent/low-energy inputs and a single permitted candidate.

Run `python3 packages/just_audio/native/crisper_dsp/tools/test_wsola_reference.py`
from the repository root for the preserved original-versus-port comparison.
It verifies retained source hashes, compiles the unchanged upstream helper's
scalar path with small test-only framework shims, and compares it with the
production port's normal SIMD/scalar implementation. The test-only interfaces,
fixture attribution, intentional differences and evidence report are described
in `../tools/wsola_reference/README.md`; none of these shims is an app dependency.

The native streaming suite must run WSOLA through the same rate/channel/sample
rate matrix as the other processors, including exact unity pass-through,
fractional rates, small input/output chunks, finite empty/short/tail drains,
partial-write backpressure and reset isolation. Source-frame accounting must
remain monotonic and bounded by accepted input, with final output rounded to
the requested duration. Long-coordinate cases must not overflow a 32-bit
index or make the matching search drift with call chunk size.

These checks establish the implemented signal and transport contracts. Sound
preference, high-rate speech intelligibility, real-device CPU/battery use and
the full Android output path need listening and device measurements.
