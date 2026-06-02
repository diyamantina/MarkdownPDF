# Canonical PDF document structure

Date: 2026-05-31

This note records the PDF document structure that the ISO specification and the
source-available writers inspected for MarkdownPDF agree on. It is a structural
reference for the portable Swift writer, not an implementation change.

## Scope

This applies to Linux and macOS output from the portable MarkdownPDF renderer. It
is not macOS-only and not iOS-only. No item in this note requires PDFKit,
CoreGraphics, CoreText, WebKit, a browser, LaTeX, C PDF libraries, or an
external renderer.

The source of truth for PDF terminology is ISO 32000. This note uses the section
names from ISO 32000-1:2008:

- 7.5, File Structure
- 7.7, Document Structure
- 7.8, Content Streams and Resources
- 9, Text
- 12, Interactive Features
- 14, Document Interchange

The Adobe-hosted ISO 32000-1 PDF and the Adobe PDF Reference archive are useful
public references for the same structure.

## Source evidence

The same high-level structure appears across unrelated implementations:

| Project | Local source path | Useful evidence |
|---|---|---|
| MarkdownPDF | `Packages/Sources/MarkdownPDF/PDFDocumentWriter.swift` | Current writer emits `%PDF-1.4`, catalog, pages, page dictionaries, content streams, resources, classic xref, trailer, `startxref`, and `%%EOF`. |
| pydyf | `researchcode/pydyf/pydyf/__init__.py` | Small object model with dictionaries, streams, pages, catalog, xref table or xref stream, trailer, and EOF marker. |
| fpdf2 | `researchcode/fpdf2/fpdf/syntax.py`, `researchcode/fpdf2/fpdf/output.py`, `researchcode/fpdf2/fpdf/outline.py` | Typed PDF syntax, delayed object IDs, classic xref table, trailer, page objects, fonts, structure tree, outlines, and ToC support. |
| pdf-writer | `researchcode/pdf-writer/src/chunk.rs`, `researchcode/pdf-writer/src/structure.rs`, `researchcode/pdf-writer/src/content.rs`, `researchcode/pdf-writer/src/font.rs` | Typed writers for catalog, pages, page, resources, content streams, outlines, destinations, font descriptors, and streams. |
| HexaPDF | `researchcode/hexapdf/lib/hexapdf/writer.rb`, `researchcode/hexapdf/lib/hexapdf/serializer.rb`, `researchcode/hexapdf/lib/hexapdf/type/page_tree_node.rb`, `researchcode/hexapdf/lib/hexapdf/type/outline.rb`, `researchcode/hexapdf/lib/hexapdf/type/font_type0.rb` | Separates serialization, xref/trailer writing, page tree, outlines, and Type0 font structure. |
| PDFio | `researchcode/pdfio/pdfio-file.c`, `researchcode/pdfio/pdfio-page.c`, `researchcode/pdfio/pdfio-content.c` | C writer with catalog, pages, page dictionaries, resources, content streams, xref reading/writing, Type0/CIDFontType2 fonts, and ToUnicode. |
| PDFBox | `researchcode/pdfbox/pdfbox/src/main/java/org/apache/pdfbox/pdfwriter/COSWriter.java`, `researchcode/pdfbox/pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDType0Font.java` | COS writer handles offsets, xref, trailer, and EOF; Type0 font code wraps descendant CID fonts and ToUnicode behavior. |
| libHaru | `researchcode/libharu/src/hpdf_xref.c`, `researchcode/libharu/src/hpdf_pages.c`, `researchcode/libharu/src/hpdf_font_tt.c` | Compact C writer with xref entries, trailer, pages tree, page dictionaries, content streams, resources, and embedded font descriptors. |
| Matplotlib | `researchcode/matplotlib/lib/matplotlib/backends/backend_pdf.py` | Direct PDF backend for charts with resource dictionaries, vector paths, images, Type0 font output, xref, trailer, and EOF. |

These projects differ in object order, compression, xref stream support, layout
engines, and font engines. They still converge on the same graph: trailer to
catalog, catalog to pages, pages to page objects, page objects to content and
resources.

## File envelope

A complete non-incremental PDF file has this outer structure:

```text
%PDF-1.4
% binary-marker-comment

1 0 obj
  catalog dictionary
endobj

2 0 obj
  pages dictionary
endobj

3 0 obj
  page dictionary
endobj

4 0 obj
  stream dictionary
stream
  content stream bytes
endstream
endobj

xref
0 5
0000000000 65535 f
0000000015 00000 n
...
trailer
<< /Size 5 /Root 1 0 R >>
startxref
byte-offset-of-xref
%%EOF
```

