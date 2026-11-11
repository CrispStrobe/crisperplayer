#!/usr/bin/env python3
"""Rebuild AAC tables from immutable Apache-2.0 vo-aacenc sources.

Crisper's local adaptation of Glint's MIT generator uses only aac_rom.c and
its TNS-limit companion tns.c at the pinned source revision below. The exact
source files and Apache license/notices are retained in provenance/vo-aacenc.
It does not fetch or read FFmpeg. All numerical initializers are unchanged
from Glint's original header; see provenance/AAC_TABLES.md for the comparison
and the separate historical two-source reproduction evidence.

Run from this vendor directory:
    python tools/gen_aac_tables.py --check

--srcdir permits an alternate directory containing byte-identical pinned
inputs. Inputs must match the recorded SHA-256 values; no network is used.
"""

import argparse
import re
import hashlib
from pathlib import Path

VO_COMMIT = "f23bc0d15467012bab11deb76ad06819140d2ccf"
SOURCE_HASHES = {
    "aac_rom.c": "bebae3b53f4de70055c6328a24e3fc3172f3b15d40eb9e4556d6d8c2d91cb8b6",
    "tns.c": "473d54f31d5ac12529cf0a17caffbe5d6e53cf50849aba109ab1f9ba6d9f77fa",
}


def source_paths(srcdir):
    paths = {}
    for name, expected in SOURCE_HASHES.items():
        path = Path(srcdir) / name
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f"{name}: source SHA-256 {actual} != {expected}")
        paths[name] = path
    return paths


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return text


def extract_array(text, name):
    """Return the flat list of integers in the initializer of `name`."""
    m = re.search(re.escape(name) + r"\s*(?:\[[^\]]*\]\s*)*=\s*\{", text)
    if not m:
        raise KeyError(name)
    depth, i = 1, m.end()
    start = m.end()
    while depth > 0:
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    body = text[start : i - 1]
    return [int(tok, 0) for tok in re.findall(r"0[xX][0-9a-fA-F]+|\d+", body)]


def check_prefix_free(codes, lens, label):
    seen = {}
    for c, l in zip(codes, lens):
        assert 0 < l <= 32 and c < (1 << l), f"{label}: code 0x{c:x} overflows len {l}"
        seen[(c, l)] = seen.get((c, l), 0) + 1
    items = list(zip(codes, lens))
    for i, (c1, l1) in enumerate(items):
        for c2, l2 in items[i + 1 :]:
            if l1 == l2 and c1 == c2:
                raise AssertionError(f"{label}: duplicate codeword")
            lo, hi = ((c1, l1), (c2, l2)) if l1 < l2 else ((c2, l2), (c1, l1))
            if (hi[0] >> (hi[1] - lo[1])) == lo[0]:
                raise AssertionError(f"{label}: 0x{lo[0]:x}/{lo[1]} prefixes 0x{hi[0]:x}/{hi[1]}")
    kraft = sum(2.0 ** -l for l in lens)
    assert kraft <= 1.0 + 1e-9, f"{label}: Kraft sum {kraft} > 1"


