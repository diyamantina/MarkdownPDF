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
CommonMark plus GitHub Flavored Markdown tables and images.

## Goals

- Build and test on macOS and Linux.
- Keep source Pure Swift.
- Render PDFs without PDFKit, CoreGraphics, WebKit, browser automation, LaTeX,
  or C libraries.
- Use standard PDF base fonts by default without embedding font files.
- Support Markdown block and inline syntax, including tables and images.

## Non-Goals

- No font redistribution.
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

The repo does not embed or redistribute font files. Standard PDF base fonts are
portable across PDF viewers, which keeps the early renderer predictable while
supporting proportional text layout.

The default portable text profile is printable ASCII. Unsupported Unicode
scalars are replaced with `?` before text is measured and serialized, so rendered
text, extracted text, and geometry witnesses observe the same replacement glyphs.
Complex scripts, bidirectional text, shaping, Type0 fonts, and `/ToUnicode` maps
belong to a later embedded-font profile.

Apple system font names remain available through
`PDFOptions.FontSet.appleSystem`:

- `SFProText-Regular`
- `SFProText-Bold`
- `SFProText-RegularItalic`
- `SFMono-Regular`

`PDFOptions.FontSet.pdfBaseMonospaced` switches all text roles to Courier when
strict monospaced output is preferred.

## Compatibility Target

The target is CommonMark plus GitHub Flavored Markdown tables and images. The
current implementation covers the syntax listed in the README and should grow
through parser fixtures and renderer tests.
