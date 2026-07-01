# Agent Guide

Guidance for anyone writing code in MarkdownPDF.

## What MarkdownPDF Is

MarkdownPDF is a Pure Swift Markdown to PDF renderer. The library parses
Markdown into an AST, lays the document out, and serializes a PDF file by hand.
This repository is the pure engine package; the `markdownpdf` and `resumepdf`
command-line tools live in the separate
[MarkdownPDFCli](https://codeberg.org/MarkdownPdfHQ/MarkdownPDFCli) repo. The full
package must build on macOS and Linux, and the core engine must also build on
Windows and WebAssembly (WASI).

## Rule Loading

At the start of a session, read [Sources/MarkdownPDFDocumentation/MarkdownPDFDocumentation.docc/Rules/RulesOverview.md](Sources/MarkdownPDFDocumentation/MarkdownPDFDocumentation.docc/Rules/RulesOverview.md) and
the rules it marks as always relevant. Name the rule files that apply to the
task at hand.

## Language Policy

Swift only for source, tests, and tooling. Do not add JavaScript, Python, shell
renderers, browser drivers, PDFKit, CoreGraphics, WebKit, LaTeX, or C Markdown
or PDF libraries.

## Product Rules

- Generate PDF bytes directly in Swift.
- Keep the core portable: it must build on macOS, Linux, Windows, and WASI.
- Do not embed font files in the public repo.
- Use standard PDF base fonts by default. Apple system font names remain
  available through `PDFOptions.FontSet.appleSystem`.
- Treat CommonMark plus GitHub Flavored Markdown tables and images as the
  compatibility target.
- Keep public API small and testable.

## Workflow

- Verify before claiming done: run `swift build` and `swift test` from the repo
  root and cite the output.
- Commits follow Conventional Commits.
- No AI attribution and no em dashes in any committed text. Enable hooks with
  `git config core.hooksPath .githooks`.

## Commands

```sh
swift build
swift test
```
