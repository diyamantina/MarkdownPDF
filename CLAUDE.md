# CLAUDE.md

Guidance for coding agents working in this repository.

## Project

MarkdownPDF is a Pure Swift Markdown to PDF renderer. It owns its parser, layout,
and PDF serialization code. The engine library is `MarkdownPDF`, the CLI is
`markdownpdf`, and the repository is `MarkdownPDF`. The engine targets macOS and
Linux.

## Read First

- [AGENTS.md](AGENTS.md) - language policy, product rules, workflow, commands.
- [Packages/Sources/MarkdownPDFDocumentation/MarkdownPDFDocumentation.docc/Design.md](Packages/Sources/MarkdownPDFDocumentation/MarkdownPDFDocumentation.docc/Design.md) - architecture and constraints.
- [Packages/Sources/MarkdownPDFDocumentation/MarkdownPDFDocumentation.docc/Rules/](Packages/Sources/MarkdownPDFDocumentation/MarkdownPDFDocumentation.docc/Rules/) - coding conventions.
- [CONTRIBUTING.md](CONTRIBUTING.md) - contributor workflow.

## Non-Negotiables

- Swift only. No shell-out renderers, browser engines, PDFKit, CoreGraphics,
  WebKit, LaTeX, or C Markdown/PDF libraries.
- The core must build on macOS and Linux.
- PDF output is serialized by hand.
- Do not embed font files in the repo. Use Apple font names by default and allow
  PDF viewers to substitute where those fonts are missing.
- Dependencies go through initializers. No singletons.
- No force-unwrapping in shipping code.
- Verify before claiming done with `swift build` and `swift test`.
- No AI attribution and no em dashes in committed text.

## Commands

```sh
cd Packages
swift build
swift test
swift run markdownpdf input.md output.pdf
```
