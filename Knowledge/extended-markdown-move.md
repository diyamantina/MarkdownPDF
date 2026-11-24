# The Markdown reader moved to ExtendedMarkdown: what was checked, and what was found

## What moved, and what could not

DOCUMENTED (`Sources/MarkdownPDF/MarkdownCoreAliases.swift`, the package ExtendedMarkdown): the parser, its options, the block and inline trees, the document, the math span and the HTML comment stripper (7 files, 1,643 lines, Foundation only) moved to the package ExtendedMarkdown as `ExtendedMarkdown.Core.<Name>`. MarkdownPDF keeps five public type aliases for the published names.

MEASURED (the first build of the new package failed to compile): one file of the plan did not move. `MarkdownDocumentMath.swift` asks whether a formula needs symbols outside WinAnsi, with `PDFTextEncoding`, a type of this package: it is a question for the renderer (does the page need the bundled symbol font), not for the reader. It stays here, as extensions of the aliased types, using public members only.

MEASURED (the build failed a second time): the renderer draws the text of its tile panels with the inline parser, which was internal; `ExtendedMarkdown.Core.InlineParser` became the one newly public member of the new package (an initializer, `options` and `parse`).

## The oracle: 210 PDFs, written before and after

MEASURED (Claw, 2026-11-24): the corpus of 210 PDFs (`corpus-method.md`), written at MarkdownPDF 0.18.6 before the move and recorded by name and sha256, was written again after the move: equal in all 210 files, by `diff -r` and by the list of hashes, twice (the package as a local path while the host had no commit of it, then from the repository address with ExtendedMarkdown at revision 167ba2c, the manifest exactly as committed).

MEASURED (test identifiers listed with `swift test list` before and after): 1076 before, 1030 after; the 49 removed identifiers are exactly the three moved suites (21, 7 and 21 tests) and the 3 added are `CoreAliasTests` (2) and `LinkTrailingQuoteRenderTests` (1). No test was lost; the three suites run in the new package with 3 new tests of the option defaults.

MEASURED (faults planted in the moved code): a soft break read as a line break changed 120 of 210 files; the nesting limit read as 31, 25 of 210; an alias removed, a compile error; the default of an option changed, 0 of 210: the corpus does not see a default that MarkdownPDF always overrides, and the new package pins its defaults with a test.

## A later commit of the other package changes what is built here

DOCUMENTED (`Package.swift`; `Package.resolved` is not tracked in this repository): the dependency on ExtendedMarkdown is by branch `main`, like the one on MathTypeset. A later commit of ExtendedMarkdown changes what MarkdownPDF builds, so every push to ExtendedMarkdown before the dependencies are by tag must be followed by the corpus once more, with the package's own option tests: the pair is the gate. The result above holds for revision 167ba2c only.
