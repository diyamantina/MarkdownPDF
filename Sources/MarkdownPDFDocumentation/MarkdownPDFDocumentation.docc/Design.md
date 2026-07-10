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

## Compatibility Target

The target is CommonMark plus GFM tables and images. The
current implementation covers the syntax listed in the README and should grow
through parser fixtures and renderer tests.
