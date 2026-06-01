# Changelog

All notable changes to MarkdownPDF are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial Pure Swift Markdown parser, PDF renderer, and `markdownpdf` CLI.
- Direct PDF serialization with Apple font names and no embedded fonts.
- Parser and renderer tests for tables, images, inline styles, and PDF structure.
- `MarkdownPDFLinux` and `MarkdownPDFMac` renderer entry products.

### Changed

- Model PDF object registration, xref tables, trailers, and file envelopes as
  typed Swift structures.
- Model the PDF catalog, flat page tree, and page dictionaries as typed Swift
  structures.
