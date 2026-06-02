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
deterministic object order, xref offsets, trailer data, page resources, metadata,
heading destinations, outlines, link annotations, text, and image XObjects.

The generic renderer currently covers:

- Headings, paragraphs, block quotes, thematic breaks, and raw HTML as visible
  text.
- Emphasis, strong text, strike-through, inline code, links, and backslash
  escapes.
- Ordered lists, unordered lists, fenced code blocks, and GitHub-flavored tables.
- Local JPEG and PNG images resolved relative to the input document.
- PDF document title metadata, heading outlines, and internal heading links.
- Opt-in generated table of contents with final page numbers and internal links.
- Standard PDF base fonts by default, without embedding font files.
- Opt-in embedded TrueType font data through `PDFOptions.EmbeddedFonts`, using
  Type 0 / CIDFontType2 fonts, ToUnicode maps, and subsetted FontFile2 streams.
- Opt-in portable syntax coloring for supported fenced code-block language
  hints, using direct DeviceRGB text operators.

The compatibility target is CommonMark plus GitHub Flavored Markdown tables and
images. The generated PDF profile is intentionally small, typed, and documented
under `docs/research/`.

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

Generate a visible table of contents:

```swift
import MarkdownPDF

let options = PDFOptions(tableOfContents: .enabled)
let markdown = "# Report\n\n## Methods\n\nBody."
let data = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
```

Enable portable syntax coloring for supported fenced code blocks:

````swift
import MarkdownPDF

let options = PDFOptions(codeSyntaxHighlighting: .enabled)
let markdown = """
```swift
let answer = "portable"
```
"""
let data = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
````

Embed caller-provided TrueType font data:

```swift
import Foundation
import MarkdownPDF

let fontData = try Data(contentsOf: URL(fileURLWithPath: "OpenFont.ttf"))
let source = PDFOptions.EmbeddedFontSource(data: fontData)
let options = PDFOptions(
    embeddedFonts: .allRoles(source),
)

let markdown = "# Embedded\n\nThe font file is embedded as a subset."
let data = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
```

Embedded fonts are opt in. The caller is responsible for the font license. The
portable renderer rejects fonts whose OS/2 embedding bits do not allow the
subset profile. macOS font discovery is not part of the shared core, and this
does not claim iOS support.

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
    P5["Phase 5<br/>#21 Typed content streams Done"]
    P6["Phase 6<br/>#26 Metadata, outlines, destinations Done"]
    P7["Phase 7<br/>#37 Mermaid diagrams Done"]
    P8["Phase 8<br/>#36 Generated ToC Done"]
    P9["Phase 9<br/>#24 Output profile documentation Done"]

    P0 --> P1 --> P2 --> P3 --> P4 --> P5 --> P6 --> P7 --> P8 --> P9

    classDef done fill:#e8f5e9,stroke:#2e7d32,color:#111;
    classDef active fill:#e3f2fd,stroke:#1565c0,color:#111;
    classDef review fill:#f3e5f5,stroke:#7b1fa2,color:#111;
    classDef next fill:#fff8e1,stroke:#f9a825,color:#111;
    classDef todo fill:#eef3ff,stroke:#3367d6,color:#111;
    class P0,P1,P2,P3,P4,P5,P6,P7,P8 done;
    class P9 done;
