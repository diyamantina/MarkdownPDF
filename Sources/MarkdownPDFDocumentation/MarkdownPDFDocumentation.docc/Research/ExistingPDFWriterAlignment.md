# Existing PDF Writer Alignment

Date: 2026-05-31

Scope: this note maps the current Swift implementation to the PDF rendering
research in `docs/research/pdf-rendering-literature-review.md` and
`docs/research/open-source-pdf-library-porting.md`. The goal is to keep future
work grounded in code that already runs on Linux and macOS.

## Rule Context

- Linux is a required target, not a later port.
- The shared renderer must stay pure Swift and must not depend on Apple PDF,
  graphics, browser, JavaScript, Python, LaTeX, C, or system renderer stacks.
- macOS-specific PDF APIs can be studied as optional backend research, but they
  cannot become the shared implementation path.
- Useful research belongs in `docs/research`.

## Working Baseline

STRUCTURAL: the package already exposes separate products for the shared
renderer, the Linux entry point, and the macOS entry point. The Linux and macOS
entry points currently delegate to `MarkdownPDFRenderer`, which means both
platform products use the same portable renderer.

Code references:

- `Packages/Package.swift`
- `Packages/Sources/MarkdownPDFLinux/MarkdownPDFLinuxRenderer.swift`
- `Packages/Sources/MarkdownPDFMac/MarkdownPDFMacRenderer.swift`

STRUCTURAL: `PDFDocumentWriter` writes PDF bytes directly. It reserves catalog
and pages objects, writes page objects, content streams, resources, annotation
objects, image objects, a classic xref table, trailer, and `startxref`.

Code references:

- `Packages/Sources/MarkdownPDF/PDFDocumentWriter.swift`
- page objects and resources: lines 23-40
- font and image resources: lines 61-76
- streams: lines 132-139
- image XObjects: lines 141-156
- URI link annotations: lines 159-170
- xref and trailer: lines 173-199

STRUCTURAL: the current text output path writes PDF text operators directly.
`PDFPageCanvas` emits `BT`, font selection, text positioning, literal strings,
and `Tj`. It also emits line, rectangle, and image placement operators.

Code references:

- `Packages/Sources/MarkdownPDF/PDFPageCanvas.swift`

STRUCTURAL: the default font path uses PDF base fonts and intentionally does not
embed font files. `FontSet.appleSystem` is an optional name set, but the emitted
font dictionary still does not include `/FontFile`.

Code references:

- `Packages/Sources/MarkdownPDF/PDFOptions.swift`
- `Packages/Sources/MarkdownPDF/StandardFont.swift`
- `Packages/Sources/MarkdownPDF/PDFDocumentWriter.swift`, lines 96-129

MEASURED BY TESTS: existing tests assert PDF 1.4 output, base fonts, no
`/FontFile`, valid xref offsets, matching stream lengths, link annotations,
page counts, image XObjects, proportional metrics, and article-grade fixtures.

Test references:

- `Packages/Tests/MarkdownPDFTests/MarkdownPDFRendererTests.swift`, lines 12-220
- `Packages/Tests/MarkdownPDFTests/FixtureTests.swift`, lines 72-110
- `Packages/Tests/MarkdownPDFTests/PDFInspector.swift`

## Current Layout Model

STRUCTURAL: the renderer handles headings, paragraphs, block quotes, lists,
code blocks, tables, thematic breaks, inline HTML fallback, links, and images.
The layout model is intentionally simple.

Current behavior:

- Paragraphs are flattened into `PDFTextRun` values.
- Wrapping is greedy and token based.
- Break opportunities are spaces, tabs, and explicit newlines.
- Pagination is immediate through `ensureSpace`.
- Headings have a keep-with-next rule.
- Tables use equal column widths and row height from wrapped line count.
- Local JPEG and simple PNG files are emitted as image XObjects.
- Remote images render as text fallback.

Code references:

- table rows: `Packages/Sources/MarkdownPDF/MarkdownPDFRenderer.swift`, lines
  181-260
- images: `Packages/Sources/MarkdownPDF/MarkdownPDFRenderer.swift`, lines
  263-301
- inline flattening: `Packages/Sources/MarkdownPDF/MarkdownPDFRenderer.swift`,
  lines 304-371
- wrapping and tokenization:
  `Packages/Sources/MarkdownPDF/MarkdownPDFRenderer.swift`, lines 374-447

## Fit With Scientific Typesetting Ideas

DOCUMENTED: Knuth and Plass model line breaking as an optimization over boxes,
glue, penalties, and demerits.

REPO IMPACT: the current `PDFTextRun` and token wrapping path is a useful
starting point. A pure Swift paragraph breaker can first convert text runs into
portable layout items, then choose breakpoints before drawing. This does not
require Apple frameworks.

DOCUMENTED: Plass pagination and later automated typesetting literature treat
page breaking as a document-level optimization problem, not only as immediate
height checks.

