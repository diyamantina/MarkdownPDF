# MarkdownPDF portable PDF output profile

Date: 2026-06-01

This document records the generated PDF profile that MarkdownPDF currently
emits from the portable Swift renderer. It is an implementation profile, not a
research target. If source and this document disagree, source and tests win and
this document must be updated in the same change.

## Platform boundary

This profile applies to the `MarkdownPDF` and `MarkdownPDFLinux` products. The
`MarkdownPDFMac` product currently delegates to the same portable renderer.

The profile is portable across macOS and Linux. It is not a macOS-only profile
and it does not use PDFKit, CoreGraphics, CoreText, WebKit, browser renderers,
LaTeX, JavaScript, Python, shell renderers, C Markdown libraries, or C PDF
libraries.

iOS support is not claimed. A macOS result does not imply iOS support until an
iOS target exists and is tested.

## Compatibility target

The Markdown compatibility target is CommonMark plus GitHub Flavored Markdown
tables and images.

The PDF compatibility target is a conservative PDF 1.4 file:

- Complete non-incremental PDF file.
- PDF 1.4 header.
- Classic xref table.
- Trailer dictionary with `/Size`, `/Root`, and optional `/Info`.
- Catalog plus a flat page tree.
- Page dictionaries with direct resource dictionaries.
- One content stream per page.
- Exact stream `/Length` values.
- Standard PDF base fonts by default.
- Optional image XObjects for supported standalone local JPEG and PNG images.
- Link annotations for URI links and internal destination links.
- Named destinations, outlines, metadata, and generated ToC when input and
  options require them.
- Optional tagged PDF structure when `PDFOptions.taggedPDF` is enabled or a
  conformance profile requires it.
- Optional PDF/UA-1 identification when `PDFOptions.conformance == .pdfUA1`.
- Optional PDF/A-2a identification when `PDFOptions.conformance == .pdfA2A`,
  or combined PDF/UA-1 plus PDF/A-2a identification when
  `PDFOptions.conformance == .pdfUA1AndPDFA2A`.

The default profile does not claim PDF/A, PDF/UA, linearized PDF, incremental
updates, encryption, digital signatures, object streams, xref streams,
JavaScript actions, SVG import, or arbitrary Mermaid language support. PDF/UA-1
and PDF/A-2a are claimed only for their opt-in conformance paths, which require
tagged structure, embedded font programs for rendered text, document title
metadata, and a veraPDF witness.

## File envelope

Every generated file starts with:

```text
%PDF-1.4
%....
```

The second line contains bytes above ASCII 127 so PDF readers treat the file as
binary.

Every generated file ends with a classic xref section and trailer:

```text
xref
0 N
0000000000 65535 f
...
trailer
<< /Size N /Root 1 0 R ... >>
startxref
byte-offset-of-xref
%%EOF
```

`startxref` is the byte offset of the `xref` keyword. All in-use objects use
generation 0. The canonical free xref entry is object 0, generation 65535.

The writer emits deterministic object numbers. Object order must not depend on
hash iteration order, filesystem order, random IDs, timestamps, locale, or
platform-specific state.

## Object order

The current writer reserves object 1 for the catalog and object 2 for the pages
root, then fills those objects after the rest of the document is known. The
serialized file still appears in object-number order.

The current order is:

1. Catalog object, reserved first and filled last.
2. Pages root object, reserved second and filled after page refs are known.
3. Font allocation in `StandardFont.allCases` order. Base Type1 fonts allocate
   one font object. Non-Type1 opt-in font sets allocate a descriptor object
   immediately before the corresponding font object.
4. Image XObjects used by page resources, in renderer image-registration order.
5. Page content stream and link annotation objects for each page.
6. Page dictionary object for each page.
7. Outline root and outline item objects when headings exist.
8. Metadata `/Info` dictionary and XMP metadata stream when `PDFOptions.title`
   is non-empty or `PDFOptions.conformance` requires a metadata declaration.
9. Tagged structure objects when `PDFOptions.taggedPDF` is enabled or
   `PDFOptions.conformance` requires tagged structure:
   `/StructTreeRoot`, `/ParentTree`, and `/StructElem` objects.

The minimal one-page text PDF has five in-use objects:

1. Catalog.
2. Pages root.
3. One font object.
4. One content stream.
5. One page dictionary.