def unpack_pair(packed):
    hi = [(v >> 8) & 0xFF for v in packed]
    lo = [v & 0xFF for v in packed]
    return hi, lo


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--srcdir", default=None)
    ap.add_argument("--out", default="src/aac_tables.hpp")
    ap.add_argument("--check", action="store_true", help="verify output without writing")
    args = ap.parse_args()

    srcdir = args.srcdir or Path(__file__).resolve().parent.parent / "provenance/vo-aacenc"
    paths = source_paths(srcdir)
    vo = strip_comments(paths["aac_rom.c"].read_text())
    tns = strip_comments(paths["tns.c"].read_text())

    # ---- spectral codebooks -------------------------------------------------
    sizes = [81, 81, 81, 81, 81, 81, 64, 64, 169, 169, 289]
    dims = [4, 4, 4, 4, 2, 2, 2, 2, 2, 2, 2]
    lavs = [1, 1, 2, 2, 4, 4, 7, 7, 12, 12, 16]
    signed = [1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0]

    spec_bits = [None] * 11
    for pair, (a, b) in ((extract_array(vo, "huff_ltab1_2"), (0, 1)),
                         (extract_array(vo, "huff_ltab3_4"), (2, 3)),
                         (extract_array(vo, "huff_ltab5_6"), (4, 5)),
                         (extract_array(vo, "huff_ltab7_8"), (6, 7)),
                         (extract_array(vo, "huff_ltab9_10"), (8, 9))):
        hi, lo = unpack_pair(pair)
        spec_bits[a], spec_bits[b] = hi, lo
    spec_bits[10] = extract_array(vo, "huff_ltab11")
    spec_codes = [extract_array(vo, f"huff_ctab{k}") for k in range(1, 12)]

    for k in range(11):
        assert len(spec_bits[k]) == sizes[k] == len(spec_codes[k]), f"book{k+1} size"
        check_prefix_free(spec_codes[k], spec_bits[k], f"book{k+1}")

    # ---- scalefactor codebook ----------------------------------------------
    scf_bits = extract_array(vo, "huff_ltabscf")
    scf_codes = extract_array(vo, "huff_ctabscf")
    assert len(scf_bits) == len(scf_codes) == 121
    check_prefix_free(scf_codes, scf_bits, "scf")

    # ---- scalefactor band tables -------------------------------------------
    num_swb_long = extract_array(vo, "sfBandTotalLong")
    num_swb_short = extract_array(vo, "sfBandTotalShort")
    vo_long_off = extract_array(vo, "sfBandTabLongOffset")
    vo_long_tab = extract_array(vo, "sfBandTabLong")
    vo_short_off = extract_array(vo, "sfBandTabShortOffset")
    vo_short_tab = extract_array(vo, "sfBandTabShort")
    assert len(num_swb_long) == len(num_swb_short) == 12
    long_tabs, short_tabs = [], []
    for i in range(12):
        lt = vo_long_tab[vo_long_off[i] : vo_long_off[i] + num_swb_long[i] + 1]
        st = vo_short_tab[vo_short_off[i] : vo_short_off[i] + num_swb_short[i] + 1]
        assert len(lt) == num_swb_long[i] + 1 and lt[0] == 0 and lt[-1] == 1024
        assert len(st) == num_swb_short[i] + 1 and st[0] == 0 and st[-1] == 128
        assert all(a < b for a, b in zip(lt, lt[1:]))
        assert all(a < b for a, b in zip(st, st[1:]))
        long_tabs.append(lt)
        short_tabs.append(st)

    sample_rates = extract_array(vo, "sampRateTab")[:12]
    assert sample_rates == [96000, 88200, 64000, 48000, 44100, 32000,
                            24000, 22050, 16000, 12000, 11025, 8000]

    # ---- TNS ----------------------------------------------------------------
    # Max-band limits come from the same Apache-2.0 source revision's tns.c.
    # Independently check that the mathematical 4-bit TNS coefficient formula
    # matches vo-aacenc's Q31 tnsCoeff4 data, validating the arcsin/sine
    # (de)quantization formula the encoder implements in code:
    #   iqfac(+) = (2^(res-1) - 0.5) / (pi/2), iqfac(-) with + 0.5,
    #   coef = sin(idx / iqfac)
    import math
    tns_long = extract_array(tns, "tnsMaxBandsLongMainLow")
    tns_short = extract_array(tns, "tnsMaxBandsShortMainLow")
    assert len(tns_long) == len(tns_short) == 12
    vo_c4 = extract_array(vo, "tnsCoeff3Borders")  # presence check only
    vo_c4 = extract_array(vo, "tnsCoeff4")
    iqp = (2 ** 3 - 0.5) / (math.pi / 2)
    iqm = (2 ** 3 + 0.5) / (math.pi / 2)
    # vo table order: idx -8..7 (two's complement order 0..7, -8..-1)? Try both
    # orders and require one to match within Q31 rounding.
    def q31(x):
        v = int(round(x * (1 << 31)))
        return max(-(1 << 31), min((1 << 31) - 1, v))
    ref_signed = [q31(math.sin(i / (iqm if i < 0 else iqp)))
                  for i in range(-8, 8)]
    ref_wrapped = [q31(math.sin(i / (iqm if i < 0 else iqp)))
                   for i in list(range(0, 8)) + list(range(-8, 0))]
    vo_signed = [v - (1 << 32) if v >= (1 << 31) else v for v in vo_c4]
    # vo computed the map with fixed-point sine: agree to ~100 Q31 ULPs.
    ok = any(all(abs(a - b) <= 256 for a, b in zip(vo_signed, ref))
             for ref in (ref_signed, ref_wrapped))
    assert ok, "TNS coef formula does not reproduce vo-aacenc tnsCoeff4"

    print("pinned-source checks passed: 11 spectral books, scf book, 12 sfb tables, TNS coef map")

    # ---- emit ---------------------------------------------------------------
    def fmt(vals, per_line=12, hexfmt=False):
        out, line = [], []
        for v in vals:
            line.append(f"0x{v:x}" if hexfmt else str(v))
            if len(line) == per_line:
                out.append("    " + ", ".join(line) + ",")
                line = []
        if line:
            out.append("    " + ", ".join(line) + ",")
        return "\n".join(out)

    h = []
    h.append("// glint - AAC standard tables (GENERATED FILE — do not edit)")
    h.append("// SPDX-License-Identifier: MIT AND Apache-2.0")
    h.append("// Regenerate with: python tools/gen_aac_tables.py")
    h.append("//")
    h.append("// Crisper modification: all table data is extracted exclusively from")
    h.append("// vo-aacenc aac_rom.c and tns.c, immutable revision:")
    h.append(f"// {VO_COMMIT}")
    h.append("// Copyright 2003-2010 VisualOn, Inc. Licensed under Apache-2.0.")
    h.append("// Generated C++ layout and generator: MIT, Glint contributors.")
    h.append("// Exact sources, license and notices: provenance/vo-aacenc/.")
    h.append("// Numerical initializers match the original Glint header exactly;")
    h.append("// no FFmpeg source is read or needed by this regeneration path.")
    h.append("")
    h.append("#ifndef GLINT_AAC_TABLES_HPP")
    h.append("#define GLINT_AAC_TABLES_HPP")
    h.append("")
    h.append("#include <cstdint>")
    h.append("")
    h.append("namespace glint {")
    h.append("namespace aac_tables {")
    h.append("")
    h.append("constexpr int kNumSampleRates = 12;")
    h.append("inline constexpr int kSampleRates[kNumSampleRates] = {")
    h.append(fmt(sample_rates))
    h.append("};")
    h.append("")
    h.append("inline constexpr uint8_t kNumSwbLong[kNumSampleRates] = {")
    h.append(fmt(num_swb_long))
    h.append("};")
    h.append("inline constexpr uint8_t kNumSwbShort[kNumSampleRates] = {")
    h.append(fmt(num_swb_short))
    h.append("};")
    h.append("")
    emitted = {}
    long_names = []
    for i in range(12):
        key = tuple(long_tabs[i])
        if key not in emitted:
            nm = f"kSwbLong_{sample_rates[i]}"
            emitted[key] = nm
            h.append(f"inline constexpr uint16_t {nm}[{len(long_tabs[i])}] = {{")
            h.append(fmt(long_tabs[i]))
            h.append("};")
        long_names.append(emitted[key])
    h.append("inline constexpr const uint16_t* kSwbOffsetLong[kNumSampleRates] = {")
    h.append("    " + ", ".join(long_names) + ",")
    h.append("};")
    h.append("")
    emitted = {}
    short_names = []
    for i in range(12):
        key = tuple(short_tabs[i])
        if key not in emitted:
            nm = f"kSwbShort_{sample_rates[i]}"
            emitted[key] = nm
            h.append(f"inline constexpr uint16_t {nm}[{len(short_tabs[i])}] = {{")
            h.append(fmt(short_tabs[i]))
            h.append("};")
        short_names.append(emitted[key])
    h.append("inline constexpr const uint16_t* kSwbOffsetShort[kNumSampleRates] = {")
    h.append("    " + ", ".join(short_names) + ",")
    h.append("};")
    h.append("")
    h.append("// Spectral Huffman codebooks 1-11 (index 0 = book 1).")
    h.append("// dim: coefficients per codeword; lav: largest absolute value;")
    h.append("// signed: table indices span [-lav, lav] (no sign bits) vs [0, lav] + sign bits.")
    h.append("inline constexpr uint8_t kBookDim[11]    = { " + ", ".join(map(str, dims)) + " };")
    h.append("inline constexpr uint8_t kBookLav[11]    = { " + ", ".join(map(str, lavs)) + " };")
    h.append("inline constexpr uint8_t kBookSigned[11] = { " + ", ".join(map(str, signed)) + " };")
    h.append("inline constexpr uint16_t kBookSize[11]  = { " + ", ".join(map(str, sizes)) + " };")
    h.append("")
    for k in range(11):
        h.append(f"inline constexpr uint8_t kSpecBits{k+1}[{sizes[k]}] = {{")
        h.append(fmt(spec_bits[k], 16))
        h.append("};")
        h.append(f"inline constexpr uint16_t kSpecCodes{k+1}[{sizes[k]}] = {{")
        h.append(fmt(spec_codes[k], 8, hexfmt=True))
        h.append("};")
    h.append("")
    h.append("inline constexpr const uint8_t* kSpecBits[11] = {")
    h.append("    " + ", ".join(f"kSpecBits{k+1}" for k in range(11)) + ",")
    h.append("};")
    h.append("inline constexpr const uint16_t* kSpecCodes[11] = {")
    h.append("    " + ", ".join(f"kSpecCodes{k+1}" for k in range(11)) + ",")
    h.append("};")
    h.append("")
    h.append("// TNS: max scalefactor bands the filter may cover (long/short windows).")
    h.append("inline constexpr uint8_t kTnsMaxBandsLong[kNumSampleRates] = {")
    h.append(fmt(tns_long))
    h.append("};")
    h.append("inline constexpr uint8_t kTnsMaxBandsShort[kNumSampleRates] = {")
    h.append(fmt(tns_short))
    h.append("};")
    h.append("")
    h.append("// Scalefactor codebook: index = dpcm + 60, dpcm in [-60, 60].")
    h.append("inline constexpr uint8_t kScfBits[121] = {")
    h.append(fmt(scf_bits, 16))
    h.append("};")
    h.append("inline constexpr uint32_t kScfCodes[121] = {")
    h.append(fmt(scf_codes, 8, hexfmt=True))
    h.append("};")
    h.append("")
    h.append("} // namespace aac_tables")
    h.append("} // namespace glint")
    h.append("")
    h.append("#endif // GLINT_AAC_TABLES_HPP")

    generated = "\n".join(h)
    if args.check:
        if Path(args.out).read_bytes() != generated.encode("utf-8"):
            raise ValueError(f"generated table header differs: {args.out}")
        print(f"verified {args.out}")
    else:
        Path(args.out).write_bytes(generated.encode("utf-8"))
        print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
