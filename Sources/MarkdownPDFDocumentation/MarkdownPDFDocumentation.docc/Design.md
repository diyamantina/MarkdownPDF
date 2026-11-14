# Design: MarkdownPDF

| Field | Value |
|---|---|
| Status | draft |
| Created | 2026-05-31 |
| Last revised | 2026-05-31 |

## Summary

MarkdownPDF converts Markdown to PDF with no external renderer. The core path is
Markdown text, Swift parser, Swift layout, Swift PDF serialization, PDF bytes.
The first implementation is intentionally small, but the compatibility target is
CommonMark plus GFM tables and images.

## Goals

- Build and test on macOS and Linux.
- Keep source Pure Swift.
- Render PDFs without PDFKit, CoreGraphics, WebKit, browser automation, LaTeX,
  or C libraries.
- Keep WinAnsi-only documents on standard PDF base fonts without embedding a
  font program.
- Support Markdown block and inline syntax, including tables and images.

## Non-Goals

- No font redistribution beyond the licensed DejaVu faces bundled by the
  package.
- No browser-quality CSS layout.
- No runtime shell-out to another conversion tool.

## Architecture

```
Markdown source
  -> MarkdownParser
  -> MarkdownDocument
  -> MarkdownPDFRenderer layout
  -> PDFDocumentWriter
  -> Data
```

## Package Products

`MarkdownPDF` remains the core portable library and current public API.
`MarkdownPDFLinux` is a Linux-compatible product entry point that delegates to
the portable renderer. `MarkdownPDFMac` is built only on macOS and gives the
package a separate platform-specific surface for future macOS renderer work.
The macOS product currently delegates to the portable renderer.

## Components

`MarkdownParser` builds the AST from Markdown source. It owns block parsing and
uses `InlineParser` for inline spans.

`MarkdownPDFRenderer` turns the AST into positioned drawing operations. It
handles pagination, wrapping, list markers, table grid drawing, image placement,
and text styling.

`PDFDocumentWriter` serializes a compact PDF file. It writes the catalog, pages,
resource dictionaries, content streams, cross-reference table, text resources,
and image XObjects directly.

`PDFImage` reads local JPEG and PNG files. JPEG data is embedded through
`DCTDecode`. Supported PNG files are embedded through their existing compressed
IDAT bytes with PDF PNG predictor parameters.

## Font Policy

The default font set references standard PDF base names:

- `Helvetica`
- `Helvetica-Bold`
- `Helvetica-Oblique`
- `Courier`

WinAnsi-only documents use standard PDF base fonts. They remain compact and
portable across PDF viewers without an embedded font program. If parsed content
contains any scalar outside WinAnsi and the caller did not select custom fonts,
the renderer binds the bundled DejaVu Sans regular, bold, and oblique faces plus
DejaVu Sans Mono for the whole document. This document-level switch keeps font
measurement, wrapping, drawing, and extraction on one coherent path. Only glyphs
the document uses are included in each emitted subset.

Callers can force the same four roles with `PDFOptions(embeddedFonts: .dejaVu)`.
If package resources are unavailable, `.dejaVu` degrades to `.disabled` and the
base-font path remains usable. Fonts supplied through `PDFOptions.EmbeddedFonts`
continue to override automatic selection.

Apple system font names remain available through
`PDFOptions.FontSet.appleSystem`:

- `SFProText-Regular`
- `SFProText-Bold`
- `SFProText-RegularItalic`
- `SFMono-Regular`

`PDFOptions.FontSet.pdfBaseMonospaced` switches all text roles to Courier when
strict monospaced output is preferred.

## Line Spacing

A theme sets a line height for each element role through
`PDFOptions/ElementStyle/lineHeightMultiplier`, a multiple of the element's own font
size. The default theme uses `1.24` for body text.

`PDFOptions/lineHeightScale` is a single multiplier applied on top of every one of
those values, so the whole document loosens or tightens together without editing the
theme. The renderer resolves it where an element's style is looked up, so paragraphs,
lists, headings, block quotes, table cells, code blocks, footnotes, and display math
all follow it. The effective line height of an element is
`fontSize * lineHeightMultiplier * lineHeightScale`.

- **Default.** `1`, which keeps the theme's own spacing. Output with the default is
  byte for byte the same as before the option existed.
- **Range.** The renderer clamps the value to `0.5 ... 3` and uses the default for a
  value that is not finite, the same containment as `PDFOptions/imageMaxHeightFraction`.
- **Scope.** Font sizes, paragraph spacing, margins, and the generated table of contents
  and index layout do not change. Only the distance between the baselines of
  consecutive lines inside an element does.

## Reading A Document Back

`PDFDocumentReader` is the engine's own witness for what it wrote. It parses the file
from its cross-reference table, walks the page tree, and interprets each content stream
far enough to say what text is shown where: the font and size in force, the text
position, strings decoded as WinAnsi for a base font or through the `/ToUnicode` map of
an embedded font, and `/ActualText` standing in for the glyphs of its span. A run's
width comes from the widths the font declares, or from the engine's standard tables for
a base font, which is what the layout measured with. The Info strings and the outline
titles are decoded as text strings, UTF-16BE after a byte order mark.

The reader covers what this engine writes and no more. A feature outside that set is
reported as unsupported instead of being read approximately, so a check built on the
reader cannot pass on a misread file. The tests check it first against a file written
by hand, then use it to read rendered documents back.

## Line Breaking

Text is broken into words at spaces, and between CJK characters, and a line takes words
until the next one does not fit the measure. The space that ends a word belongs to that
word for drawing, but it takes no room at the end of a line: a word moves down only when
its ink does not fit, and its trailing space may hang past the measure, where nothing is
drawn. Spaces alone never start a line. A line that is centered or right aligned, in a
table cell or a diagram label, is placed by its ink width for the same reason.

## Keeping Blocks Together

`PDFOptions/keepTogether` is answered by the layout itself. To learn whether a list item
or a section fits, the layout runs the same drawing code on a copy of its own state,
with pages of its own, and looks at whether the copy broke a page. There is no second
implementation of block heights to drift from the first. A unit that does not fit where
it stands and does fit on an empty page starts the next page; one that fits nowhere is
drawn in place and breaks as before. Units inside a unit being measured are not measured
again, so the cost grows with the nesting depth, not exponentially with it. A unit that
directly follows a heading is never moved alone: the heading is placed first, together
with the first item or the section under it.

A larger value suits a document that is read closely or marked up, such as a contract.
The witness is geometric: the baseline distance between consecutive lines of a
paragraph, list item, block quote, code block, and wrapped table cell is measured from
the generated content stream and must scale by exactly the factor.

## Compatibility Target

The target is CommonMark plus GFM tables and images. The
current implementation covers the syntax listed in the README and should grow
through parser fixtures and renderer tests.
