# PDF Witness Gate

How MarkdownPDF proves generated PDFs are usable, not only syntactically valid.

This rule applies whenever a change touches PDF bytes, layout, pagination,
fonts, images, tables, diagrams, generated ToC, content streams, PDF validation
helpers, or CI tool setup.

## Core rule

A PDF change is not done until witnesses inspect generated PDFs. Compilation and
string inspection are not enough.

Every witness is code in this package. No outside program is run by a test, a
script, a hook or a workflow to produce, read, measure, render or convert a PDF
or an image.

Required witness layers:

1. Byte inspection in the test target for object graph invariants, xref
   offsets, stream lengths, resources, annotations, fonts, images, and page
   dictionaries.
2. `PDFDocumentReader.structureIssues(in:)` for syntax, xref, trailer, stream
   and page tree failures. Any issue is a failure for this writer.
3. `PDFDocumentReader` for what a reader gets back: page count and sizes,
   version, title and author, outline, links, fonts, and the text of each page.
4. The word boxes of `PDFDocumentReader.Page.words` for layout.
5. For a conformance profile, the facts the profile requires of the file.

The visual witnesses must fail on a word without a size, text outside page
bounds, same-line word overlap, and words of different lines that collide.

The reader and the writer have one author, so the reader is held to files typed
out by hand in the tests, each with a known content or one deliberate fault. A
new reader capability needs such a file before a test may lean on it.

What no code in the package can check yet is not verified, and is said to be so.
A test for such a property is kept, disabled with
`.disabled("not verified: ..., see Docs/NOT-VERIFIED.md")`, made to fail if it is
enabled, and listed in `Docs/NOT-VERIFIED.md` with the capability that would
restore it. Today that is anything that needs pixels (the package has no
rasterizer) and full PDF/A and PDF/UA conformance runs. A test is never deleted
silently, and never left to pass without checking anything.

## Fixture standard

Layout-affecting changes must use realistic fixtures. A one-page smoke PDF is
not enough for typography, pagination, or rich blocks.

Representative fixtures should include:

- Multiple pages.
- Dense prose.
- Inline styles and inline code.
- Lists.
- Tables.
- Links.
- Fenced code blocks, including long lines.
- Mermaid diagrams or other rich blocks when the feature is in scope.
- Page breaks that occur after mixed content.

If a stronger fixture exposes a production renderer bug, fix production Swift.
Do not weaken the fixture to make the test pass.

## Witness bugs versus renderer bugs

Separate PDF output defects from defects of the reader that inspects them.

- If the reader and the byte inspection agree the PDF bytes are wrong, fix the
  renderer.
- If the reader is wrong about bytes that are right, fix the reader, and first
  add the hand-written file that shows it wrong.
- Add production `#if os(...)` rendering branches only as a last resort, and
  only when the required PDF bytes truly need to differ by platform.

Known witness behavior:

- The reader reads what this engine writes and refuses the rest with
  `PDFDocumentReader.ReadError.unsupported`. It is not a general PDF reader, and
  a file it accepts is not thereby shown to be valid for every viewer.
- The reader reports text outside the page. A word box that leaves the page is a
  renderer defect, not something to filter out.

## CI contract

CI installs no PDF or image program. The macOS job installs `swiftformat` and
`swiftlint`, and an open font for the external font smoke test, whose path is
passed through `MARKDOWNPDF_OPEN_FONT_PATH`. The Linux job needs a Swift
toolchain and a DejaVu font. `swift build` and `swift test` are the gate.

## Future feature contract

Every future PDF feature issue must state its witness plan before implementation
is called done. This includes ToC, tables, charts, graphs, images, font
embedding, richer Mermaid support, and output profile changes.

Manual inspection artifacts are useful for review, but they are secondary. The
normal completion gate is automated witness evidence on macOS and Linux.

## Platform boundaries

Portable means macOS and Linux. macOS-only behavior must be named as macOS-only.
iOS support is not implied by a macOS result and must not be claimed unless it is
implemented and tested separately.
