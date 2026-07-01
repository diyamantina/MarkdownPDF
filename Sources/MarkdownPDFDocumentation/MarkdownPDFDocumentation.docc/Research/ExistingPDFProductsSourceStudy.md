# Existing PDF Products Source Study

Date: 2026-05-31

## Scope

This note records source-code research for portable PDF generation. The target
for MarkdownPDF remains Linux and macOS without Apple framework dependencies.
Implementation must stay Swift, but research does not need to prioritize Swift
projects.

Local source snapshots were downloaded under `researchcode/`. That directory is
ignored by Git and is not a vendored dependency. The snapshots are for
architecture study only.

Projects inspected:

- Typst: https://github.com/typst/typst
- pdf-writer: https://github.com/typst/pdf-writer
- Apache PDFBox: https://github.com/apache/pdfbox
- Apache FOP: https://github.com/apache/xmlgraphics-fop
- Skia PDF backend: https://github.com/google/skia
- QuestPDF: https://github.com/QuestPDF/QuestPDF
- libHaru: https://github.com/libharu/libharu

Swift projects were checked only as a quick reject pass. TPPDF, PDFGenerator,
and Swiftly-PDFKit depend on Apple rendering APIs, WebKit, or an external
HTML-to-PDF toolchain, so they are not useful implementation models for this
repo.

## Source Findings

### pdf-writer

Local paths:

- `researchcode/pdf-writer/src/chunk.rs`
- `researchcode/pdf-writer/src/content.rs`
- `researchcode/pdf-writer/src/font.rs`

The useful pattern is a typed PDF object and content-stream writer. `Chunk`
owns object output and offsets. `Content` owns PDF graphics and text operators.
Font support is split into Type0 fonts, font descriptors, embedded font files,
CMaps, and ToUnicode maps.

MarkdownPDF implication: grow a small typed PDF layer instead of expanding ad
hoc string assembly. Candidate Swift modules are `PDFObject`, `PDFRef`,
`PDFChunk`, `PDFContentStream`, `PDFResources`, and `PDFFontProgram`.

### Apache PDFBox

Local paths:

- `researchcode/pdfbox/pdfbox/src/main/java/org/apache/pdfbox/pdfwriter/COSWriter.java`
- `researchcode/pdfbox/pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDType0Font.java`

PDFBox keeps cross-reference writing, trailer writing, stream serialization,
font embedding, subsetting, and Unicode fallback as explicit subsystems.
`COSWriter` records object offsets and writes the body, xref table, trailer,
`startxref`, and EOF marker. Type0 font code handles embedded TrueType fonts,
subsetting, glyph IDs, and ToUnicode behavior.

MarkdownPDF implication: font embedding should be treated as a subsystem, not
as a text drawing option. Tests should inspect object references, xref offsets,
stream lengths, `/FontDescriptor`, `/FontFile2`, `/CIDFontType2`, and
`/ToUnicode`.

### Apache FOP

Local paths:

- `researchcode/xmlgraphics-fop/fop-core/src/main/java/org/apache/fop/pdf/PDFDocument.java`
- `researchcode/xmlgraphics-fop/fop-core/src/main/java/org/apache/fop/pdf/PDFToUnicodeCMap.java`
- `researchcode/xmlgraphics-fop/fop-core/src/main/java/org/apache/fop/pdf/PDFFactory.java`
- `researchcode/xmlgraphics-fop/fop-core/src/main/java/org/apache/fop/layoutmgr/BreakingAlgorithm.java`
- `researchcode/xmlgraphics-fop/fop-core/src/main/java/org/apache/fop/layoutmgr/PageBreakingAlgorithm.java`

FOP is most useful for layout architecture. It separates page and line breaking
from PDF serialization, uses Knuth-style boxes, glues, penalties, demerits, and
explicit page-break recovery. Its PDF code also creates ToUnicode CMaps and
registers font objects through a factory layer.

MarkdownPDF implication: line and page layout should produce a measured
intermediate layout model before PDF writing. Tables, headings, and paragraphs
should become layout elements with break decisions, not direct draw calls.

### Typst

Local paths:

- `researchcode/typst/crates/typst-pdf/src/lib.rs`
- `researchcode/typst/crates/typst-pdf/src/outline.rs`
- `researchcode/typst/crates/typst-pdf/src/text.rs`
- `researchcode/typst/crates/typst-pdf/src/tags/mod.rs`
- `researchcode/typst/crates/typst-layout/src/inline/linebreak.rs`
- `researchcode/typst/crates/typst-layout/src/grid/layouter.rs`

Typst separates document layout from PDF export. PDF export consumes a paged
document, builds outlines from headings and page destinations, draws glyphs
through a text layer, and has explicit tagging support. Its line breaker uses
simple and optimized paths, including dynamic programming for better line
choices. Its grid layouter handles repeated headers, rowspans, region state,
and orphan prevention.