The header identifies the file as PDF and declares a version. A binary marker
comment after the header is common when the file contains non-ASCII bytes.

The body is a sequence of numbered indirect objects. Each indirect object has an
object number, a generation number, an object value, and an `endobj` terminator.
Most generated files use generation 0 for all in-use objects.

The cross-reference data lets a PDF processor seek directly to indirect objects.
The classic xref table stores byte offsets for object headers. Cross-reference
streams are a later PDF feature and store equivalent lookup data in a stream
object. They are useful for compression and large files, but they are not
required for MarkdownPDF's initial writer.

The trailer dictionary points to the document root and records enough file-level
state for a reader to load the document. The required first baseline is `/Size`
and `/Root`. `/Info`, `/ID`, `/Encrypt`, and `/Prev` are optional or feature
dependent.

`startxref` stores the byte offset of the last cross-reference section or
cross-reference stream. `%%EOF` marks the end of the file.

Incremental updates append a new body section, a new cross-reference section, and
a new trailer with `/Prev` pointing to the earlier xref. MarkdownPDF writes a
complete file and does not need incremental updates for its first profile.

## Document graph

After a PDF processor locates the trailer, it follows `/Root` to the document
catalog:

```text
trailer
  /Root -> Catalog

Catalog
  /Pages -> Pages root
  /Outlines -> Outline dictionary, optional
  /Names -> Name trees, optional
  /Metadata -> XMP metadata stream, optional
  /MarkInfo -> Tagged PDF marker, optional
  /StructTreeRoot -> Structure tree, optional

Pages root
  /Kids -> Page or Pages nodes
  /Count -> total leaf page count

Page
  /Parent -> Pages node
  /MediaBox -> page rectangle
  /Resources -> names used by content streams
  /Contents -> content stream or array of streams
  /Annots -> annotations, optional

Content stream
  PDF graphics and text operators

Resources
  /Font -> font resource names
  /XObject -> images and form XObjects
  /ExtGState -> graphics states
  /ColorSpace -> named color spaces
  /Pattern -> patterns
```

The catalog is the root of the document object graph. The catalog must point to
the page tree through `/Pages`.

The page tree may be deep or flat. A flat `/Pages` node with every page listed in
`/Kids` is valid for MarkdownPDF's early output. Deeper trees matter for very
large documents or editing workflows.

A page dictionary represents one visible page. The required practical baseline is
`/Type /Page`, `/Parent`, `/MediaBox`, `/Resources`, and `/Contents`.

A content stream is a PDF stream object. Its dictionary includes `/Length`; the
stream body contains operators such as path, color, image, and text commands.
Compression is optional. If compression is used, `/Filter` and any decode
parameters must match the bytes.

A resource dictionary binds names from content streams to indirect objects. For
example, `/F1 12 Tf` in a content stream uses `/F1` from the page's `/Font`
dictionary. The writer should track resources structurally while emitting draw
commands. Regex discovery after content generation is fragile and should not be
the MarkdownPDF design.

## Text and fonts

PDF text is content stream state plus font resources. The common operator
baseline is:

| Operator | Role |
|---|---|
| `BT` and `ET` | Begin and end a text object. |
| `Tf` | Select a font resource and size. |
| `Tm` | Set the text matrix. |
| `Td` | Move the text position. |
| `Tj` | Show one string. |
| `TJ` | Show strings with per-run positioning adjustments. |
| `Ts` | Set text rise for superscript or subscript-like placement. |

Standard PDF base fonts are the simplest portable baseline. They are referenced
by name and do not require embedding font program bytes. MarkdownPDF's default
profile should keep base fonts as the default path.

Article-grade embedded Unicode text normally uses this object graph:

```text
Page /Resources /Font
  /F5 -> Type0 font

Type0 font
  /Subtype /Type0
  /BaseFont /ABCDEF+FontName
  /Encoding /Identity-H
  /DescendantFonts [CIDFont]
  /ToUnicode -> CMap stream

CIDFont
  /Subtype /CIDFontType2
  /BaseFont /ABCDEF+FontName
  /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>
  /FontDescriptor -> FontDescriptor
  /W -> widths
  /CIDToGIDMap -> map stream or /Identity

FontDescriptor
  /FontName /ABCDEF+FontName
  /Flags, /FontBBox, /Ascent, /Descent, /ItalicAngle, /CapHeight, /StemV
  /FontFile2 -> TrueType subset stream

ToUnicode CMap stream
  maps emitted character codes back to Unicode
```