The trailer `/Size` is one greater than the highest object number because object
0 is the free xref entry.

## Catalog

The minimal catalog is:

```text
<< /Type /Catalog /Pages 2 0 R >>
```

Optional entries are emitted only when the corresponding feature is active:

- `/Outlines` and `/PageMode /UseOutlines` when headings produce outline items.
- `/Names << /Dests ... >>` when headings produce named destinations.
- `/Metadata` when `PDFOptions.title` or `PDFOptions.conformance` produces an
  XMP metadata stream.
- `/OutputIntents` with an embedded sRGB ICC profile when
  `PDFOptions.conformance` enables PDF/A-2a.
- `/MarkInfo`, `/StructTreeRoot`, and `/Lang` when `PDFOptions.taggedPDF` is
  enabled or a conformance profile requires tagged structure.
- `/ViewerPreferences << /DisplayDocTitle true >>` when title metadata exists or
  tagged PDF structure is enabled. PDF/UA-1 also requires this entry.

The catalog does not emit `/OpenAction` or JavaScript. It emits output intents
and PDF/A conformance declarations only for the opt-in PDF/A-2a path.

## Page tree and pages

The page tree is flat:

```text
<< /Type /Pages /Kids [page-ref ...] /Count page-count >>
```

Each page dictionary contains:

```text
<< /Type /Page
/Parent pages-ref 0 R
/MediaBox [0 0 width height]
/Resources << ... >>
/Contents content-ref 0 R
optional /StructParents integer
>>
```

`/Annots` is present only when a page has link annotations. Empty annotation
arrays are omitted.

`/StructParents` is present only when `PDFOptions.taggedPDF` is enabled and the
page owns marked content.

Heading destinations are recorded during layout and then used by document-level
named destinations and outline objects. They do not add keys to page
dictionaries by themselves.

## Resources

Resource dictionaries are generated from typed page resource usage, not by
scanning stream strings after the fact.

The current page resource dictionary supports:

- `/Font` for text resources.
- `/XObject` for local image resources.

Unsupported resource categories are omitted until implemented. This includes
`/ExtGState`, `/ColorSpace`, `/Pattern`, `/Shading`, `/Properties`, form
XObjects, and embedded file resources.

Resource names are deterministic:

| Resource | Names |
|---|---|
| Regular text font | `/F1` |
| Bold text font | `/F2` |
| Italic text font | `/F3` |
| Monospaced text font | `/F4` |
| Images | `/Im1`, `/Im2`, and so on in first-use order |

Each page declares only resources used by that page.

## Content streams

Every page has one content stream. By default the stream is uncompressed and the
dictionary contains an exact `/Length`; tests compare declared and actual byte
counts.

When `PDFOptions.streamCompression` is enabled, page content streams are encoded
with a Pure Swift zlib-wrapped DEFLATE profile and `/Filter /FlateDecode` only
when the encoded stream is smaller than the raw stream. The emitted `/Length` is
the encoded byte count. The default output remains uncompressed.

Content streams use typed PDF operators for text, paths, rectangles, lines,
images, colors, graphics state save/restore, and XObject drawing.

The renderer currently emits visible content for:

- Headings.
- Paragraphs.
- Block quotes.
- Ordered and unordered lists.
- Fenced code blocks.
- Tables as visual cell borders and text. When `PDFOptions.taggedPDF` is
  enabled, the same visible table receives Table, TR, TH, and TD structure
  elements.
- Thematic breaks.
- Raw HTML as visible monospaced text, not interpreted HTML.
- Inline emphasis, strong text, strike-through, inline code, links, images as
  inline labels, and line breaks.
- Supported portable Mermaid flowcharts.
- Visible generated table of contents when enabled.

Long tokens are split by measured font width before they exceed the line width.
This protects headings, ToC entries, URLs, and identifiers from colliding with
page bounds or neighboring text.

## Tagged structure

Tagged structure is opt in through `PDFOptions.taggedPDF` and is automatically
enabled by `PDFOptions.conformance == .pdfUA1`. The writer emits:

- Catalog `/MarkInfo << /Marked true >>`.
- Catalog `/Lang`, defaulting to `en-US`.
- Catalog `/StructTreeRoot`.
- Page `/StructParents` keys for pages that contain marked content.
- BDC/EMC marked-content sections with deterministic per-page MCIDs.
- `/StructTreeRoot`, `/ParentTree`, and `/StructElem` objects.

