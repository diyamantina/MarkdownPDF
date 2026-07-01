# Portable embedded fonts and ToUnicode plan

Date: 2026-06-01

Scope: this note defines the smallest portable embedded-font and ToUnicode
profile MarkdownPDF can implement without changing the project boundary. It is a
plan for future implementation issues, not current product behavior.

## Rule context

- The shared renderer must remain pure Swift and Linux-buildable.
- PDF bytes must be generated directly by this package.
- No PDFKit, CoreGraphics, CoreText, WebKit, browser renderers, JavaScript,
  Python, LaTeX, C Markdown libraries, or C PDF libraries are allowed in the
  shared path.
- Do not commit font binaries to the public repository.
- macOS and Linux must produce the same output for the same input font data.
- This plan does not establish iOS support. Any later iOS support needs its own
  explicit platform review and tests.

## Current baseline

The default portable profile uses standard PDF base fonts and writes simple text
strings through page content streams. Unsupported Unicode scalars are replaced
with `?`. The default path intentionally does not emit `/FontFile`,
`/FontFile2`, `/FontFile3`, `/ToUnicode`, Type 0 fonts, CID fonts, or CMap
streams.

The opt-in embedded-font profile now accepts caller-provided TrueType data
through `PDFOptions.EmbeddedFonts`. Each supplied role is parsed, validated,
mapped, subsetted, and emitted as a Type 0 parent font with a CIDFontType2
descendant, FontFile2 stream, ToUnicode CMap, and CIDToGIDMap when compact CIDs
need it. Roles left nil keep using the matching base font role.

Existing code contains these reusable hooks and implementation points:

- `PDFFontObject` serializes `DescendantFonts` and `ToUnicode` references.
- `PDFFontDescriptor` serializes `FontFile`, `FontFile2`, and `FontFile3`
  references.
- `PDFContentStream` and `PDFPageCanvas` centralize text drawing operations.
- `PDFEmbeddedFontCatalog` resolves public role mappings to parser metadata and
  glyph mappers without scanning platform font directories.
- `PDFValidation`, Poppler geometry, MuPDF character quads, and raster
  comparison witness text extraction and layout quality.

The current `FontSet.appleSystem` names are unembedded TrueType font names. That
is a naming option, not an embedded-font implementation, and it must not be used
as evidence for portable font embedding.

## Research sources used

This plan is based on existing repository research:

- `markdownpdf-output-profile.md` for the current base-font and text encoding
  boundary.
- `existing-pdf-writer-alignment.md` for the current Swift writer shape and the
  existing gaps around Type 0 fonts, CID fonts, CMaps, and ToUnicode.
- `open-source-pdf-library-porting.md` for architecture patterns from PDFBox,
  Skia, libHaru, Typst, and other projects that can be reimplemented in Swift
  without taking those projects as dependencies.
- `pdf-rendering-literature-review.md` for the extraction-quality and font
  embeddability risks.
- `pdf-validation-tooling.md` and `pdf-visual-layout-validation.md` for qpdf,
  Poppler, MuPDF, and raster witness expectations.

The result is a portable macOS and Linux plan. macOS-only font discovery remains
optional future product work, and iOS support is not claimed.

## Smallest supported profile

The first embedded-font profile should be:

- TrueType outlines from caller-provided font data.
- Type 0 composite font dictionaries with descendant CIDFontType2 dictionaries.
- Identity-H encoding for PDF character codes.
- A ToUnicode CMap for every embedded text font.
- Latin-first text where each Unicode scalar maps to one glyph without shaping.
- Deterministic subset names, glyph ordering, widths, and object ordering.
- Visible fallback or an explicit thrown error when required glyphs are missing.

This first profile should not claim:

- Arabic, Hebrew, or other bidirectional text.
- Indic, Thai, Khmer, Tibetan, or other complex shaping.
- Emoji, color fonts, variable fonts, OpenType CFF, TTC collections, WOFF, or
  WOFF2.
- Ligature substitution, kerning, mark positioning, vertical writing, or ruby
  text.
- PDF/A or PDF/UA conformance.
- iOS support.

Complex-script shaping and bidi follow-up work is tracked by #79 and
`complex-script-shaping-bidi-roadmap.md`.

## Font input policy

The core portable renderer should not scan system font directories. It accepts
font data that the caller supplies explicitly:

```swift
let fontData = try Data(contentsOf: URL(fileURLWithPath: "OpenFont.ttf"))
let source = PDFOptions.EmbeddedFontSource(data: fontData)
let options = PDFOptions(embeddedFonts: .allRoles(source))
```

These constraints hold:

- Default output remains PDF base fonts with no embedded font files.
- Embedded fonts are opt in.
- The public repo stores no font binaries.
- Tests can use CI-installed open fonts or an environment-provided font path,
  but the package source must not depend on a bundled font file.