For CFF/OpenType CFF fonts, the descendant is usually CIDFontType0 and the font
file is usually `/FontFile3` with a suitable subtype. That is a later profile for
MarkdownPDF.

Important terms:

- Unicode scalar: the text value from Markdown.
- Glyph ID: an index into a font program.
- CID: a character identifier used by a CID-keyed PDF font.
- Character code: the bytes emitted in a PDF text string.
- Subset code: the code assigned by the PDF writer for a glyph in a subset.

Font embedding is not full text shaping. Shaping decides which glyphs and
positions represent Unicode text for a script and font. Font embedding stores the
font program and maps emitted codes back to Unicode. MarkdownPDF can implement
embedded horizontal TrueType for Latin and scientific text before it claims full
complex-script typography.

## Navigation and metadata

Outlines, destinations, links, and metadata are optional PDF structures, but they
are central to article-grade output.

The outline dictionary hangs from the catalog through `/Outlines`. Outline items
form a linked tree with `/Parent`, `/Prev`, `/Next`, `/First`, `/Last`, `/Count`,
`/Title`, and either destination or action entries.

Destinations can be direct destination arrays or named destinations. A heading
destination normally points to a page and a position on that page. This is why
ToC and outline generation must come after layout has stable heading anchors.

Link annotations hang from page dictionaries through `/Annots`. A URI link uses
`/Subtype /Link`, `/Rect`, optional border styling, and an action dictionary such
as `/A << /S /URI /URI (...) >>`. Internal links should point to destinations.

The document information dictionary is referenced from the trailer through
`/Info`. XMP metadata is a metadata stream referenced from the catalog through
`/Metadata`. A later PDF/A profile will require stricter metadata and output
intent decisions than the baseline writer needs.

`/ID` in the trailer identifies the file instance. It matters for encryption,
signatures, incremental update workflows, and some validation profiles. It can be
deferred for the initial deterministic writer profile unless a validation target
requires it.

Tagged PDF uses marked content, marked-content IDs, `/MarkInfo`, a
`/StructTreeRoot`, and a parent tree. This should be designed after the layout
model carries enough semantic structure. The current canonical profile should
not pretend that untagged content is accessible tagged PDF.

## Current MarkdownPDF mapping

`PDFDocumentWriter` already maps to the canonical baseline:

- `Builder.build(root:)` writes the PDF header, object bodies, classic xref
  table, trailer, `startxref`, and EOF marker.
- `data()` reserves catalog and pages objects, writes standard font objects,
  image XObjects, page content streams, link annotations, page dictionaries, the
  pages dictionary, and the catalog dictionary.
- `resources(fontRefs:imageRefs:)` builds page resource dictionaries with `/Font`
  and optional `/XObject` entries.
- `addStream(dictionary:data:)` writes stream dictionaries with `/Length`.
- `addLinkAnnotation(_:)` writes URI link annotations.

Current tests already inspect the file prefix, base-font references, absence of
embedded font files, xref offsets, stream lengths, page count, and link
annotation count.

## Deferred features

The following are valid PDF features, but they are not part of the first
canonical MarkdownPDF profile:

- Cross-reference streams.
- Object streams.
- Incremental updates.
- Encryption.
- Digital signatures.
- Linearization.
- Tagged PDF.
- PDF/A and PDF/UA conformance.
- Embedded CFF/OpenType CFF fonts.
- Complex-script shaping and bidirectional layout.

Deferring them keeps the first writer profile small, deterministic, and testable
on Linux and macOS.

## Testing consequences

Structural tests should assert invariants that every PDF writer must satisfy:

- Header starts with the chosen PDF version.
- Every indirect object has exactly one xref entry.
- Every in-use xref offset points to the matching object header.
- Trailer `/Size` matches the xref entry count.
- Trailer `/Root` points to a catalog object.
- `startxref` points to the xref table or xref stream.
- Every stream `/Length` matches emitted bytes before compression, or decoded
  stream validation is explicit when compression is enabled.
- Page tree `/Count` matches the number of leaf page objects.
- Page dictionaries point to valid content streams and resource dictionaries.
- Resource names used in content streams are present in page resources.
- Link annotations have valid rectangles and valid action or destination entries.
- Future embedded-font tests inspect Type0 font, descendant CID font,
  FontDescriptor, FontFile2, widths, and ToUnicode mappings.