The first tagged profile maps Markdown blocks to standard PDF structure roles:
H1 through H6, P, BlockQuote, L, LI, Lbl, LBody, Table, TR, TH, TD, Figure,
TOC, and TOCI. Code blocks use `/Code` and a RoleMap entry to `/Span`.

Figure elements receive `/Alt` from Markdown image alt text, chart titles, or a
deterministic fallback description. Table header cells receive column scope.
Decorative rules, table cell borders, code block backgrounds, and ToC leaders
are emitted as `/Artifact` marked content.

The structure-only path does not claim PDF/UA or PDF/A conformance. The
PDF/UA-1 conformance path additionally requires a non-empty document title and
embedded font programs for every rendered text role, emits `pdfuaid` XMP
identification, and is validated with `verapdf -f ua1 --format json`. The
PDF/A-2a path emits an sRGB output intent, `pdfaid` XMP identification, and a
deterministic trailer `/ID`; the combined path also includes the PDF/UA XMP
extension schema required by PDF/A.

The tagged witness suite validates RTL PDF/UA and CJK plus diacritic combined
PDF/UA plus PDF/A fixtures with veraPDF, qpdf, and Poppler text extraction.

## Tables

Tables render as portable PDF page content: stroked cell rectangles, optional
header fill rectangles, and text runs. When tagged output is enabled, the visual
table also emits Table/TR/TH/TD structure elements and artifacts for the cell
borders and header fill.

Column widths are measured from the header cells and all body rows before the
table is drawn. The width plan uses standard-font text metrics to compute a
minimum width and a preferred width per column, then distributes the available
content width deterministically. Wide prose columns can receive more space than
short identifier or numeric columns, while every column remains bounded by the
page content width.

Cell text wraps inside its measured column. Long no-space tokens are split by
the same measured-token policy used by paragraphs and headings. Alignment
markers are preserved per column:

- Leading columns draw from the left cell padding.
- Center columns center each wrapped line in the cell.
- Trailing columns draw each wrapped line against the right cell padding.

Rows split by wrapped cell-line fragments when a row is taller than the
remaining page space. Body pages repeat the prepared header after a page break
when the table continues. If a header itself consumes too much page space, the
renderer avoids an infinite repeat and continues on a fresh page.

The measured table witness fixture covers mixed alignments, dense prose cells,
long no-space tokens, a tall row that splits across page boundaries, repeated
headers, qpdf syntax validation, Poppler text and geometry, MuPDF character
quads, and all-page Poppler/MuPDF raster comparison. macOS and Linux use the
same portable table algorithm. iOS support is not claimed.

## Text encoding

The portable base-font profile emits PDF literal strings and font dictionaries
with `/WinAnsiEncoding`, but the supported visible text repertoire is intentionally
smaller: printable ASCII U+0020 through U+007E, plus escaped PDF literal string
controls for backspace, tab, line feed, form feed, and carriage return.

Every unsupported Unicode scalar is replaced with `?` before text is measured and
serialized. This includes Latin-1 letters, Windows-1252 punctuation, emoji,
combining marks, CJK, complex scripts, and bidirectional text. Replacement is per
Unicode scalar, not per user-perceived grapheme cluster.

The profile does not emit `/ToUnicode` CMaps. Poppler and MuPDF text extraction
are expected to expose the replacement characters, not recover the original
unsupported input. qpdf validates syntax and stream structure but does not act as
a text extraction witness. macOS and Linux use the same replacement profile. iOS
support is not claimed.

## Oversized blocks

The portable layout profile must not rely on a permissive PDF viewer clipping
content that falls outside the page body. Block kinds use explicit overflow
policies:

- Paragraphs, list item bodies, block quote bodies, raw HTML fallback, generated
  ToC entries, and remote image fallback labels split through the shared wrapped
  line renderer. Each line reserves page space before it is drawn.
- Code blocks split by wrapped code line fragments. Each fragment gets its own
  code background rectangle and never reserves more than the available page body.
- Table rows split by wrapped cell-line fragments when one row is taller than the
  usable page body. Continued table pages repeat the prepared header when the
  table body crosses a page break.
