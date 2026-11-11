# AAC table provenance and reproducible Apache source selection

The current table generator reads **only two immutable Apache-2.0 source
files** from vo-aacenc. Every numerical initializer matches Glint's original
header. Its C++ body, beginning at `#ifndef`, is byte-identical: **45 numerical
arrays containing 3,229 values**. Only the generated attribution comments change.
The machine-readable input identities, hashes, per-array fingerprints and
comparison results are in [aac_tables.json](aac_tables.json).

## Current inputs

Both source files are pinned to vo-aacenc revision
[`f23bc0d15467012bab11deb76ad06819140d2ccf`](https://github.com/mstorsjo/vo-aacenc/tree/f23bc0d15467012bab11deb76ad06819140d2ccf).
The retained copies also match the Git blob IDs in that revision's tree.

| Retained input | Immutable primary source | SHA-256 |
| --- | --- | --- |
| `vo-aacenc/aac_rom.c` | [aacenc/src/aac_rom.c](https://github.com/mstorsjo/vo-aacenc/blob/f23bc0d15467012bab11deb76ad06819140d2ccf/aacenc/src/aac_rom.c) | `bebae3b53f4de70055c6328a24e3fc3172f3b15d40eb9e4556d6d8c2d91cb8b6` |
| `vo-aacenc/tns.c` | [aacenc/src/tns.c](https://github.com/mstorsjo/vo-aacenc/blob/f23bc0d15467012bab11deb76ad06819140d2ccf/aacenc/src/tns.c) | `473d54f31d5ac12529cf0a17caffbe5d6e53cf50849aba109ab1f9ba6d9f77fa` |

Their headers identify Copyright 2003–2010 VisualOn, Inc. and Apache-2.0.
The exact [COPYING](vo-aacenc/COPYING), [root NOTICE](vo-aacenc/NOTICE), and
[aacenc NOTICE](vo-aacenc/AACENC_NOTICE) are retained. The root notice contains
an unrelated Unicode notice and is preserved unabridged; no Unicode code or
data is selected. These source files are generator evidence and are not
compiled into the audio library.

The generated header carries `MIT AND Apache-2.0`: Glint's generator/C++ layout
keeps its MIT grant, and the extracted table data is explicitly attributed to
the Apache sources. The current source selection does not rely on treating
the tables as uncopyrightable or on inferring a license from their numerical
identity. It carries the source grant and notices.

## What is extracted and what is calculated

| Output | Operation and source |
| --- | --- |
| 11 spectral Huffman codebooks | Copy `huff_ctab1`–`huff_ctab11` from `aac_rom.c`. |
| Spectral codeword lengths | Split packed high/low bytes of `huff_ltab1_2`–`huff_ltab9_10`; copy `huff_ltab11`. |
| Scalefactor Huffman book | Copy `huff_ctabscf` and `huff_ltabscf`. |
| Scalefactor-band counts and offsets | Slice `sfBandTabLong`/`Short` using their offset arrays and counts. |
| Sample-rate table | Take the first twelve `sampRateTab` entries. |
| TNS band limits | Copy `tnsMaxBandsLongMainLow` and `tnsMaxBandsShortMainLow` from `tns.c`. Both match the original header exactly. |
| Book dimensions, sizes and signedness | Keep Glint's existing format descriptors unchanged. |
| TNS coefficient quantization | Verify the sine-based formula against `tnsCoeff4`; no extracted coefficient table is emitted. |

The Huffman and band tables are extracted normative data, **not newly invented
by a mathematical generator**. Prefix-freeness, lengths, ordered offsets and
TNS formula checks validate the extraction; they do not create the codebooks.

Run from the Glint vendor directory:

```sh
python3 tools/gen_aac_tables.py --check
```

This is fully offline. The script verifies both input SHA-256 values before
parsing and compares the complete generated header with the retained output.
It does not read, download or require an FFmpeg file. A mismatched input or
output fails verification. A normal application build uses the retained
header; the native-source audit repeats this reconstruction check.

## Historical evidence, kept separate

Glint first added its AAC table generator/header in
[`059d235bd32e3f6aad84bb5b836906a6bd53336d`](https://github.com/CrispStrobe/glint/commit/059d235bd32e3f6aad84bb5b836906a6bd53336d)
and added TNS limits in
[`3f6208299962d87eec7a0f37683b1a6ccbc888f2`](https://github.com/CrispStrobe/glint/commit/3f6208299962d87eec7a0f37683b1a6ccbc888f2).
The original script downloaded mutable `master` URLs from vo-aacenc and
FFmpeg and asserted that matching normative tables were identical.

On 2026-11-11, the **unmodified** pinned Glint generator reproduced its original
header byte-for-byte from the vo-aacenc `aac_rom.c` pin above and
[FFmpeg `aactab.c` at `044bfc7785650102f1e3e27868dc40b023d90d5f`](https://github.com/FFmpeg/FFmpeg/blob/044bfc7785650102f1e3e27868dc40b023d90d5f/libavcodec/aactab.c).
The reproduced original header SHA-256 is
`df0118f458bb3e0e1b92ecc276b4fb75bed27dde51996a9e8b882006a6dafc51`.
That FFmpeg source declares LGPL-2.1-or-later; its hash and immutable URL are
recorded as historical reproduction evidence. The file is not retained here
and is not an input to the current generator or application build.

This establishes a **reproducing pair of revisions**, not the historical
developer's exact download time or invocation. The original Glint file hashes
remain in `UPSTREAM.json`, and `UPSTREAM.patch` preserves the local correction
from those originals. The present evidence addresses the selected table source
and its notices; it does not assert whole-product distribution approval or
resolve unrelated codec patent questions.
