# Contributing to MarkdownPDF

Thanks for your interest in MarkdownPDF. This guide covers how to set up, the
constraints the project follows, and how to land a change.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Language policy

MarkdownPDF is a **pure Swift** project. All renderer, parser, PDF writer, CLI,
tooling, and test code must be Swift.

Do not add JavaScript, Python, shell renderers, browser drivers, PDFKit,
CoreGraphics, WebKit, LaTeX, C Markdown libraries, C PDF libraries, or any
external renderer. Validation tools such as `qpdf` and Poppler are test
dependencies only; they are not part of rendering.

## Project status

MarkdownPDF is an early Markdown-to-PDF renderer. It already emits inspectable
PDF 1.4 files with deterministic object order, xref offsets, trailer data, page
resources, text, images, links, and a small CommonMark/GFM surface. The current
working surface, package products, validation strategy, and roadmap are listed
in [`README.md`](README.md), and the architecture is in
[`Packages/Sources/MarkdownPDFDocumentation/MarkdownPDFDocumentation.docc/Design.md`](Packages/Sources/MarkdownPDFDocumentation/MarkdownPDFDocumentation.docc/Design.md).

## Getting started

Requires a recent Swift toolchain. MarkdownPDF is a monorepo: a workspace at the
root, a single `Package.swift` under `Packages/`, and package products for the
portable renderer, platform entry points, and CLIs.

```sh
git config core.hooksPath .githooks
cd Packages
swift build
swift test
swift run markdownpdf input.md output.pdf
```

The hook command wires three checks: `commit-msg` and `pre-commit` reject
forbidden style tells in messages and staged content, and `pre-push` runs the
mechanical verification stack.

Before pushing, run the same core checks locally:

```sh
scripts/check-style.sh
scripts/check-namespacing.sh
swiftformat . --config .swiftformat --lint
swiftlint --config .swiftlint.yml --strict
( cd Packages && swift build && swift test )
```

The CI workflows run the style gate, macOS Swift gate, and Linux Swift gate.

## Constraints

MarkdownPDF follows the conventions documented in
[`Packages/Sources/MarkdownPDFDocumentation/MarkdownPDFDocumentation.docc/Conventions.md`](Packages/Sources/MarkdownPDFDocumentation/MarkdownPDFDocumentation.docc/Conventions.md). The short version:

- Pure Swift source, tests, and tooling.
- Direct PDF byte generation. Rendering does not shell out to another renderer.
- No PDFKit, CoreGraphics, WebKit, browser renderers, LaTeX, JavaScript, Python,
  shell renderers, or C Markdown/PDF libraries in implementation.
- No font files committed to this repo. Standard PDF base fonts are the default.
- The core builds on macOS and Linux.
- Dependencies are injected through initializers. Platform-specific behavior
  sits behind a protocol seam.
- Types are namespaced under `MarkdownPDF`, one non-private type per file, with
  filenames matching qualified type names.
- Tests use the Swift Testing framework and assert behavior, not implementation.

Read the surrounding files before writing new code and match what is already
there. Consistency with existing code outranks personal preference.

## Commits

Commit messages follow Conventional Commits: `<type>(<scope>): summary`,
lowercase type, imperative mood, no trailing period, first line under 72
characters. Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
`build`, `ci`, `chore`.

Do not include AI attribution and do not use em dashes in commit messages or
committed files.

## Branches

Branch from the current tip of `main`:

```sh
git fetch origin main && git checkout -b feat/<topic> origin/main
```

Naming: `fix/<issue>-<topic>`, `feat/<topic>`, `chore/<topic>`,
`docs/<topic>`, `refactor/<topic>`.

## Pull requests

- Keep one focused change per PR.
- Add tests for behavior changes and validation-sensitive PDF output changes.
- Run `swift build` and `swift test` from `Packages/` and confirm both pass.
- Add a `CHANGELOG.md` entry under `Unreleased` for any change touching shipping
  source. Docs, tests, and config changes do not need an entry.
- Do a self-review pass on your own diff and fix what a reviewer would flag.

## Issues

For bugs, file an issue first using the bug form, then branch with the issue
number in the name. The issue is the durable record of symptom, reproduction,
and acceptance criteria.

For features, an issue is recommended when the scope is non-trivial.

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