- Mermaid diagrams render as vector drawing commands only when the measured plan
  fits the page body. Too-tall or too-wide diagrams fall back to a visible code
  block, so the split code-block policy applies.
- Local standalone images scale to the content width and to the smaller of 45%
  of page height or the usable page body height. Remote images stay as wrapped
  fallback text.
- Thematic breaks reserve their fixed height before drawing.

The witness fixture for this policy renders a document with a body height smaller
than the previous local-image cap, a table row taller than the body, a Mermaid
diagram that falls back because it is taller than one page, and a multi-page code
block. qpdf, Poppler text and geometry, MuPDF structured text, and Poppler/MuPDF
rasters inspect the output on macOS and Linux.

## Fonts

The default font profile uses standard PDF base font names and does not embed
font files:

- Helvetica.
- Helvetica-Bold.
- Helvetica-Oblique.
- Courier.

Base-font output must not contain `/FontFile`, `/FontFile2`, or `/FontFile3`.

`PDFOptions.FontSet.appleSystem` is an opt-in font-name surface. It emits simple
unembedded TrueType font dictionaries with deterministic widths and font
descriptors, but it does not load Apple frameworks and it does not embed font
bytes. Reader output can depend on font substitution when those names are not
installed.

The current profile does not implement:

- Embedded font files.
- Font subsetting.
- Type0 composite fonts.
- CIDFontType2 descendants.
- `/ToUnicode` CMaps.
- Complex-script shaping.
- Bidirectional text.
- Color fonts.

Future embedded-font work must introduce a separate tested profile and must not
commit font files to the public repository without an explicit policy change.
See `portable-embedded-fonts-tounicode-plan.md` for the staged portable plan.

## Images

Standalone local images are represented as image XObjects. Image resources are
reused when the same source path appears more than once.

Supported image inputs:

- JPEG, emitted with `/Filter /DCTDecode`.
- PNG without unsupported alpha/interlace modes, emitted with `/Filter
  /FlateDecode` and matching `/DecodeParms`.

Remote images are not fetched. Standalone remote images render as visible
placeholder text. Inline images render as visible labels.

Unsupported or invalid image data throws `MarkdownPDFError`.

## Links and navigation

External Markdown links become URI link annotations:

```text
<< /Type /Annot
/Subtype /Link
/Rect [x0 y0 x1 y1]
/Border [0 0 0]
/A << /S /URI /URI (...) >>
>>
```

Internal Markdown fragment links whose destination starts with `#` are
normalized to heading destination names. If a matching destination exists, the
annotation emits `/Dest (name)`. If no matching destination exists, the original
fragment remains a URI action so the link is visible rather than silently
discarded.

Heading anchors use deterministic ASCII slugs derived from visible heading text.
Duplicate headings get numeric suffixes such as `intro-2`.

Named destinations are emitted under the catalog `/Names` dictionary:

```text
/Names << /Dests << /Names [(details) [page-ref 0 R /XYZ x y null]] >> >>
```

Named destinations are sorted by destination name for deterministic output.

Outlines are emitted when headings exist. The outline root hangs from the
catalog through `/Outlines`; outline items use `/Title`, `/Parent`, `/Dest`, and
the sibling or child links required by their tree position. The outline tree
follows Markdown heading levels.

## Generated table of contents

Generated ToC is opt in:

```swift
let options = PDFOptions(tableOfContents: .enabled)
```

The ToC is a layout feature built from final heading destinations:

- If the document starts with an H1, the ToC is inserted after that heading.
- Otherwise the ToC is inserted before the first block.
- Entries are derived from headings in source order.
- `maximumDepth` filters heading levels from 1 through 6.
- Entry titles use visible heading text.
- Entry page numbers are final rendered page numbers.
- Entry links point at existing heading named destinations.

The renderer first lays out the document without a ToC to collect heading
destinations. It then lays out with ToC entries and repeats until the ToC page
numbers match final heading pages. The convergence guard is six passes. If page
numbers do not converge, rendering throws
`MarkdownPDFError.tableOfContentsDidNotConverge`.

The ToC does not create its own heading destination or outline item.

## Mermaid diagrams

Portable Mermaid support is intentionally a subset.

Supported:

- `flowchart` and `graph` diagrams.
- Mermaid `pie` charts through the native chart renderer.
- `TD`, `TB`, `BT`, `LR`, and `RL` directions.
- One statement per line.
- Node declarations with plain or quoted labels.
- Directed edges with optional labels.