REPO IMPACT: the current `ensureSpace` function is the right place to identify
the boundary, but not the final algorithm. The next maintainable step is an
intermediate layout tree with block heights and legal breakpoints. That lets
headings, table rows, figures, and captions participate in page breaking before
PDF bytes are emitted.

DOCUMENTED: Unicode line breaking, bidirectional ordering, OpenType shaping,
and glyph mapping are separate concerns.

REPO IMPACT: the renderer should not claim full Unicode or complex-script
typesetting yet. A Linux and macOS compatible path can add UAX 14 style line
break classes first, then later add a pure Swift shaping and font-subsetting
layer if the project accepts that scope.

DOCUMENTED: PDF text extraction quality depends on encoding, font dictionaries,
and ToUnicode mappings.

REPO IMPACT: the current literal string path replaces scalars outside the
single-byte range with `?`. That is acceptable for the current base-font
baseline, but it is not sufficient for article-grade Unicode text, embedded
fonts, or reliable extraction. Font embedding should be paired with Type 0 font
support and ToUnicode tests.

DOCUMENTED: table and figure quality is not just visual. Scientific documents
need stable reading order, cell structure, captions, and extractable text.

REPO IMPACT: current tables are visual grids. The next table milestone should
introduce a table layout model before adding more drawing features. This will
make repeated headers, row splitting, captions, and future tagged PDF work
possible.

## Fit With Open Source PDF Libraries

DOCUMENTED: PDFBox, FOP, Typst, Skia, libHaru, Cairo, and ReportLab all prove
that robust PDF generation is usually built from a small number of stable
layers: document model, layout model, resource manager, content stream writer,
font subsystem, and validation tests.

REPO IMPACT: MarkdownPDF already has early versions of these layers:

- document model: Markdown AST
- layout model: current `Layout` struct
- resource manager: font and XObject dictionaries in `PDFDocumentWriter`
- content stream writer: `PDFPageCanvas`
- font subsystem: `StandardFont`
- validation tests: `PDFInspector`

The best Swift porting strategy is to copy architecture, invariants, and test
oracles, not source code. The public repo should avoid translated code unless a
license review explicitly allows it.

## Important Gaps

STRUCTURAL: there is no document outline, named destination tree, page labels,
or generated table of contents yet. The catalog only points at the page tree and
optionally sets display-title preferences.

STRUCTURAL: there is no embedded font stream, Type 0 font, CID font, CMap, or
ToUnicode map.

STRUCTURAL: there is no tagged PDF structure tree, role map, marked content, or
PDF/UA validation path.

STRUCTURAL: there is no PDF/A metadata, output intent, or veraPDF gate.

STRUCTURAL: Mermaid, chart, and graph support does not exist as rendering
logic. Under current repo rules, Mermaid CLI, browser rendering, JavaScript, and
external rasterization tools are not acceptable source or test dependencies.
Acceptable future paths are a small pure Swift diagram subset, caller-provided
image assets, or vector chart primitives implemented in Swift.

STRUCTURAL: content streams are not compressed. This is simpler for tests and
debugging, but compression can be added later if a pure Swift implementation is
chosen and test fixtures inspect decoded content.

## Recommended Next Order

1. Strengthen the current `PDFInspector` tests around object references,
   resource dictionaries, annotations, and generated fixtures.
2. Introduce a typed PDF object and content-stream layer while preserving the
   current byte output tests.
3. Split layout into measured blocks before drawing. Keep PDF serialization as
   the last stage.
4. Add a portable line-breaking experiment based on Knuth-Plass ideas for Latin
   text, with snapshots that compare current greedy wrapping against optimized
   wrapping.
5. Replace equal-width table drawing with a table layout model.
6. Add outlines, named destinations, and generated ToC on top of the layout
   tree.
7. Add embedded font research only through a pure Swift font parser/subsetter
   design, with Type 0 fonts and ToUnicode maps in the same milestone.
8. Add chart and graph primitives as vector PDF operations before considering
   diagram languages.
9. Add PDF/A and tagged PDF only after the font and structure layers are in
   place.

## Source Anchors

- Knuth and Plass, `Breaking Paragraphs into Lines`:
  https://typographix.binets.fr/files/knuth-plass-breaking.pdf
- Plass, `Optimal Pagination Techniques for Automatic Typesetting Systems`:
  https://books.google.com/books/about/Optimal_Pagination_Techniques_for_Automa.html?id=SmogAQAAIAAJ
- Unicode Line Breaking Algorithm:
  https://www.unicode.org/reports/tr14/
- Unicode Bidirectional Algorithm:
  https://www.unicode.org/reports/tr9/
- OpenType overview:
  https://learn.microsoft.com/en-us/typography/opentype/spec/overview
- PDF Association PDF specification archive:
  https://pdfa.org/resource/pdf-specification-archive/
- PDFBox:
  https://pdfbox.apache.org/
- Typst open source:
  https://typst.app/open-source/
- Skia PDF theory:
  https://skia.org/docs/dev/design/pdftheory/