- The core rejects fonts whose OS/2 `fsType` forbids embedding.
- The core records whether embedding is installable, editable, preview-print,
  or restricted when that metadata exists.
- Fonts that permit embedding but set the no-subsetting bit must use full-font
  embedding or be rejected by any subset-only feature. The current public
  profile is subset-only, so those fonts are rejected.
- A macOS product may later add font discovery, but discovery is outside the
  shared renderer and does not imply Linux or iOS behavior.

## CI-safe font fixture policy

The public repository must not store real font binaries. Tests use two fixture
classes:

- Generated Swift TrueType fixtures for deterministic parser, mapper, subset,
  writer, and public API tests. These are source-level byte builders, not
  committed font files.
- CI-installed or environment-provided open fonts for external-font smoke
  tests. GitHub CI installs DejaVu Sans on Linux and Liberation Sans on macOS,
  then passes the chosen path through `MARKDOWNPDF_OPEN_FONT_PATH`. Unsupported
  local environments may skip only those external-font tests, with the skip
  reason naming the missing font path.

The current #70 public API witness uses the generated TrueType fixture so macOS
and Linux run the same deterministic test without committing a font binary. A
separate external-font smoke test uses a CI-installed open font path to prove
the public API also accepts a real open TrueType font without making that font a
repository dependency.

## Required PDF objects

The first implementation should emit these objects for each embedded font.

### Type 0 parent font

Required entries:

- `/Type /Font`
- `/Subtype /Type0`
- `/BaseFont /ABCDEF+PostScriptName`
- `/Encoding /Identity-H`
- `/DescendantFonts [n 0 R]`
- `/ToUnicode n 0 R`

The six-letter subset prefix must be deterministic for tests. The production
implementation can derive it from stable document font order and subset content.

### CIDFontType2 descendant font

Required entries:

- `/Type /Font`
- `/Subtype /CIDFontType2`
- `/BaseFont /ABCDEF+PostScriptName`
- `/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>`
- `/FontDescriptor n 0 R`
- `/W [...]`
- `/CIDToGIDMap /Identity` only when CIDs equal glyph ids.

If the subset assigns compact CIDs that do not equal glyph ids, emit a
`CIDToGIDMap` stream instead of `/Identity`.

### FontDescriptor

Required entries:

- `/Type /FontDescriptor`
- `/FontName /ABCDEF+PostScriptName`
- `/Flags`
- `/FontBBox`
- `/ItalicAngle`
- `/Ascent`
- `/Descent`
- `/CapHeight`
- `/StemV`
- `/FontFile2 n 0 R`

Metrics should come from the TrueType tables where possible. Do not invent
descriptor numbers when the font exposes better values.

### FontFile2 stream

Required behavior:

- Store the embedded TrueType subset or full font bytes.
- Set `/Length1` to the uncompressed font program byte count.
- Preserve deterministic stream bytes for tests.
- Compression follows `PDFOptions.streamCompression`: default off, opt-in
  `/Filter /FlateDecode` only when the Pure Swift encoded stream is smaller
  than the raw font program.

### ToUnicode CMap stream

Required behavior:

- Use CMapType 2.
- Define a codespace for the emitted two-byte PDF character codes.
- Map every emitted PDF character code to the original Unicode scalar sequence.
- Emit deterministic `bfchar` and `bfrange` blocks.
- Chunk mappings to stay inside PDF CMap operator limits.

The first profile should map one PDF character code to one Unicode scalar.
Multi-scalar mappings, ligatures, combining sequences, and shaped clusters are
future work.

## TrueType parser requirements

The first parser should be specification-driven and small. It needs enough table
coverage to validate embedding, measure text, and build the PDF font objects:

- Table directory checksums and offsets.
- `head` for units per em, bounding box, indexToLocFormat, and checksum
  adjustment.
- `hhea` and `hmtx` for advances and left side bearings.
- `maxp` for glyph count.
- `cmap` for Unicode scalar to glyph id mapping, starting with format 4 and
  format 12.
- `name` for PostScript name and family naming.
- `OS/2` for embeddability, ascent, descent, cap height when available, and
  weight/style metadata.
- OS/2 `fsType` bits for restricted embedding, preview-print embedding,
  editable embedding, no subsetting, and bitmap-only embedding.
- `post` for italic angle when available.
- `loca` and `glyf` for subset extraction and composite glyph closure.

The parser should reject malformed offsets, unsupported table formats, missing
required tables, and fonts that do not cover requested scalars.

## Text layout requirements

Embedded-font text cannot reuse the current single-byte literal string path.
Future layout needs a distinction between source text and encoded glyph runs:

