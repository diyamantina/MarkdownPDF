# Pure-Swift DEFLATE / FlateDecode encoder

Date: 2026-06-02

Issue: #127

## Scope

This note researches and records how MarkdownPDF implements a Pure Swift DEFLATE
compressor so that PDF content streams and embedded `FontFile2` TrueType programs
can be written with `/Filter /FlateDecode`. The first shipped profile adds an
opt-in compression backend without changing the existing output by default.

The decoder (inflate) is out of scope for the product: the renderer only writes
PDFs, it does not read them. The current implementation keeps a small internal
Pure Swift inflate helper for round-trip tests; it is not public API and is not
used by rendering.

## Product boundary

- Pure Swift, buildable on Linux and macOS. Same input must produce
  byte-identical output on both platforms.
- NO `zlib`, `libz`, Apple `Compression` framework, or any C / third-party
  compression library in the production path. Cited open-source projects below
  are STUDY references to reimplement in Swift, NOT dependencies. Each carries a
  license note.
- A third-party inflater MAY be used in TESTS ONLY for round-trip checks
  (compress in Swift, inflate with the oracle, compare to original input).
- Compression stays opt-in until the encoder is proven by witnesses. Default
  output continues to emit uncompressed streams, matching the existing
  `FontFile2` profile in `portable-embedded-fonts-tounicode-plan.md`, which
  explicitly leaves compression off "until the project has a pure Swift
  compression policy."
- This work produces raw DEFLATE streams (RFC 1951). The PDF `/FlateDecode`
  filter expects a zlib wrapper (RFC 1950), so the encoder emits the 2-byte zlib
  header plus an Adler-32 trailer around the raw DEFLATE payload. gzip (RFC 1952)
  is not needed for PDF and is documented only for completeness.

## Implementation status

Issue #127 ships the first portable profile:

- `PDFOptions.streamCompression` is disabled by default and opt-in per render.
- Page content streams and embedded `FontFile2` streams are compressed only when
  the zlib-wrapped output is smaller than the raw stream.
- The encoder emits stored blocks and fixed-Huffman blocks with a deterministic
  greedy LZ77 match finder. Dynamic Huffman blocks remain future work.
- `/Length` is the encoded byte count. `FontFile2` keeps `/Length1` as the
  uncompressed font-program byte count.
- Focused witnesses cover round-trip inflate, exact stream lengths,
  `qpdf --check`, `pdftotext` parity with the uncompressed baseline, size
  reduction for representative repeated streams, and deterministic output.

## Standards and sources

DEFLATE bitstream and its wrappers:

- RFC 1951, DEFLATE Compressed Data Format Specification v1.3 (P. Deutsch, 1996).
  Canonical: https://www.rfc-editor.org/rfc/rfc1951.html and
  https://www.ietf.org/rfc/rfc1951.txt . This is the normative spec for block
  types, the fixed Huffman code tables, the length/distance symbol alphabets and
  extra-bit tables, and bit-packing order (codes packed LSB-first; Huffman codes
  packed MSB-first within their field).
- RFC 1950, ZLIB Compressed Data Format Specification v3.3 (Deutsch and Gailly,
  1996): https://www.rfc-editor.org/rfc/rfc1950.html and
  https://www.ietf.org/rfc/rfc1950.txt . Defines the CMF/FLG header bytes, the
  optional DICTID, and the trailing Adler-32 checksum that wrap raw DEFLATE for
  PDF `/FlateDecode`.
- RFC 1952, GZIP File Format Specification v4.3 (Deutsch, 1996):
  https://www.rfc-editor.org/rfc/rfc1952.html . Not used by PDF; recorded for
  completeness only.

Foundational papers:

- D. A. Huffman, "A Method for the Construction of Minimum-Redundancy Codes,"
  Proceedings of the IRE, vol. 40, no. 9, pp. 1098-1101, Sept. 1952. Archival
  PDF: https://compression.ru/download/articles/huff/huffman_1952_minimum-redundancy-codes.pdf
  Source for the optimal prefix-code construction; DEFLATE uses a length-limited
  canonical variant of it.
