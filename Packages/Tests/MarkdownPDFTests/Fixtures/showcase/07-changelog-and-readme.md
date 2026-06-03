# MarkdownPDF

A pure-Swift Markdown to PDF renderer. No browser engines, no C libraries, PDF
bytes serialized by hand. Builds on macOS and Linux.

## Features

- Multilingual text with embedded fonts: café, résumé, Привет, Καλημέρα.
- Inline and display TeX math: $E = mc^2$ and $a^2 + b^2 = c^2$.
- Native vector charts and a portable Mermaid subset.
- Independent witnesses: Poppler and MuPDF.

## Quick start

```sh
swift run markdownpdf input.md output.pdf
```

```swift
let data = try MarkdownPDFRenderer().render(markdown: "# Hello")
```

## Status

| Area | State |
| :--- | :---: |
| Embedded fonts | done |
| Math subset | active |
| Charts | done |
| Tagged PDF | done |

---

## Changelog

### [Unreleased]

#### Fixed

- Scale embedded CID `/W` widths and FontDescriptor metrics to 1000-unit glyph
  space. Fonts with `unitsPerEm != 1000` (DejaVu, Liberation use 2048) no longer
  render garbled in viewers.

#### Added

- Full visual witness battery on embedded-font fixtures.
- Diverse multilingual showcase corpus.

### [0.1.0]

- Initial parser, renderer, and `markdownpdf` CLI.

## Tasks

- [x] Width scaling fix
- [x] Witness battery
- [ ] CJK-covering CI font