- Source Unicode scalars remain available for extraction and fallback messages.
- Glyph ids come from the font parser.
- PDF character codes are assigned by the subset planner.
- Width measurement uses glyph advance widths in font units scaled by font size.
- Content streams write hex strings or `TJ` arrays with two-byte character
  codes.
- Existing base-font rendering stays unchanged unless embedded fonts are enabled.

The first implementation should keep the current greedy wrapping algorithm and
replace only the measurement and encoding backend for embedded fonts. Paragraph
optimization, kerning, and shaping are separate issues.

## Subsetting plan

Subsetting should be staged. A full-font embedding milestone is acceptable only
as an internal stepping stone if it never claims final article-grade output.
The public feature should prefer subsets because full fonts make PDFs large and
can violate font license expectations.

Subset requirements:

1. Collect used Unicode scalars after Markdown parsing and inline fallback.
2. Resolve glyph ids through the selected font.
3. Add `.notdef` and required space glyphs.
4. Recursively include composite glyph dependencies from `glyf`.
5. Assign deterministic CIDs.
6. Build `/W` widths from the selected glyph advances.
7. Build `CIDToGIDMap` if CIDs do not equal glyph ids.
8. Write a valid subset TrueType program with corrected table checksums.
9. Emit a ToUnicode CMap for all emitted character codes.

If the subset writer is too large for one issue, split it before public API
exposure.

## Validation requirements

Every implementation stage needs structural tests before visual tests.

Required structural assertions:

- Type 0 parent font exists when embedded fonts are enabled.
- CIDFontType2 descendant exists and is referenced by the parent.
- FontDescriptor references `/FontFile2`.
- FontFile2 stream length and Length1 match emitted bytes.
- ToUnicode stream exists and is referenced by the parent font.
- Page resources reference the embedded font resource.
- Base-font default PDFs still omit font files and ToUnicode maps.

Required extraction and layout witnesses:

- `qpdf --check` accepts the generated PDF.
- `pdftotext` extracts accented Latin text exactly for the embedded-font
  fixture.
- `pdftotext -tsv` reports word boxes inside page bounds with no same-line
  overlap.
- `mutool draw -F stext` reports positive character quads with monotonic glyph
  order inside text runs.
- Poppler and MuPDF page rasters have comparable ink bounds.

Required negative tests:

- Missing requested glyphs fail visibly or throw a typed error.
- Restricted embedding permissions are rejected.
- No-subsetting permissions force full embedding or a typed rejection in
  subset-only modes.
- Malformed TrueType table offsets are rejected.
- Unsupported font formats are rejected with actionable messages.
- Existing base-font tests continue to pass unchanged.

## Proposed implementation issues

These issues can be opened directly from this plan.

1. Model Type 0, CIDFontType2, FontFile2, and ToUnicode objects.
   - Add typed Swift PDF structures for the object dictionaries and CMap stream.
   - Add serialization tests for required keys and deterministic ordering.
   - Do not change renderer output yet.

2. Add a pure Swift TrueType metadata parser.
   - Parse required tables listed in this plan.
   - Validate offsets, lengths, and embeddability metadata.
   - Add parser-negative unit tests using tiny synthetic table byte arrays.
   - Use CI-provided or environment-provided open fonts for real font programs.
   - Do not commit real font programs as source bytes.

3. Add embedded-font glyph mapping and width measurement.
   - Map Latin Unicode scalars to glyph ids.
   - Measure text from `hmtx` advances.
   - Keep the existing base-font path unchanged.

4. Add ToUnicode CMap generation and tests.
   - Generate deterministic CMap streams for two-byte PDF character codes.
   - Verify exact extraction for accented Latin text.

5. Add CID text content writing behind an opt-in embedded-font option.
   - Write hex strings or `TJ` arrays with two-byte character codes.
   - Keep source text, glyph ids, CIDs, and widths as separate data.
   - Add qpdf, Poppler, MuPDF, and raster witnesses.

6. Add TrueType subsetting.
   - Include composite dependencies.
   - Emit deterministic subset names and font program bytes.
   - Add CIDToGIDMap support when compact CIDs are used.

7. Add public API and CI font fixture policy.
   - Keep embedded fonts opt in.
   - Document caller font licensing responsibility.
   - Use generated Swift TrueType fixtures for deterministic CI coverage.
   - Configure external-font smoke tests to use installed DejaVu Sans or an
     explicit environment-provided path without committing font files.

8. Defer complex-script shaping and bidi to a separate epic.
   - Require a pure Swift shaping plan or an explicitly optional platform
     product plan.
   - Do not expand the first embedded-font profile to these scripts.

## Decision summary

The minimum useful portable path is not "embed any font and hope." It is a
Type0/CIDFontType2 text path with ToUnicode from the start, a strict font input
policy, Latin-first scope, and witness tests that prove both extraction and
layout. Base fonts remain the default because they are small, deterministic, and
already covered by the current output profile.
