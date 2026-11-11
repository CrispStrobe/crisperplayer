# Glint streaming decoder subset

Source: <https://github.com/CrispStrobe/glint>, commit
`7b458cff0fc9c397f671c422db4770c72fc22f5c` (2026-11-02).
The upstream project declares the MIT license retained in `LICENSE`.
`UPSTREAM.json` records SHA-256 for every original and retained file; the
reproducible local changes are in `UPSTREAM.patch`.

This subset compiles the MPEG-1/2/2.5 Layer III and AAC-LC decoder classes and
their required tables. It contains no encoder objects, command line tools,
WASM, FFmpeg library, resampler, or whole-file decoding helpers. The table
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
