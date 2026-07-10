# CLAUDE.md

Guidance for coding agents working in this repository.

## Project

MarkdownPDF is a Pure Swift Markdown to PDF renderer. It owns its parser, layout,
and PDF serialization code. This repository is the pure engine package
(`MarkdownPDF`); the `markdownpdf` and `resumepdf` command-line tools live in the
separate [MarkdownPDFCli](https://codeberg.org/MarkdownPdfHQ/MarkdownPDFCli) repo, which
consumes this package. The full package targets macOS and Linux; the core engine
also builds on Windows and WebAssembly (WASI).

## Read First

- [AGENTS.md](AGENTS.md) - language policy, product rules, workflow, commands.
- [Sources/MarkdownPDFDocumentation/MarkdownPDFDocumentation.docc/Design.md](Sources/MarkdownPDFDocumentation/MarkdownPDFDocumentation.docc/Design.md) - architecture and constraints.
- [Sources/MarkdownPDFDocumentation/MarkdownPDFDocumentation.docc/Rules/](Sources/MarkdownPDFDocumentation/MarkdownPDFDocumentation.docc/Rules/) - coding conventions.
- [CONTRIBUTING.md](CONTRIBUTING.md) - contributor workflow.

## Non-Negotiables

- Swift only. No shell-out renderers, browser engines, PDFKit, CoreGraphics,
  WebKit, LaTeX, or C Markdown/PDF libraries.
- The full package must build on macOS and Linux. The core engine target
  (`MarkdownPDF`) must also build on Windows and WebAssembly (WASI).
- PDF output is serialized by hand.
- Bundle only the approved DejaVu faces and their exact upstream license. Keep
  WinAnsi-only documents on PDF base fonts, and select the bundled faces when
  parsed content needs glyphs outside WinAnsi.
- Dependencies go through initializers. No singletons.
- No force-unwrapping in shipping code.
- Verify before claiming done with `swift build` and `swift test`.
- No AI attribution and no em dashes in committed text.

## Commands

```sh
swift build
swift test
```
