# MarkdownPDF

**Follow updates on [@diyamantina](https://x.com/diyamantina).**

[![Style and namespacing](https://github.com/mihaelamj/MarkdownPDF/actions/workflows/style.yml/badge.svg)](https://github.com/mihaelamj/MarkdownPDF/actions/workflows/style.yml)
[![Swift macOS](https://github.com/mihaelamj/MarkdownPDF/actions/workflows/swift-macos.yml/badge.svg)](https://github.com/mihaelamj/MarkdownPDF/actions/workflows/swift-macos.yml)
[![Swift Linux](https://github.com/mihaelamj/MarkdownPDF/actions/workflows/swift-linux.yml/badge.svg)](https://github.com/mihaelamj/MarkdownPDF/actions/workflows/swift-linux.yml)

MarkdownPDF is a Pure Swift Markdown to PDF renderer. It parses Markdown, lays
the document out, and serializes PDF bytes directly in Swift.

The core renderer is built for macOS and Linux. It does not use PDFKit,
CoreGraphics, WebKit, wkhtmltopdf, Chromium, LaTeX, browser renderers,
JavaScript, Python, shell renderers, or C Markdown/PDF libraries.

## What Works Today

MarkdownPDF is early, but it already emits inspectable PDF 1.4 files with
deterministic object order, xref offsets, trailer data, page resources, link
annotations, text, and image XObjects.

The generic renderer currently covers:

- Headings, paragraphs, block quotes, thematic breaks, and raw HTML as visible
  text.
- Emphasis, strong text, strike-through, inline code, links, and backslash
  escapes.
- Ordered lists, unordered lists, fenced code blocks, and GitHub-flavored tables.
- Local JPEG and PNG images resolved relative to the input document.
- Standard PDF base fonts by default, without embedding font files.

The compatibility target is CommonMark plus GitHub Flavored Markdown tables and
images. The generated profile is still intentionally small while the canonical
PDF structure is being moved into typed Swift components.

## Package Products

| Product | Kind | Purpose |
|---|---|---|
| `MarkdownPDF` | Library | Portable Markdown parser, layout engine, and direct PDF byte writer. |
| `MarkdownPDFLinux` | Library | Linux-facing entry point for the portable renderer. |
| `MarkdownPDFMac` | Library | macOS-only entry point. It currently delegates to the portable renderer. |
| `MarkdownPDFResume` | Library | Structured resume JSON to Markdown template. |
| `markdownpdf` | Executable | Markdown file to PDF file command. |
| `resumepdf` | Executable | Resume JSON file to PDF file command. |

`MarkdownPDFMac` is available only when the package is built on macOS. iOS
support is not claimed.

## Quick Start

Use the portable renderer directly:

```swift
import Foundation
import MarkdownPDF

let markdown = "# Hello\n\nA small PDF renderer."
let data = try MarkdownPDFRenderer().render(markdown: markdown)
try data.write(to: URL(fileURLWithPath: "hello.pdf"))
```

Use custom page settings:

```swift
import MarkdownPDF

let options = PDFOptions(
    pageSize: .letter,
    margins: PDFOptions.Margins(top: 48, right: 48, bottom: 48, left: 48),
    baseFontSize: 11,
    fontSet: .pdfBase,
    title: "Example",
)

let markdown = "# Letter Page\n\nCustom page settings."
let data = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
```

Use the Linux-facing product:

```swift
import MarkdownPDFLinux

let markdown = "# Linux\n\nPortable PDF output."
let data = try MarkdownPDFLinuxRenderer().render(markdown: markdown)
```

Use the macOS-facing product:

```swift
import MarkdownPDFMac

let markdown = "# macOS\n\nCurrently delegates to the portable renderer."
let data = try MarkdownPDFMacRenderer().render(markdown: markdown)
```

Run the Markdown CLI:

```sh
cd Packages
swift run markdownpdf input.md output.pdf
```

Run the resume template CLI:

```sh
cd Packages
swift run resumepdf input.json output.pdf
```

See [docs/RESUME_TEMPLATE.md](docs/RESUME_TEMPLATE.md) for the resume JSON
shape and journal inputs behind it.

## Canonical PDF roadmap

Epic [#27](https://github.com/mihaelamj/MarkdownPDF/issues/27) tracks the
ordered path from the current byte writer to a fully typed canonical PDF
document structure.

Portable Mermaid diagrams and generated ToC are explicit phases because they
affect pagination and must work on Linux without Node or Apple-only rendering.
The epic issue and this diagram should be updated at every child issue transition:
implementation start, PR open, merge, or scope change.

```mermaid
flowchart TD
    P0["Phase 0<br/>#28 Minimal canonical PDF<br/>Done"]
    P1["Phase 1<br/>#29 Tool validation<br/>#25 Structural validation<br/>Done"]
    P2["Phase 2<br/>#22 PDF syntax<br/>#30 Object registry, xref, trailer<br/>Done"]
    P3["Phase 3<br/>#18 Catalog, page tree, page dictionaries<br/>Done"]
    P4["Phase 4<br/>#19 Page resources Done<br/>#20 Font objects Done<br/>#23 Image XObjects Done"]
    P5["Phase 5<br/>#21 Typed content streams PR #42 visual gate hardening"]
    P6["Phase 6<br/>#26 Metadata, outlines, destinations"]
    P7["Phase 7<br/>#37 Mermaid diagrams"]
    P8["Phase 8<br/>#36 Generated ToC"]
    P9["Phase 9<br/>#24 Output profile documentation"]

    P0 --> P1 --> P2 --> P3 --> P4 --> P5 --> P6 --> P7 --> P8 --> P9

    classDef done fill:#e8f5e9,stroke:#2e7d32,color:#111;
    classDef next fill:#fff8e1,stroke:#f9a825,color:#111;
    classDef todo fill:#eef3ff,stroke:#3367d6,color:#111;
    class P0,P1,P2,P3,P4 done;
    class P5 next;
    class P6,P7,P8,P9 todo;
```

## Validation

The test suite validates generated PDFs in three ways:

- Swift structural inspection checks object references, xref offsets, stream
  lengths, page resources, annotations, fonts, images, and canonical page
  structure.
- `qpdf --check` validates syntax, xref, trailer, and stream-level structure.
- Poppler tools inspect real reader behavior through `pdfinfo`, `pdftotext`, and
  `pdftoppm`.
- MuPDF `mutool` independently extracts character quads and renders page rasters.

Layout-affecting renderer changes must keep the visual geometry tests passing.
Those tests render representative Markdown, extract Poppler word and line boxes
with `pdftotext -tsv`, extract MuPDF character quads with `mutool draw -F stext`,
and compare Poppler and MuPDF raster ink bounds. They fail on
non-positive boxes, text outside page bounds, same-line word overlap,
same-word glyph overlap, vertical line collisions, blank renders, or divergent
non-overlapping ink bounds.

See [docs/research/pdf-validation-tooling.md](docs/research/pdf-validation-tooling.md)
and [docs/research/pdf-visual-layout-validation.md](docs/research/pdf-visual-layout-validation.md)
for the validation rationale.

## Build and Test

```sh
cd Packages
swift build
swift test
```

The same package is expected to build on macOS and Linux. GitHub CI runs style,
macOS Swift, and Linux Swift checks.

Useful local checks from the repository root:

```sh
./scripts/check-style.sh
swiftformat . --config .swiftformat --lint
swiftlint --config .swiftlint.yml
```

## Documentation

- [CONTRIBUTING.md](CONTRIBUTING.md): contributor setup, conventions, branches,
  commits, and pull requests.
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md): community standards and enforcement.
- [docs/DESIGN.md](docs/DESIGN.md): implementation architecture.
- [docs/CONVENTIONS.md](docs/CONVENTIONS.md): project conventions.
- [docs/RESUME_TEMPLATE.md](docs/RESUME_TEMPLATE.md): resume JSON and template
  behavior.
- [docs/research/README.md](docs/research/README.md): research map.
- [docs/research/canonical-pdf-document-structure.md](docs/research/canonical-pdf-document-structure.md):
  canonical PDF structure notes.
- [docs/research/markdownpdf-output-profile.md](docs/research/markdownpdf-output-profile.md):
  target output profile.

## Platform Boundaries

- Portable behavior means macOS and Linux.
- `MarkdownPDFMac` is a macOS target hook, not a separate backend yet.
- iOS support is not implemented or tested.
- Apple system font names remain available through
  `PDFOptions.FontSet.appleSystem`, but the public repo does not embed font
  files.
- Research source snapshots, when present, are evidence only. They are not
  package dependencies. See
  [docs/research/source-snapshot-policy.md](docs/research/source-snapshot-policy.md).

## Design Constraints

- Pure Swift source.
- Direct PDF byte generation.
- No runtime shell-out to another renderer or validator during rendering.
- No PDFKit, CoreGraphics, WebKit, browser renderers, LaTeX, JavaScript, Python,
  shell renderers, or C Markdown/PDF libraries in implementation.
- No embedded font files in the public repo.
- Standard PDF base fonts by default, with Apple system font names available
  through `PDFOptions.FontSet.appleSystem`.
- Linux generation support through Foundation and byte-level PDF serialization.
- Small, testable public API.

## License

See [LICENSE](LICENSE).
