# Glint streaming decoder subset

Source: <https://github.com/CrispStrobe/glint>, commit
`7b458cff0fc9c397f671c422db4770c72fc22f5c` (2026-11-02).
The upstream project declares the MIT license retained in `LICENSE`. The
locally regenerated AAC table data additionally carries Apache-2.0; its exact
source grant and notices are retained under `provenance/vo-aacenc/`.
`UPSTREAM.json` records SHA-256 for every original and retained file; the
reproducible local changes are in `UPSTREAM.patch`.

This subset compiles the MPEG-1/2/2.5 Layer III, AAC-LC and native FLAC frame
decoders and their required tables. It contains no encoder objects, command
line tools, WASM, FFmpeg library or resampler. The upstream FLAC whole-file
convenience function is excluded by `CRISPER_FLAC_FRAME_ONLY`. The table
generator reconstructs the retained header offline during the native-source
audit. The application build never downloads table sources.
The host uses the separate `../../glint_bridge.cpp` bounded-frame ABI.

## Local decoder changes

The AAC patch bounds scalefactor-band and spectral-escape indices, rejects
invalid TNS lengths, incomplete channel data, multi-block ADTS and unsupported
fill extensions (including HE-AAC SBR), and moves the global PNS random state
into each decoder. The bridge seeds PNS by absolute packet ordinal so seeks
and concurrent waveform probes produce consistent noise without sharing
mutable stream state. PNS describes energy rather than a prescribed waveform;
this does not claim bit-identical output to another decoder.

The bridge initializes upstream static Huffman/window tables once before
concurrent decoder creation, checks frame sizes and finite output, and keeps
C++ exceptions inside the C ABI. Dart reads one compressed frame at a time.

The FLAC patch exposes its existing independent frame parser and decoder,
including consumed bytes and absolute sample numbers. It preserves header
CRC8 and complete-frame CRC16 verification, supports FLAC's 36-bit sample
number encoding, bounds predictor output and short-frame warmup, and removes
an upstream 31-bit unary-code restriction that rejected valid Rice residuals.
Signed wasted-bit restoration uses multiplication rather than shifting negative
integers. Only the bounded frame functions are built for this application.

The Dart FLAC path reads STREAMINFO, skips pictures/comments without copying,
and seeks by bounded header search plus CRC-validated frame numbers. It keeps
at most 2 MiB of compressed read-ahead and one PCM block (at most 65,535 frames).
It supports native FLAC with a declared sample count, mono/stereo 4–24-bit PCM,
8–384 kHz and the pinned decoder's supported prediction tools. Unknown-length
FLAC, 32-bit FLAC, negative LPC quantization shifts and Ogg-FLAC are not
supported. Neither opening nor seeking requires whole-file decoding.

## AAC table source and attribution

The current `tools/gen_aac_tables.py` reads only immutable, hash-verified
**vo-aacenc Apache-2.0** inputs. Its `aac_rom.c` supplies codebooks and band
tables; `tns.c` supplies identical TNS limits. All 45 numerical arrays and the
entire C++ body after `#ifndef` remain byte-identical to Glint's original
header. Only attribution comments change. The exact Apache license and both
upstream notices are retained and included in the app's desktop-audio notice.

[The source map and reconstruction record](provenance/AAC_TABLES.md) distinguishes
extracted codebook data from mathematical coefficient checks. It also retains
the separately verified pair of immutable vo-aacenc/FFmpeg revisions that
reproduce the original Glint generator output. That historical reconstruction
does not recover the original invocation. No FFmpeg source is retained, read
by the current generator, or linked into this decoder. This scoped source
record does not assert whole-product distribution approval.

No Opus implementation or libopus-derived table is included in this subset.
The pinned decoder's AAC feature coverage is AAC-LC mono/stereo with supported
tools; unsupported LC tools and HE-AAC fail explicitly. Container extensions
such as `.m4b` do not imply that every codec inside them is supported.