```

## Validation

The test suite validates generated PDFs in five layers:

- Swift structural inspection checks object references, xref offsets, stream
  lengths, page resources, annotations, fonts, images, and canonical page
  structure.
- `qpdf --check` validates syntax, xref, trailer, and stream-level structure.
- Poppler tools inspect reader behavior through `pdfinfo`, `pdftotext`,
  `pdftotext -tsv`, and `pdftoppm`.
- MuPDF `mutool` independently extracts character quads and renders page
  rasters.
- Poppler and MuPDF raster output is compared across every generated page in the
  visual stress fixture.

Layout-affecting renderer changes must keep the visual geometry tests passing.
Those tests render representative multi-page Markdown with dense prose, inline
styles, lists, tables, links, fenced code fallback, Mermaid diagrams, and page
breaks. They extract Poppler word and line boxes with `pdftotext -tsv`, extract
MuPDF character quads with `mutool draw -F stext`, and compare Poppler and MuPDF
raster ink bounds for every page. They fail on non-positive boxes, text outside
page bounds, same-line word overlap, same-word glyph overlap, vertical line
collisions, blank renders, or divergent ink bounds.

Witness differences are handled in the test layer unless the generated PDF bytes
truly need to differ by platform. Linux Poppler page-origin normalization and
macOS CI Base35 font installation are examples of witness environment fixes, not
production renderer forks.

Set `MARKDOWNPDF_ARTIFACT_DIR` while running tests to preserve witness outputs.
The visual layout tests write the representative PDF, extracted text, `pdfinfo`
output, Poppler TSV, MuPDF structured text, and Poppler/MuPDF page rasters under
that directory, with a `README.txt` manifest naming each witness. GitHub CI
uploads those files as `markdownpdf-witness-linux` and
`markdownpdf-witness-macos` artifacts for pull request review.

Embedded-font tests use generated Swift TrueType fixtures for deterministic
coverage and CI-installed open fonts for an external smoke test. Linux CI uses
DejaVu Sans, macOS CI uses Liberation Sans, and both pass the chosen font path
through `MARKDOWNPDF_OPEN_FONT_PATH`; the public repository does not commit font
binaries.

See [docs/research/pdf-validation-tooling.md](docs/research/pdf-validation-tooling.md)
and [docs/research/pdf-visual-layout-validation.md](docs/research/pdf-visual-layout-validation.md)
for the validation rationale. See
[docs/rules/pdf-witness-gate.md](docs/rules/pdf-witness-gate.md) for the policy
future PDF features must satisfy.

## Portable fidelity roadmap

Epic [#48](https://github.com/mihaelamj/MarkdownPDF/issues/48) tracks the next
portable hardening round after the canonical PDF structure epic. It focuses on
reviewable witness artifacts, realistic fixtures, text encoding boundaries,
oversized block behavior, tables, diagrams, charts, and future font planning
without adding Apple-only dependencies.

```mermaid
flowchart TD
    F0["Phase 0<br/>#49 Witness artifacts Done"]
    F1["Phase 1<br/>#50 Article fixtures Done"]
    F2["Phase 2<br/>#51 Text encoding Done"]
    F3["Phase 3<br/>#52 Oversized blocks Done"]
    F4["Phase 4<br/>#53 Tables Done"]
    F5["Phase 5<br/>#54 Diagrams and charts Done"]
    F6["Phase 6<br/>#55 Fonts and ToUnicode plan Done"]

    F0 --> F1 --> F2 --> F3 --> F4 --> F5 --> F6

    classDef done fill:#e8f5e9,stroke:#2e7d32,color:#111;
    classDef active fill:#e3f2fd,stroke:#1565c0,color:#111;
    classDef review fill:#f3e5f5,stroke:#7b1fa2,color:#111;
    classDef next fill:#fff8e1,stroke:#f9a825,color:#111;
    classDef todo fill:#eef3ff,stroke:#3367d6,color:#111;
    class F0,F1 done;
    class F2 done;
    class F3,F4,F5 done;
    class F6 done;
```

## Embedded font foundation roadmap

Epic [#63](https://github.com/mihaelamj/MarkdownPDF/issues/63) tracked the
portable embedded-font implementation after the #55 research plan and is now
complete. This round is strictly macOS and Linux portable: the core remains
Swift-only, does not use Apple-only rendering APIs, does not commit font
binaries, and does not claim iOS support.

```mermaid
flowchart TD
    E0["Phase 0<br/>#64 Type 0 object model<br/>Done"]
    E1["Phase 1<br/>#65 TrueType parser gates<br/>Done"]
    E2["Phase 2<br/>#66 Glyph mapping and widths<br/>Done"]
    E3["Phase 3<br/>#67 ToUnicode CMaps<br/>Done"]
    E4["Phase 4<br/>#68 CID text writer witnesses<br/>Done"]
    E5["Phase 5<br/>#69 TrueType subsetting<br/>Done"]
    E6["Phase 6<br/>#70 Public API and CI font policy<br/>Done"]
    E7["Phase 7<br/>#71 Complex-script follow-up epic<br/>Done"]

    E0 --> E1 --> E2 --> E3 --> E4 --> E5 --> E6 --> E7

    classDef done fill:#e8f5e9,stroke:#2e7d32,color:#111;
    classDef active fill:#e3f2fd,stroke:#1565c0,color:#111;
    classDef review fill:#f3e5f5,stroke:#7b1fa2,color:#111;
    classDef next fill:#fff8e1,stroke:#f9a825,color:#111;
    classDef todo fill:#eef3ff,stroke:#3367d6,color:#111;
    class E0,E1,E2,E3,E4,E5,E6,E7 done;
