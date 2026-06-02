# Deep portable PDF source study

Date: 2026-05-31

This is a second source-code pass for portable PDF generation. The target for
MarkdownPDF remains a pure Swift implementation that runs on Linux and macOS
without Apple framework dependencies. The sources below are research inputs, not
dependencies and not code to copy into the repository.

Local source snapshots live under `researchcode/`, which is intentionally ignored
by Git. The public repository must not vendor third-party PDF libraries or font
files.

## Scope

The useful implementation path is shared by Linux and macOS. No recommendation in
this note requires CoreGraphics, CoreText, PDFKit, WebKit, browser rendering,
LaTeX, or C PDF libraries.

macOS and iOS boundary: this pass does not use Apple APIs. Anything described as
portable applies to Linux and macOS. It is not macOS-only and not iOS-only. If an
Apple-specific renderer is reconsidered later, its behavior must be documented in
a separate macOS/iOS boundary note and kept outside the portable core.

## Local source snapshots

- HexaPDF: `https://github.com/gettalong/hexapdf.git`, commit `7c8b42a`
- dart_pdf: `https://github.com/DavBfr/dart_pdf.git`, commit `72d590e`
- ReportLab mirror: `https://github.com/MrBitBucket/reportlab-mirror.git`,
  commit `320d4ba`
- Cairo: `https://gitlab.freedesktop.org/cairo/cairo.git`, commit `8e3ac5e`
- OpenPDF: `https://github.com/LibrePDF/OpenPDF.git`, commit `c5acada`
- PDFio: `https://github.com/michaelrsweet/pdfio.git`, commit `5cd0abd`

Earlier source notes also inspected Typst, pdf-writer, PDFBox, Apache FOP, Skia,
QuestPDF, and libHaru.

## Pure C projects

There are real pure C or mostly C projects worth studying:

- PDFio: small, direct C API for PDF objects, pages, streams, content operators,
  images, metadata, and PDF/A features. It is a useful model for a typed Swift
  writer surface.
- libHaru: compact C PDF writer. It is useful as a minimal object/page/xref
  reference.
- Cairo PDF surface: C backend for a vector drawing stack. It is more complex
  because it sits behind a graphics API, but it has valuable PDF code for font
  subsetting, images, tags, outlines, metadata, and xref streams.
- MuPDF: large C renderer and document engine. It is useful as an architecture
  reference only, not as a conversion target.

The implementation rule remains unchanged: do not add or port C libraries into
MarkdownPDF. Use these projects to understand PDF structure and test cases, then
implement the needed pieces in Swift.

## Object model and xref writing

MarkdownPDF currently writes many PDF objects through ad hoc strings in
`PDFDocumentWriter`. That works for the current surface but makes future features
fragile because fonts, outlines, tags, named destinations, streams, images, and
page resources all need stable object references before the file is finalized.

Portable source evidence:

- HexaPDF separates object serialization from file writing. `Writer` reserves and
  writes indirect objects, then writes xref and trailer data at the end.
  `Serializer` knows how to write dictionaries, arrays, references, strings, and
  streams.
- dart_pdf has a `PdfXrefTable` that assigns object numbers, emits object bodies,
  collects offsets, and writes either legacy xref tables or compressed xref
  streams.
- ReportLab registers objects by internal names, formats indirect objects until
  no more are discovered, then writes xref and trailer.
- OpenPDF stores cross references in a sorted set, supports object streams, and
  decides between legacy xref tables and xref streams.
- PDFio has a compact object lifecycle: create object, create stream when needed,
  close object once, then write pages, xref, trailer, `startxref`, and EOF.
- Cairo writes late objects in a deliberate order: patterns, font subsets, pages,
  document interchange objects, page dictionaries, catalog, xref, and trailer.

MarkdownPDF implication: introduce Swift value types for `PDFObject`, `PDFRef`,
`PDFName`, `PDFString`, `PDFArray`, `PDFDictionary`, and `PDFStream`, backed by a
single `PDFWriter` that owns object numbering, stream lengths, offsets, xref, and
trailer creation. Keep legacy xref tables first. Xref streams can wait.

## Content stream API

MarkdownPDF should stop spreading raw content operators across layout code.

Portable source evidence:

- HexaPDF `Canvas` tracks graphics state, text object state, current point,
  resource use, and operators.
- PDFio exposes one function per common content operator: paths, rectangles,
  colors, save/restore, text begin/end, text matrix, text show, images, and
  marked content.
