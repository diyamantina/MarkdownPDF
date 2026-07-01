# Open source PDF library porting research

This note investigates open source PDF generators and adjacent renderers as
sources of algorithms that could be reimplemented in Swift. It does not propose
adding those libraries as dependencies.

## Scope

The package must build on Linux and macOS. The primary implementation must be
pure Swift and must not depend on Apple frameworks. OS-specific backends can be
future experiments, but they are not the design center for this research pass.

Porting policy:

- Prefer specification-driven Swift implementations.
- Study permissively licensed projects for architecture and algorithms.
- Do not paste translated code from other projects into this repo without a
  license review and attribution plan.
- Treat LGPL, MPL, AGPL, and proprietary code as research-only unless the user
  explicitly approves a legal path.
- Do not add C, C++, Java, Rust, Python, JavaScript, or browser renderer
  dependencies to this public Swift package.

## Candidate libraries

| Project | Language | License signal | Useful for Swift port? | Notes |
|---|---|---|---|---|
| Apache PDFBox | Java | Apache 2.0 | High | Object model, content streams, resources, Type 0 fonts, font subsets |
| Apache FOP | Java | Apache 2.0 | High | Area tree, pagination, tables, footnotes, output-independent layout |
| Typst compiler | Rust | Apache 2.0 | High | Modern PDF export, PDF/A, PDF/UA, tags, outlines, tables, layout ideas |
| Skia SkPDF | C++ | BSD | Medium | Drawing backend, resource collection, font subsetting, PDF limitations |
| libHaru | C | zlib/libpng style | Medium | Small PDF generator, outlines, annotations, images, font embedding |
| ReportLab | Python | BSD | Medium | High-level document model, flowables, canvas API, charts |
| Cairo PDF surface | C | LGPL/MPL | Low for code, medium for ideas | Vector surface backend and metadata model |
| OpenPDF/iText family | Java | LGPL/MPL or AGPL/proprietary variants | Low | Avoid code conversion unless license is approved |
| MuPDF | C | AGPL/commercial | Low | Renderer architecture only, not suitable for direct code translation |
| PDFium | C++ | BSD-style | Low | Large reader/rendering engine, not a focused PDF generator target |

## PDFBox

DOCUMENTED: PDFBox is an open source Java tool under Apache License 2.0. It can
create PDFs from scratch with embedded fonts and images.

Source:
https://pdfbox.apache.org/

DOCUMENTED: `PDPageContentStream` is a page content stream writer. Its source
shows append, prepend, overwrite, compression, resource propagation, and graphics
state reset behavior.

Source:
https://apache.googlesource.com/pdfbox/+/trunk/pdfbox/src/main/java/org/apache/pdfbox/pdmodel/PDPageContentStream.java

DOCUMENTED: `PDType0Font` supports loading TrueType fonts as Type 0 fonts,
adding Unicode code points to a subset, checking whether a font will be subset,
and replacing a font with the subset.

Source:
https://pdfbox.apache.org/docs/2.0.0/javadocs/org/apache/pdfbox/pdmodel/font/PDType0Font.html

DOCUMENTED: The PDFBox font guide says the standard 14 fonts are always
available for consumers, and recommends embedding fonts for portability.

Source:
https://svn.apache.org/repos/asf/pdfbox/site/publish/userguide/fonts.html?p=1507079

Swift-portable ideas:

- Model page content as a typed stream writer, not raw string concatenation.
- Make append/prepend/overwrite explicit states if editing support ever appears.
- Keep page resources close to the page and register fonts/images through a
  resource manager.
- For font embedding, track used Unicode scalars before finalizing the document.
- Make `subset()` a finalization step after all pages are laid out.

Risk:

- PDFBox is a large mature codebase. Translating classes directly would import a
  Java object model that does not match this Swift package.

Verdict: Study and reimplement the concepts in Swift. Do not translate large
files.

## Apache FOP

DOCUMENTED: Apache FOP lays XSL-FO content into pages and renders it to output,
with PDF as a main target. Its example includes static areas, graphics,
footnotes, and a table spanning two pages. The project is Apache-licensed.

Source:
https://xmlgraphics.apache.org/fop/index

Swift-portable ideas:

- Separate the area tree from the PDF renderer.
- Represent blocks, inline areas, tables, footnotes, and static page regions as
  layout results before serialization.
- Implement table pagination as a layout problem, not a stream-writing problem.
- Keep output-independent layout so Linux and macOS share pagination.

Risk:

- XSL-FO is far larger than MarkdownPDF's current scope.

Verdict: Port the area-tree idea, not the XSL-FO feature set.

## Typst

DOCUMENTED: Typst's compiler is open source under Apache 2.0 and can be used as
a Rust library. It exports PDF by default.

Source:
https://typst.app/open-source/

DOCUMENTED: Typst supports PDF version selection, PDF/A variants, PDF/UA-1,
tagged PDF by default, and additional checks for PDF/UA export.

Source:
https://typst.app/docs/reference/pdf/

Swift-portable ideas:

- Make PDF standard target an explicit option.
- Keep semantic document constructs available until PDF export so tags and
  accessibility can be written.
- Make complex table accessibility an explicit feature area.
- Treat PDF/A and PDF/UA as validation-bearing export modes.

Risk:

- Typst is a complete typesetting language and compiler. Its architecture is
  much broader than Markdown-to-PDF.

Verdict: Use as a modern reference for feature ordering and standards behavior.
Do not translate compiler internals directly.

## Skia SkPDF

DOCUMENTED: Skia's PDF backend accumulates drawing into a per-page device. When
the page ends, device content and resources are added to the owning document.
Document close serializes the PDF.

