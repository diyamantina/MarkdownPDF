# Changelog

All notable changes to MarkdownPDF are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial Pure Swift Markdown parser, PDF renderer, and `markdownpdf` CLI.
- Direct PDF serialization with Apple font names and no embedded fonts.
- Parser and renderer tests for tables, images, inline styles, and PDF structure.
- `MarkdownPDFLinux` and `MarkdownPDFMac` renderer entry products.
- MuPDF character-quad and cross-renderer raster validation for generated PDFs.
- Deterministic PDF metadata, named heading destinations, outline objects, and
  internal heading links.
- Portable Mermaid flowchart rendering for a documented Swift-only subset, with
  visible fallback for unsupported Mermaid syntax.
- Portable embedded-font and ToUnicode implementation plan for future Type 0
  and CIDFontType2 work.
- Internal Type 0, CIDFontType2, FontFile2, and ToUnicode object models for the
  portable embedded-font profile.
- Pure Swift TrueType metadata parser with table bounds, checksums, cmap
  discovery, horizontal metrics, names, and OS/2 embedding policy gates.
- Internal TrueType glyph mapping and width measurement for the portable
  embedded-font profile.
- Deterministic ToUnicode CMap generation with range compression, chunking, and
  glyph-mapping conflict detection.
- Opt-in CID text writing, TrueType subsetting, CIDToGIDMap streams, and public
  `PDFOptions.EmbeddedFonts` role mapping for caller-provided TrueType data.
- CI-safe embedded-font fixtures using generated Swift TrueType data and an
  installed DejaVu Sans smoke-test path instead of committed font binaries.
- Opt-in portable syntax coloring for supported fenced code block language
  hints, with extraction, geometry, and raster witnesses.
- Diverse multilingual showcase corpus combining prose, TeX math, native charts,
  Mermaid diagrams, and mixed-script tables, including a large multi-chapter
  handbook, rendered with embedded fonts under the full visual witness battery
  and across popular page formats (US Letter, Legal, Tabloid, A3, A5).

### Fixed

- Scale embedded-font CID `/W` widths and FontDescriptor metrics (FontBBox,
  Ascent, Descent, CapHeight) from the font `unitsPerEm` space to PDF 1000-unit
  glyph space. Fonts with `unitsPerEm != 1000` (DejaVu and Liberation use 2048)
  previously rendered garbled in viewers: glyphs spread apart, adjacent words
  overlapped, and lines collided vertically, because viewers advance glyphs from
  `/W` and derive glyph heights from the descriptor.
- Run the full visual witness battery (Poppler `pdftotext -tsv` word-box
  geometry, MuPDF character quads, and a Poppler-vs-MuPDF raster comparison) on
  embedded-font fixtures so width and metric scaling regressions fail the build
  instead of passing extraction-only checks.
- Stop the MuPDF character-quad witness from flagging legitimately tiny math
  sub/superscripts (zero-height, positive-width slivers) as non-positive size;
  only a clearly negative (flipped) height is now a defect.

### Changed

- Move the full study-only source snapshot corpus (33 third-party projects) out
  of `researchcode/` into the private companion repository `MarkdownPDFResearch`,
  keeping only a small high-signal subset (`pydyf`, `unicode-linebreak`,
  `unicode-bidi`, `libdeflate`, `zlib`) locally. This shrinks the public
  repository and keeps it classified as Swift.
- Model PDF object registration, xref tables, trailers, and file envelopes as
  typed Swift structures.
- Model the PDF catalog, flat page tree, and page dictionaries as typed Swift
  structures.
- Track page resource usage and resource dictionaries through typed Swift
  structures.
- Model image XObjects and reusable image resource references through typed
  Swift structures.
- Build page content streams from typed PDF operator structures.
- Measure table column widths from header and body content, preserve alignment,
  and repeat table headers across page breaks.
- Validate Mermaid edge-label placement during planning and fall back visibly
  when labels would collide with diagram nodes.