- dart_pdf routes widgets through graphics objects rather than string-concatenated
  PDF commands.
- OpenPDF uses separate content layers for table backgrounds, lines, and text,
  then composes them back into the page canvas.

MarkdownPDF implication: add a typed `PDFContentStream` builder. It should know
whether a text object is open, track save/restore depth, escape or hex-encode
strings centrally, and record resource usage. Layout should emit draw commands,
not hand-written PDF snippets.

## Font embedding and ToUnicode

Font embedding is the highest-risk portable feature. It is not just writing a
font file into a stream.

Portable source evidence:

- HexaPDF maps original glyph IDs to subset glyph IDs, includes compound glyph
  components recursively, and writes glyf, loca, hmtx, head, hhea, and maxp table
  data for subsets.
- HexaPDF also builds ToUnicode and CID CMaps from sorted mappings and caps CMap
  sections at 100 entries.
- dart_pdf uses Type0 fonts for Unicode text: Type0 font, descendant
  CIDFontType2, `/Identity-H`, `/CIDToGIDMap /Identity`, `/ToUnicode`, widths,
  font descriptor, and a subset font stream.
- ReportLab dynamically assigns characters into subsets, freezes the subset set
  before final object writing, adds widths and a ToUnicode CMap, and optionally
  uses shaping when HarfBuzz is present.
- Cairo's TrueType path builds a subset font stream, font descriptor, either
  WinAnsi TrueType or Type0/CIDFontType2 dictionaries, widths, and ToUnicode.
  Its comments call out unsupported vertical and synthetic font cases.
- OpenPDF writes Type0/CIDFontType2 fonts, descriptor, optional CIDSet, TrueType
  or CFF subset streams, widths, and ToUnicode.

MarkdownPDF implication: start with a portable TrueType subset for horizontal
text, Type0/CIDFontType2, `/Identity-H`, `/CIDToGIDMap /Identity`, widths,
descriptor, and ToUnicode. Keep base fonts as default. Do not commit font files.
Use external or temporary test fonts only if their license is clear.

Important boundary: font embedding is not full text shaping. Complex scripts,
bidirectional text, hyphenation, variation fonts, color fonts, and vertical text
are separate problems. The portable core can add embedded Latin and symbol-heavy
scientific documents before claiming full international typography.

## Layout, pagination, and tables

MarkdownPDF currently lays out and draws many blocks directly. Tables are drawn
as equal-width columns with immediate row rendering. That is too tight for
repeated headers, row splitting, ToC anchors, and later tags.

Portable source evidence:

- dart_pdf `MultiPage` measures widgets against constraints, handles
  `SpanningWidget` state, saves and restores spanning context, then paints after
  the page split is chosen.
- dart_pdf tables compute intrinsic and flex column widths, row heights, repeated
  rows, and continuation state before painting.
- HexaPDF `TableBox` models cells, row spans, column spans, header rows, footer
  rows, split table parts, and a `fit_rows` pass for available height.
- ReportLab Platypus flowables have `wrap`, `split`, and `drawOn`; frames ask a
  flowable how large it is before drawing. ReportLab tables calculate widths,
  heights, spans, row positions, and split rows.
- OpenPDF table pagination subtracts header and footer height, scans measured row
  heights, can split a row, and creates a shallow continuation table containing
  only rows that fit.
- QuestPDF and Apache FOP, covered in the previous note, confirm the same idea:
  choose a space plan before painting.

MarkdownPDF implication: introduce a measured layout model before adding
article-grade tables. A practical shape is `LayoutNode` for document structure,
`LayoutFragment` for page-positioned fragments, and `DrawCommand` for final PDF
painting. Tables should become spanning layout nodes with measured columns, row
heights, repeat-header policy, and a clear row split policy.

## ToC, outlines, links, and tagged PDF

ToC and outlines depend on stable layout anchors. They should not be bolted onto
the current drawing pass.

Portable source evidence:

- ReportLab's `TableOfContents` draws the previous build's entries and checks
  whether the current pass matches the last pass. That is a direct signal that a
  ToC can require repeated layout until page numbers stabilize.
- ReportLab separates bookmarks from outline entries. A bookmark binds a key to a
  page destination, and an outline entry points to that key.
- Cairo's tagged PDF test creates heading destinations, outline items, a ToC
  destination, ToC links, document tags, metadata, and link annotations.
