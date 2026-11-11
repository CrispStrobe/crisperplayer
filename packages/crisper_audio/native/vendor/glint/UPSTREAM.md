# Glint streaming decoder subset

Source: <https://github.com/CrispStrobe/glint>, commit
`7b458cff0fc9c397f671c422db4770c72fc22f5c` (2026-11-02).
The upstream project declares the MIT license retained in `LICENSE`.
`UPSTREAM.json` records SHA-256 for every original and retained file; the
reproducible local changes are in `UPSTREAM.patch`.

This subset compiles the MPEG-1/2/2.5 Layer III, AAC-LC and native FLAC frame
decoders and their required tables. It contains no encoder objects, command
line tools, WASM, FFmpeg library or resampler. The upstream FLAC whole-file
convenience function is excluded by `CRISPER_FLAC_FRAME_ONLY`. The table
generator is retained as provenance evidence and is never run by the build.
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

## AAC table provenance remains unresolved

The retained `src/aac_tables.hpp` and `tools/gen_aac_tables.py` describe
normative AAC tables extracted and cross-checked from **vo-aacenc
(Apache-2.0)** and **FFmpeg libavcodec**. The generator uses moving upstream
branches rather than immutable extraction revisions. The Glint MIT headline
does not, by itself, establish attribution requirements or clear derived-table
licensing. This integration preserves that evidence and makes no claim of
distribution approval. It introduces no linked FFmpeg or LGPL runtime.

No Opus implementation or libopus-derived table is included in this subset.
The pinned decoder's AAC feature coverage is AAC-LC mono/stereo with supported
tools; unsupported LC tools and HE-AAC fail explicitly. Container extensions
such as `.m4b` do not imply that every codec inside them is supported.
