# PDF Witness Gate

How MarkdownPDF proves generated PDFs are usable, not only syntactically valid.

This rule applies whenever a change touches PDF bytes, layout, pagination,
fonts, images, tables, diagrams, generated ToC, content streams, PDF validation
helpers, or CI tool setup.

## Core rule

A PDF change is not done until independent witnesses inspect generated PDFs.
Compilation and string inspection are not enough.

Required witness layers:

1. Swift structural checks for object graph invariants, xref offsets, stream
   lengths, resources, annotations, fonts, images, and page dictionaries.
2. `qpdf --check` for syntax, xref, trailer, and stream-level failures. qpdf
   warnings are failures for this writer.
3. Poppler reader checks through `pdfinfo`, `pdftotext`, and `pdftotext -tsv`.
4. MuPDF structured text extraction through `mutool draw -F stext`.
5. All-page raster comparison between Poppler `pdftoppm` and MuPDF
   `mutool draw`.

The visual witnesses must fail on non-positive boxes, text outside page bounds,
same-line word overlap, same-word glyph overlap, line collisions, blank renders,
or divergent ink bounds.

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

Separate PDF output defects from tool interpretation defects.

- If independent tools agree the PDF bytes are wrong, fix the renderer.
- If one tool reports platform-specific coordinates or font behavior while the
  PDF structure and other witnesses agree, normalize that behavior in the test
  witness layer.
- Add production `#if os(...)` rendering branches only as a last resort, and
  only when the required PDF bytes truly need to differ by platform.

Known witness behavior:

- Linux Poppler can report non-zero `pdftotext -tsv` page row origins on later
  generated pages even when the PDF MediaBox starts at `0 0`.
- Homebrew Poppler on macOS needs URW Base35 fonts installed before raster
  checks can reliably paint PDF base-font text.

## CI contract

Linux CI must install:

- `qpdf`
- `poppler-utils`
- `mupdf-tools`

macOS CI must install:

- `qpdf`
- `poppler`
- `mupdf`
- `font-urw-base35`

The macOS job should refresh fontconfig after installing `font-urw-base35` so
Poppler raster checks can discover the Base35 fonts.

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