Source:
https://skia.org/docs/dev/design/pdftheory/

DOCUMENTED: SkPDF embeds fonts because arbitrary fonts cannot be assumed to exist
on the viewer machine. It uses glyph-id encoding, splits Type 1 or Type 3 fonts
into groups of 255 glyphs, and uses HarfBuzz subsetting for TrueType fonts.

Source:
https://skia.org/docs/dev/design/pdftheory/

DOCUMENTED: Skia's public PDF backend documentation distinguishes unsupported
features as drop, ignore, or expand. It notes that some expansion paths lose
text-as-text.

Source:
https://docs.skia.org/docs/user/sample/pdf/

Swift-portable ideas:

- Use a page-local drawing accumulator and a document-level resource registry.
- Make unsupported feature handling explicit.
- Preserve text as text whenever possible; document when text must become paths
  or raster.
- Track glyph ids separately from source Unicode.

Risk:

- Skia is a huge C++ graphics engine. Direct translation is not practical.

Verdict: Strong architecture source for the PDF backend, especially resource
collection and feature-fallback policy.

## libHaru

DOCUMENTED: libHaru is an ANSI C library for generating PDF files. It supports
lines, text, images, outlines, text annotations, link annotations, deflate,
JPEG/PNG images, Type 1 and TrueType font embedding, encryption, CJK fonts, and
encodings.

Source:
https://libharu.org/

Swift-portable ideas:

- A small PDF generator can stay understandable and still support outlines,
  annotations, images, compression, and embedded fonts.
- The feature list maps closely to MarkdownPDF's next milestones.

Risk:

- It is C, older, and its encoding model is not enough for modern Unicode goals.
- The site says the project needs maintainership, so avoid treating it as the
  primary modern reference.

Verdict: Useful for small-writer design and PDF object ordering. Not enough for
article-grade Unicode and accessibility.

## Cairo PDF surface

DOCUMENTED: Cairo's PDF surface is a multi-page vector backend and supports PDF
metadata and outlines in its API.

Source:
https://cairographics.org/manual/cairo-PDF-Surfaces.html

Swift-portable ideas:

- Model PDF output as a surface-like target with page lifecycle, metadata, and
  outline operations.
- Keep a clear abstraction between drawing API and PDF serialization.

Risk:

- Cairo is C and uses LGPL/MPL licensing. Direct code conversion needs legal
  review and is not aligned with this repo's no-C-library rule.

Verdict: Research-only for concepts.

## ReportLab

DOCUMENTED: ReportLab's open source toolkit is available under the BSD license
and focuses on generating PDF files and graphics.

Source:
https://docs.reportlab.com/developerfaqs/

Swift-portable ideas:

- A higher-level document layer can sit above a low-level canvas.
- Flowable-like blocks are a useful model for paragraphs, tables, figures, page
  breaks, and keep-with-next behavior.
- Charts can be implemented as vector drawing primitives over the same canvas.

Risk:

- ReportLab is Python and has a long-lived API with many features that are not
  needed here.

Verdict: Good source for document-flow concepts. Do not port APIs wholesale.

## What can be converted to Swift

High-confidence pure Swift ports:

- PDF object builder with typed object references.
- Content stream writer with typed operators.
- Page lifecycle state machine.
- Resource dictionary manager for fonts, images, annotations, and destinations.
- Layout boxes for block, inline, table, figure, and code.
- Knuth-Plass-style paragraph breaker for Latin text.
- Table model with header rows, row groups, column alignment, and cell boxes.
- PDF structural inspector for unit tests.

Medium-confidence pure Swift ports:

- Type 0 font dictionaries.
- ToUnicode CMap writing.
- TrueType subset bookkeeping.
- Deflate compression if Foundation or Swift-native compression is allowed.
- PDF outlines and named destinations.
- PDF/A-oriented metadata scaffolding.

OS-specific optional experiments:

- Platform text shaping and measurement.
- Platform PDF context output.
- Platform font discovery and embeddability checks where available.

These are not allowed in the shared Linux and macOS renderer.

Do not port now:

- Full Skia graphics stack.
- Full Typst compiler.
- Full FOP XSL-FO engine.
- Full PDFBox object model.
- Cairo backend code.
- OpenPDF/iText code without license review.
- MuPDF code.

## Recommended implementation sequence

1. Strengthen the current pure-Swift PDF writer with typed operators and
   resource registration.
2. Add a layout tree that is independent of the PDF writer.
3. Add table and figure layout boxes on the portable path.
4. Add font embedding as a portable PDF writer feature, with macOS and Linux
   tests split by available fonts.
5. Add ToUnicode CMap generation before claiming extraction quality.
6. Add PDF outline and named destinations.
7. Add optional OS-specific measurement or shaping only after the pure-Swift
   model works on Linux and macOS.
8. Add optional PDF/A and PDF/UA export modes after validation strategy is
   agreed.

## Linux commitment

REPO CONSTRAINT: Linux support is not optional. The shared rendering model must
not depend on CoreGraphics, CoreText, AppKit, UIKit, PDFKit, WebKit, browser
engines, or C PDF libraries.

IMPLEMENTATION RULE: If an algorithm cannot run on Linux in pure Swift, it is
OS-specific product work or research-only. It is not allowed in the core
portable renderer.

## Open questions

- Is license-reviewed translation from Apache 2.0 or BSD sources acceptable, or
  should all code remain clean-room/spec-driven?
- Should PDF/A validation use an optional external CI job, or should the repo
  only provide manual validation notes?
- Should embedded fonts be portable-first with a Swift font parser, or should
  the first milestone use only PDF base fonts plus ToUnicode improvements?
- What is the minimum PDF version for the first article-grade target?