- J. Ziv and A. Lempel, "A Universal Algorithm for Sequential Data Compression,"
  IEEE Trans. Information Theory, vol. 23, no. 3, pp. 337-343, May 1977. PDF:
  https://courses.cs.duke.edu/spring03/cps296.5/papers/ziv_lempel_1977_universal_algorithm.pdf
  (DOI catalog: https://dl.acm.org/doi/10.1109/TIT.1977.1055714 ). Source for
  LZ77 sliding-window dictionary matching, the back-reference half of DEFLATE.

PDF-specific:

- ISO 32000-1:2008 (PDF 1.7), Adobe-donated copy:
  https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf
  Clause 7.4 (Filters, FlateDecode) and 9.9 (Embedded Font Programs). ISO 32000-2
  syntax errata clause: https://pdf-issues.pdfa.org/32000-2-2020/clause07.html .

## Format model and how it maps to PDF

A DEFLATE stream is a sequence of blocks. Each block starts with 3 header bits:
`BFINAL` (1 = last block) and `BTYPE` (00 stored, 01 fixed Huffman, 10 dynamic
Huffman, 11 reserved/error). Blocks need not be byte-aligned except stored
blocks, which pad to a byte boundary then carry `LEN` and `~LEN` 16-bit fields
followed by raw bytes.

Inside a compressed block the data is a stream of symbols from two alphabets:

- Literal/length alphabet (0-285): 0-255 are literal bytes, 256 is end-of-block,
  257-285 encode match lengths 3-258 with per-symbol extra bits.
- Distance alphabet (0-29): back-reference distances 1-32768 with extra bits.

LZ77 produces the literals and `<length, distance>` pairs; Huffman coding maps
those symbols to bits. RFC 1951 limits distances to 32K and lengths to 258.

How this attaches to PDF: a stream object is written as
`<< /Filter /FlateDecode /Length N >> stream ... endstream`, where `N` is the byte
count of the encoded (compressed, zlib-wrapped) data. For a `FontFile2` program
the descriptor stream additionally carries `/Length1` set to the UNCOMPRESSED
TrueType byte count (per ISO 32000-1 section 9.9 and the existing FontFile2 plan),
while `/Length` is the compressed byte count. `/Length1` is therefore computed
before compression and is independent of the filter. The Adler-32 trailer is over
the uncompressed data.

## Encoder construction

LZ77 match finding:

- Hash-chain match finder. Hash 3 bytes at the current position into a table of
  head pointers; chain equal-hash positions through a `prev[]` array indexed by
  window position. Walk the chain to find the longest match within the 32K
  window, capped at 258 bytes and by a `max_chain` effort limit. This is the
  classic zlib structure (`deflate.c`) and is straightforward to port.
- Lazy matching. After finding a match at position p, also probe p+1. If p+1
  yields a strictly longer match, emit a literal at p and take the longer match;
  otherwise emit the match at p. This is the standard quality-vs-speed lever and
  what zlib calls lazy evaluation.
- Optimal / minimum-cost-path parsing is a later, optional quality tier
  (libdeflate levels 10-12). Not required for first delivery.

Block type selection:

- Stored blocks for incompressible or tiny inputs (the encoded size of a
  compressed block would exceed the raw size). Always correct, trivially
  deterministic, good first milestone.
- Fixed Huffman (BTYPE=01): use the RFC 1951 static code tables. No per-block
  table cost, so it wins for small blocks. Deterministic by construction.
- Dynamic Huffman (BTYPE=10): build two canonical Huffman trees from the actual
  symbol frequencies of the block, length-limited to 15 bits for the
  literal/length and distance trees, then encode the code-length sequence with a
  third Huffman tree (the code-length alphabet, with the RFC's run-length
  symbols 16/17/18 and the fixed permutation order). Choose dynamic over fixed
  only when the estimated dynamic size including the table cost is smaller.

Canonical Huffman construction:

- Count symbol frequencies, build a length-limited optimal code (package-merge or
  the bounded-depth heap method zlib uses in `trees.c`), then assign canonical
  codes: sort by (code length, symbol value), assign codes in increasing order
  per RFC 1951 section 3.2.2. Canonical assignment is what makes the output
  reproducible and is the only assignment the decoder can reconstruct from
  lengths alone.

Block splitting: a long input can be cut into multiple blocks so each block gets
a Huffman table matched to its local statistics. A simple, deterministic policy
(fixed-size or frequency-drift triggered splits) is enough for first delivery;
sophisticated split-point search is an optional later tier.

## Reference implementations (study only, not dependencies)

- zlib (madler/zlib), zlib license:
  https://github.com/madler/zlib/blob/master/deflate.c , `trees.c` for Huffman
  tree building. License: https://zlib.net/zlib_license.html . The canonical
  hash-chain + lazy-match encoder and length-limited Huffman builder.
- libdeflate (ebiggers/libdeflate), MIT license:
  https://github.com/ebiggers/libdeflate/blob/master/lib/deflate_compress.c .
  Greedy/lazy/near-optimal tiers; study its minimum-cost-path parser later.
- miniz (richgel999/miniz), MIT license:
  https://github.com/richgel999/miniz . Single-file, compact, complete reference
  encoder+decoder.
- Go compress/flate, BSD-3-Clause:
  https://go.dev/src/compress/flate/deflate.go and
  https://go.dev/src/compress/flate/huffman_bit_writer.go . Clean readable
  encoder and bit writer; good structural model for Swift.
- Rust miniz_oxide, MIT OR Zlib OR Apache-2.0:
  https://docs.rs/miniz_oxide . Safe, allocation-disciplined port of miniz.
- fpnge (veluca93/fpnge), Apache-2.0:
  https://github.com/veluca93/fpnge . Precomputed dynamic-Huffman tables for a
  constrained parser.

License posture: each project above is read for algorithm understanding and
reimplemented from the RFCs and papers. None is vendored or linked. The zlib,
MIT, BSD, and Apache-2.0 terms are all permissive and compatible with this
study-only posture, but we still write original Swift.

## Witness policy

Structural assertions first:

- Encoded streams declare `/Filter /FlateDecode` and a `/Length` equal to the
  emitted compressed byte count.
- `FontFile2` streams declare `/Length1` equal to the UNCOMPRESSED font program
  byte count, with `/Length` equal to the compressed count.
- Stored-block output equals input plus the stored framing, exactly.

Round-trip witnesses (oracle in test target only):

- Compress in Swift, inflate with a third-party oracle (zlib via system tooling,
  e.g. `qpdf`/`pdftotext` decompressing the stream, or a test-only library),
  assert the inflated bytes equal the original input for content streams and for
  the font program.
- `qpdf --check` and `qpdf --qdf` accept the compressed PDF.
- `pdftotext` extraction still matches the uncompressed-stream baseline at the
  text level.

Determinism witnesses:

- Same input compresses to byte-identical output on macOS and Linux in CI.
- Re-running the encoder on the same input is bit-stable.

Negative tests:

- Incompressible input falls back to stored blocks and never grows beyond the
  stored-framing overhead.
- Existing uncompressed-stream tests continue to pass unchanged with compression
  off.

## Determinism concerns

Byte-identical output across platforms is a hard requirement and is where most
DEFLATE encoders silently diverge. The encoder must pin every nondeterministic
lever:

- No `Dictionary` iteration order or `Set` ordering in symbol/table construction;
  use arrays indexed by symbol value.
- Length-limited Huffman code construction must use a fully specified tie-break
  (sort by code length then symbol value) so two platforms assign identical
  canonical codes.
- Match-finder effort limits (`max_chain`, lazy threshold, good/nice-length
  cutoffs) must be fixed constants, not tuned per platform or CPU.
- Block-split decisions must be a pure function of the input, not of timing or
  buffer sizes.
- The zlib wrapper FLG check bits and FLEVEL must be fixed values.

Determinism is verified mechanically by the cross-platform CI witness, not
assumed.

## Ordered work

1. Done: zlib wrapper + Adler-32 + stored blocks. Emit RFC 1950 header/trailer around
   stored DEFLATE blocks. Wire `/FlateDecode`, `/Length`, and `/Length1`. Prove
   round-trip via oracle and `qpdf --check`. Smallest correct milestone.
2. Done: fixed Huffman + LZ77 hash chains. Add the hash-chain match finder,
   greedy matching, and RFC 1951 static-table encoding. First milestone that
   actually shrinks streams.
3. Next: dynamic Huffman. Add length-limited canonical Huffman construction, the
   code-length alphabet encoding, and fixed-vs-dynamic-vs-stored block selection.
4. Block splitting and optional optimal parsing tier. Deterministic split policy
   first; minimum-cost-path parsing only as an opt-in quality tier later.
5. Enable compression by default for content streams and `FontFile2` once all
   witnesses pass.

Each stage ships behind the opt-in flag and adds its witnesses before the next
stage begins.

## Platform notes

- The encoder is pure Swift `Data`/`[UInt8]` arithmetic with no platform APIs, so
  macOS and Linux run the identical code path. No Apple `Compression` fallback.
- Adler-32 and the bit writer are integer-only and endian-independent as written
  (the format defines its own byte order), so no platform endianness handling is
  required beyond following the RFC packing rules.
- The test oracle may differ per platform, but the production encoder output it
  checks must be identical on both.
- iOS is not in scope for this issue; the code is platform-neutral but no iOS
  witness is claimed here.


## Source-code references (vendored in `researchcode/`)

VERDICT: no vendored project implements DEFLATE from scratch; every one WRAPS zlib (or Rust `miniz_oxide`). Their in-tree value is the PDF stream WIRING, not the codec. The codec itself must come from the canonical sources being vendored in #137 (libdeflate, zlib).

PDF stream wiring (study-only):
- `researchcode/skia/src/pdf/SkPDFTypes.cpp` - `serialize_stream()` (~L556-589): compress, compare against `kMinimumSavings` (21 bytes), fall back to raw, then emit `/Filter /FlateDecode` + `/Length`. The compress-or-skip decision to mirror. (C++, BSD-3)
- `researchcode/skia/src/pdf/SkDeflate.cpp` - `SkDeflateWStream` (~L78-143): buffering + `Z_FINISH` flush state machine around zlib `deflateInit2(level, Z_DEFLATED, 0x0F, 8, ...)` (0x0F = zlib header = what `/FlateDecode` expects). Mirror the buffering shape; bytes stay your own RFC 1951 code.
- `researchcode/pdfio/pdfio-stream.c` - `_pdfioStreamClose`/`_pdfioStreamCreate` (~L139-339): canonical `/Length` handling (indirect length object vs seek-back over a `/Length 9999999999` placeholder) and `/DecodeParms` predictor setup. (C, Apache-2.0)
- `researchcode/pdf-writer/src/object.rs` - `Stream::start` + `Filter::to_name()` + `Drop`: simplest correct precise-`/Length` (compress fully in memory, then write `/Length = data.len()`). Crate does no DEFLATE itself (routes to external `miniz_oxide`). (Rust, MIT/Apache)
- `researchcode/borb/.../flate_decode.py` - PNG/TIFF predictor unwinding incl. full Paeth (spec-defined, language-neutral; reimplement from ISO 32000 / RFC 2083, not from this AGPL file).

To-vendor (see #137): `libdeflate/lib/deflate_compress.c` (MIT) and `zlib/deflate.c`+`trees.c` (zlib license) are the actual from-scratch encoder + length-limited Huffman to port.

Spec anchors: RFC 1951/1950/1952, Huffman 1952, Ziv-Lempel 1977, ISO 32000 7.4.4.
