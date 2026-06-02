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