```

## Complex script shaping roadmap

Epic [#79](https://github.com/mihaelamj/MarkdownPDF/issues/79) tracks the
follow-up work for Unicode line breaking, bidirectional text, shaped glyph
clusters, and multi-scalar ToUnicode mappings. This roadmap is still portable
macOS and Linux work: the shared renderer remains Swift-only, does not depend on
Apple-only APIs or C shaping libraries, and does not claim iOS support.

```mermaid
flowchart TD
    S0["Phase 0<br/>#80 Standards and boundary<br/>Done"]
    S1["Phase 1<br/>#81 Fixtures and witnesses<br/>Done"]
    S2["Phase 2<br/>#82 Shaped cluster model<br/>Done"]
    S3["Phase 3<br/>#83 Line-break opportunities<br/>Done"]
    S4["Phase 4<br/>#84 Bidi ordering<br/>Done"]
    S5["Phase 5<br/>#85 Pure Swift shaping increments<br/>Done"]
    S6["Phase 6<br/>#86 PDF emission and ToUnicode clusters<br/>Done"]

    S0 --> S1 --> S2 --> S3 --> S4 --> S5 --> S6

    classDef done fill:#e8f5e9,stroke:#2e7d32,color:#111;
    classDef active fill:#e3f2fd,stroke:#1565c0,color:#111;
    classDef review fill:#f3e5f5,stroke:#7b1fa2,color:#111;
    classDef next fill:#fff8e1,stroke:#f9a825,color:#111;
    classDef todo fill:#eef3ff,stroke:#3367d6,color:#111;
    class S0,S1,S2,S3,S4,S5,S6 done;