Unsupported Mermaid syntax renders as a visible code-block fallback beginning
with `Unsupported Mermaid diagram:`. The renderer does not call Node, browsers,
shell renderers, Apple APIs, or external conversion tools.

Supported Mermaid output is ordinary PDF page content: paths, rectangles,
strokes, arrow lines, and text. It does not emit SVG, images, form XObjects, or
platform-specific drawing commands.

Mermaid edge labels are measured during planning. A supported diagram only draws
when each label box stays inside the diagram content area and does not intersect
any planned node box. If an edge label cannot be placed safely, the whole
Mermaid block falls back visibly rather than rendering overlapping text.

Native chart support covers Mermaid `pie` plus fenced `chart` blocks for bar,
line, and scatter charts. Supported charts emit typed PDF drawing operations in
Swift: rectangles, paths, cubic Bezier arcs, polylines, markers, and text. Other
Mermaid chart syntaxes remain visible fallback text until they pass the same
witness stack.

## Metadata

When `PDFOptions.title` is non-empty or `PDFOptions.conformance` is enabled,
the writer emits:

- Trailer `/Info` reference.
- `/Title` and `/Producer` in the info dictionary.
- XMP `/Metadata` stream referenced by the catalog.
- `/ViewerPreferences << /DisplayDocTitle true >>`.

`/Producer` is deterministic and currently `MarkdownPDF`. The PDF/UA-1
conformance path writes `pdfuaid:part` with value `1` in XMP. The PDF/A-2a path
writes `pdfaid:part` with value `2` and `pdfaid:conformance` with value `A`.

The default profile does not emit document `/ID` values. The PDF/A-2a path emits
a deterministic trailer `/ID`.

## Validation requirements

Generated PDFs are considered acceptable only after independent witnesses check
them. Compilation and string inspection are not enough.

The normal witness stack is:

1. Swift structural inspection through `PDFInspector`.
2. `qpdf --check`.
3. Poppler `pdfinfo`, `pdftotext`, `pdftotext -tsv`, and `pdftoppm`.
4. MuPDF `mutool draw -F stext` and `mutool draw -F pnm`.
5. All-page raster comparison between Poppler and MuPDF output.

The witness stack must fail on:

- Bad header or EOF marker.
- Broken xref offsets.
- Wrong trailer `/Size`.
- Missing catalog or page tree objects.
- Page tree `/Count` mismatches.
- Missing page `/Parent`, `/MediaBox`, `/Resources`, or `/Contents`.
- Stream `/Length` mismatches.
- Undeclared font or XObject usage.
- Missing resource objects.
- Link annotations without URI actions or valid destinations.
- Named destinations pointing at missing pages.
- Outline items pointing at invalid pages.
- Non-positive text boxes.
- Text outside page bounds.
- Same-line word overlap.
- Same-word glyph overlap.
- Vertical line collisions.
- Blank raster output.
- Divergent Poppler and MuPDF ink bounds.

Layout-affecting changes must use representative fixtures with multiple pages,
dense prose, inline styles, lists, tables, links, code blocks, Mermaid diagrams,
generated ToC, long tokens, and page breaks.

## CI tools

Linux CI installs:

- `qpdf`.
- `poppler-utils`.
- `mupdf-tools`.
- `veraPDF`.

macOS CI installs:

- `qpdf`.
- `poppler`.
- `mupdf`.
- `verapdf`.
- `font-urw-base35`.

macOS CI refreshes fontconfig after installing Base35 fonts so Poppler raster
checks can paint standard PDF base fonts.

Known witness differences belong in the test layer unless generated bytes truly
need to differ by platform. Current production rendering has no Linux-specific
PDF byte branch.

## Deferred profile decisions

The following remain future profiles or unsupported features:

- PDF 1.5 or later object streams and xref streams.
- Incremental update writing.
- Linearization.
- Encryption and permission dictionaries.
- Digital signatures.
- Complex-script shaping and bidirectional text.
- SVG import.
- General chart or graph rendering beyond the documented Mermaid subset.
- Form XObjects.
- Color management beyond device color spaces used by current content.
- Remote image fetching.

Deferring these keeps the portable writer small enough to validate on macOS and
Linux with the current witness stack.