MarkdownPDF implication: ToC and outline support should be driven by the layout
tree and heading locations. Table support should be designed as a layout model
with repeated headers and row or column spans before adding PDF drawing polish.

### Skia PDF Backend

Local paths:

- `researchcode/skia/src/pdf/SkPDFDocument.cpp`
- `researchcode/skia/src/pdf/SkPDFDevice.h`
- `researchcode/skia/src/pdf/SkPDFResourceDict.cpp`
- `researchcode/skia/src/pdf/SkPDFTag.cpp`

Skia keeps PDF resource dictionaries separate from page content and assigns
stable resource names for fonts, XObjects, patterns, and graphics states. It
writes object offsets, xref data, trailer data, annotations, page dictionaries,
resource dictionaries, and content streams through dedicated code paths.
Outlines can be derived from structure information.

MarkdownPDF implication: resource naming and page resource dictionaries should
be first-class. Page drawing should collect resource use while generating
content, then write a deterministic resource dictionary.

### QuestPDF

Local paths:

- `researchcode/QuestPDF/Source/QuestPDF/Drawing/SpacePlan.cs`
- `researchcode/QuestPDF/Source/QuestPDF/Elements/Table/Table.cs`
- `researchcode/QuestPDF/Source/QuestPDF/Infrastructure/PageContext.cs`
- `researchcode/QuestPDF/Source/QuestPDF/Fluent/GenerateExtensions.cs`

QuestPDF is not a PDF-byte-writing model for this repo because it uses Skia for
output. Its layout model is useful. Elements measure against available space and
return `Empty`, `Wrap`, `PartialRender`, or `FullRender` plans. Table layout
plans cell positions, handles partial rendering, tracks repeated headers, and
registers semantic table structure.

MarkdownPDF implication: introduce an explicit layout planning result for
blocks and tables. PDF writing should consume completed layout commands.

### libHaru

Local paths:

- `researchcode/libharu/src/hpdf_xref.c`
- `researchcode/libharu/src/hpdf_pages.c`

libHaru is useful as a compact writer model. It has an explicit xref table,
trailer dictionary, pages tree, page dictionaries, content streams, and
resources. It also finalizes page graphics state before writing.

MarkdownPDF implication: the current direct writer can stay small, but it needs
strict ownership of object IDs, offsets, page tree state, content streams, and
resource dictionaries.

## Portable Architecture Conclusions

1. Mature PDF products separate layout from PDF serialization.
2. Mature PDF writers keep object references and byte offsets typed.
3. Content streams should be built through operator APIs, not raw string
   fragments spread across renderers.
4. Embedded fonts require a dedicated subsystem: font parsing, glyph IDs,
   subsetting, font descriptors, font file streams, CID fonts, CMaps, and
   ToUnicode maps.
5. ToC and outline support depends on heading locations after layout, not only
   Markdown parsing.
6. Tables need planning before drawing: columns, rows, spans, page breaks,
   repeated headers, and eventually semantic structure.
7. Tagged PDF and PDF/A affect object structure early. They should be tracked
   as design constraints even if implemented later.

## Apple Platform Boundary

The useful implementation path here is not macOS-only and not iOS-only. The
recommended architecture uses pure Swift data structures and direct PDF bytes.
It does not rely on CoreGraphics, CoreText, PDFKit, WebKit, AppKit, UIKit, or
system HTML-to-PDF tools.

Swift projects found during the quick pass do not meet that boundary. They are
excluded from implementation research because they depend on Apple rendering
APIs or external HTML-to-PDF conversion. Their public API shapes may be glanced
at later, but their rendering architecture should not guide MarkdownPDF.

## Suggested Implementation Order

1. Add a typed PDF object and content-stream layer behind existing output tests.
2. Add deterministic page resource dictionaries and resource naming.
3. Build a measured layout tree and page planning model.
4. Implement outline and ToC from heading layout positions.
5. Add table layout planning with spans and page-break behavior.
6. Add embedded font infrastructure with Type0 fonts and ToUnicode maps.
7. Add optional tagged PDF and PDF/A validation tests.

## Test Ideas

- Byte-level PDF tests for header, object boundaries, stream lengths, xref
  offsets, trailer, `startxref`, and EOF.
- Resource tests that parse page dictionaries and confirm font, image, and
  graphics state resource names.
- Outline tests that confirm `/Outlines`, `/First`, `/Last`, `/Next`, `/Prev`,
  `/Dest`, and title strings.
- Font tests with generated tiny test fonts outside the public repo or fixture
  fonts that are license-cleared before commit.
- Layout tests that assert line breaks, page breaks, table row placement,
  repeated headers, and heading destinations independent from PDF bytes.