```

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
- [docs/research/portable-embedded-fonts-tounicode-plan.md](docs/research/portable-embedded-fonts-tounicode-plan.md):
  portable embedded-font and ToUnicode implementation plan.
- [docs/research/complex-script-shaping-bidi-roadmap.md](docs/research/complex-script-shaping-bidi-roadmap.md):
  follow-up roadmap for Unicode line breaking, bidi ordering, shaping, and
  ToUnicode cluster witnesses.
- [docs/research/source-code-typesetting-literature.md](docs/research/source-code-typesetting-literature.md):
  source-code formatting literature and witness notes.
- [docs/research/source-code-renderer-analysis.md](docs/research/source-code-renderer-analysis.md):
  source-code formatting comparison against current renderer and witness paths.
- [docs/research/source-code-formatting-model.md](docs/research/source-code-formatting-model.md):
  portable source-code formatting model for renderer implementation.
- [docs/research/portable-syntax-coloring.md](docs/research/portable-syntax-coloring.md):
  portable syntax-coloring recommendation, implementation policy, and witness
  requirements.
- [docs/research/apple-and-custom-fonts.md](docs/research/apple-and-custom-fonts.md):
  Apple system font naming limits and custom-font format policy.

## Platform Boundaries

- Portable behavior means macOS and Linux.
- `MarkdownPDFMac` is a macOS target hook, not a separate backend yet.
- iOS support is not implemented or tested.
- The default portable text profile emits printable ASCII. Unsupported Unicode
  scalars, including Latin-1 letters, Windows-1252 punctuation, emoji, complex
  scripts, combining marks, and bidirectional text, render as `?` unless the
  caller enables an embedded TrueType font profile that covers those scalars.
- Issue [#95](https://github.com/mihaelamj/MarkdownPDF/issues/95) completed the
  hard fixture corpus pass with duplicate headings, generated ToC pressure,
  internal and external links, nested quotes, lists, wide tables, reused local
  images, remote image fallback, raw HTML fallback, code blocks, Mermaid drawing,
  and unsupported Mermaid fallback.
- Issue [#97](https://github.com/mihaelamj/MarkdownPDF/issues/97), landed by
  PR [#98](https://github.com/mihaelamj/MarkdownPDF/pull/98), completed the A4
  and external manuscript witness pass. It adds sustained manuscript prose, A4
  page-size assertions, tables, local and remote figures, supported Mermaid
  drawing, unsupported Mermaid fallback, a complete patent fixture, Formidabble
  source-style manuscript coverage, an App Intents framework manuscript, an
  optimized WWDC transcript witness path, a full WWDC source bundle for explicit
  large-fixture stress runs, and all-page Poppler/MuPDF raster comparison for
  the A4 manuscript.
- The full WWDC fixture is committed for special stress coverage. Run it with
  `MARKDOWNPDF_LARGE_FIXTURE_TESTS=1 swift test --filter FixtureTests/wwdcLargeFixtureRendersSelectedOversizedAssetsWhenEnabled`
  from `Packages/`.
- Issue [#99](https://github.com/mihaelamj/MarkdownPDF/issues/99) completed
  source-code formatting research and implementation, including the reported
  quote-stroke, crammed-layout, glyph-overlap, and image-presence regressions.
  Issue [#120](https://github.com/mihaelamj/MarkdownPDF/issues/120) landed the
  portable syntax-coloring implementation. Issue
  [#122](https://github.com/mihaelamj/MarkdownPDF/issues/122) landed Unicode
  combining diacritics and CJK / kanji coverage. Issue
  [#135](https://github.com/mihaelamj/MarkdownPDF/issues/135) landed
  screenshot-reported source-code layout regression coverage across code,
  quotes, headings, images, and fallback text. Issue
  [#123](https://github.com/mihaelamj/MarkdownPDF/issues/123) landed RTL
  manuscript hardening. Issue
  [#141](https://github.com/mihaelamj/MarkdownPDF/issues/141) landed the #135
  negative-control proof. Issue
  [#146](https://github.com/mihaelamj/MarkdownPDF/issues/146) preserved staged
  research for the next implementation shortlist. Issue
  [#142](https://github.com/mihaelamj/MarkdownPDF/issues/142) landed the
  line-break correctness follow-up for Thai, Khmer, Japanese non-starters, and
  Hangul. Issue
  [#143](https://github.com/mihaelamj/MarkdownPDF/issues/143) expanded
  syntax-coloring coverage with data-driven comment delimiters for shell,
  YAML, XML/HTML, Pascal, Lisp-family, SQL, Lua, Haskell, Ada, Erlang, LaTeX,
  and Visual Basic hints.
- Issue [#100](https://github.com/mihaelamj/MarkdownPDF/issues/100) tracks
  named PDF page sizes, including A1, A3, A4, and A5.
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

## Current Hardening

```mermaid
flowchart TD
    H0["#95<br/>Hard Markdown fixture corpus<br/>Done"]
    H1["#97/#98<br/>A4 and external fixtures<br/>Done"]
    H2["#99<br/>Source-code formatting epic<br/>Done"]
    H2A["#101<br/>Literature research<br/>Done"]
    H2B["#102<br/>Compare with renderer<br/>Done"]
    H2C["#103<br/>Portable code model<br/>Done"]
    H2D["#112<br/>Remove quote strokes<br/>Done"]
    H2E["#104<br/>Formatting baseline<br/>Done"]
    H2F["#105<br/>Visual witnesses<br/>Done"]
    H2G["#113<br/>Image inclusion audit<br/>Done"]
    H2H["#106<br/>Syntax coloring study<br/>Done"]
    H2I["#118<br/>Roadmap colors<br/>Done"]
    H2J["#119<br/>Crazy markdown fixtures<br/>Done"]
    H2K["#120<br/>Portable syntax coloring<br/>Done"]
    H2L["#122<br/>CJK + diacritics<br/>Done"]
    H2M["#135<br/>Screenshot layout regressions<br/>Done"]
    H2N["#123<br/>RTL manuscript<br/>Done"]
    H2O["#141<br/>Prove #135 witness<br/>Done"]
    H2R["#146<br/>Preserve staged research<br/>Done"]
    H2P["#142<br/>Line-break correctness<br/>Done"]
    H2Q["#143<br/>More syntax languages<br/>Done"]
    H3["#100<br/>Named page sizes<br/>Todo"]

    H0 --> H1
    H1 --> H2
    H2 --> H2A --> H2B --> H2C --> H2D --> H2E --> H2F --> H2G --> H2H --> H2I --> H2J --> H2K --> H2L --> H2M --> H2N --> H2O --> H2R --> H2P --> H2Q
    H1 --> H3

    classDef done fill:#e8f5e9,stroke:#2e7d32,color:#111;
    classDef active fill:#e3f2fd,stroke:#1565c0,color:#111;
    classDef review fill:#f3e5f5,stroke:#7b1fa2,color:#111;
    classDef next fill:#fff8e1,stroke:#f9a825,color:#111;
    classDef todo fill:#eef3ff,stroke:#3367d6,color:#111;
    class H0,H1,H2 done;
    class H2A,H2B,H2C,H2D,H2E,H2F,H2G,H2H,H2I,H2J,H2K,H2L,H2M,H2N,H2O done;
    class H2P,H2R done;
    class H2Q done;
    class H3 todo;
```

## License

See [LICENSE](LICENSE).