- PDFio exposes marked content and sets catalog `MarkInfo`, while leaving the
  caller responsible for `StructTreeRoot`.
- OpenPDF has tagged PDF and structure-tree support, but it is a large subsystem.
- Typst, covered earlier, builds outlines and tags from its document model rather
  than from late string rendering.

MarkdownPDF implication: first add layout anchors for headings and link targets.
Then add destinations and outline dictionaries. Add ToC by using a two-pass or
converging-pass layout. Tagged PDF should come later, but the layout model should
keep enough structure to assign MCIDs when that work starts.

## Images, SVG, charts, graphs, and Mermaid

MarkdownPDF currently supports JPEG image objects. The portable path can grow
without an external renderer if graphics are represented as vector draw commands
or image XObjects.

Portable source evidence:

- PDFio and ReportLab handle image XObjects and page resource dictionaries.
- Cairo has separate image emitters for JPEG, JPX, CCITT, JBIG2, and fallback
  image surfaces.
- dart_pdf includes a pure Dart SVG parser/painter and chart widgets that emit
  vector PDF operations.
- Skia and Cairo both prove that vector graphics can be lowered into PDF content
  streams without a browser.

MarkdownPDF implication: SVG and charts should feed the same `DrawCommand` and
`PDFContentStream` path. Under repository rules, Mermaid cannot be converted by
JavaScript, a browser, or an external renderer in the implementation. Allowed
portable choices are either accept pre-rendered SVG/image input, or later write a
limited Swift Mermaid parser for a documented subset.

## Validation and testing

Fast tests should validate the PDF structure instead of comparing pixels.

Existing `PDFInspector` already parses stream lengths, page count, link
annotation count, and xref offsets. Extend it before adding large features.

Suggested fast test targets:

- Object writer: every indirect object has an xref entry, xref offsets point at
  object headers, stream `/Length` values match bytes, trailer `/Size` is correct,
  and `startxref` points to `xref`.
- Resource dictionaries: page resources contain all fonts and images referenced
  by content streams, and no unreferenced resources are emitted for simple cases.
- Content stream builder: balanced `BT`/`ET`, balanced `q`/`Q`, valid text
  escaping or hex strings, deterministic number formatting.
- Tables: rows split across pages, headers repeat, row heights are deterministic,
  and no content stream draws outside the expected cell rectangles.
- Outlines and ToC: heading anchors produce destinations, outline count matches
  headings, ToC page numbers converge, and link annotations point to known
  destinations.
- Font embedding: Type0 font dictionaries contain descriptor, descendant font,
  widths, font stream, and ToUnicode. A tiny embedded-font fixture can be checked
  structurally without pixel rendering.
- Images: XObject dimensions, color space, bits per component, filter, and
  resource names match the input image.

Linux validation is mandatory. The same Swift tests should run under macOS and
Linux CI. Optional visual checks can exist locally, but they must not be the only
proof for PDF correctness.

## Recommended implementation order

1. Replace ad hoc writer internals with typed PDF object values and one object
   registry.
2. Add `PDFContentStream` typed operators with state checks and resource
   tracking.
3. Make page resources deterministic and separate resource creation from drawing.
4. Introduce measured layout nodes, page fragments, and draw commands.
5. Rework tables as spanning layout nodes with measured columns, row heights,
   repeated headers, and row split policy.
6. Add heading anchors, named destinations, outlines, and internal links.
7. Add ToC through a two-pass or convergence layout path.
8. Add portable Type0 TrueType subset embedding and ToUnicode.
9. Add SVG and charts as vector draw commands.
10. Revisit tagged PDF and PDF/A once layout nodes, anchors, and content streams
    are structured enough to support MCIDs and a structure tree.

## Risks

- Font embedding without shaping can still render simple Latin and scientific
  symbols well, but it must not be described as complete typography.
- ToC can change pagination. The renderer needs a convergence guard so a bad
  document cannot loop forever.
- Tagged PDF requires a real structure tree, MCIDs, parent tree, roles, and
  careful ordering. It is not just marked-content operators.
- C projects use memory and error-handling patterns that should not be translated
  mechanically into Swift.
- License review is required before copying any algorithmic code. This research
  note records architecture and behavior only.

## Conclusion

The deeper source pass points to one stable direction: build a portable document
model and PDF writer first, then layer article features on it. The strongest
near-term work is not a macOS renderer. It is a Swift object writer,
content-stream builder, measured layout model, and table pagination path that
behave the same on Linux and macOS.
