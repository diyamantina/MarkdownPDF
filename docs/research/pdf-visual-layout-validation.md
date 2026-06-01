# PDF Visual Layout Validation Research

Date: 2026-06-01

This note covers portable, open-source ways to test whether generated PDFs are
visually readable: no obvious text overlap, no broken spacing, and no renderer
regressions. The current product boundary still applies: MarkdownPDF source and
tests stay Swift, and generated PDF bytes stay direct Swift output. External
tools are acceptable as validation tools in CI, not as PDF generators.

## Problem

Structural validation is necessary but not enough. `qpdf --check`, `pdfinfo`,
and our Swift `PDFInspector` can prove that the file is syntactically valid and
that the document tree is sane. They do not prove that glyphs are readable or
that text spacing is visually correct.

The visual failure modes to catch are:

- Words or columns overlap on the same line.
- Letter spacing is too tight or negative within a word.
- Lines collide vertically.
- A renderer change causes visible output drift.
- A PDF opens, but Poppler/Ghostscript/MuPDF interpret its font metrics
  differently than our expectations.

## Findings

### Poppler: best first CI check

Poppler is already in the test stack through `qpdf`, `pdfinfo`, `pdftotext`,
and `pdftoppm`. The Debian `pdftotext` man page documents:

- `-bbox`: XHTML bounding boxes for each word.
- `-bbox-layout`: bounding boxes for blocks, lines, and words.
- `-tsv`: TSV bounding boxes for blocks, lines, and words.

Source: <https://manpages.debian.org/trixie/poppler-utils/pdftotext.1.en.html>

`pdftotext -tsv` is the most convenient machine input for Swift tests. It emits
rows with `level`, `page_num`, `block_num`, `line_num`, `word_num`, `left`,
`top`, `width`, `height`, and `text`.

Useful checks:

- Parse word rows (`level == 5`).
- Group by page, block, and line.
- Sort by `left`.
- Fail if any adjacent words on the same line overlap beyond a small epsilon.
- Fail if a word has non-positive width or height.
- Fail if line boxes on the same page overlap vertically within the same block.
- Assert that expected long fixtures produce many words and multiple lines, so
  the check is not accidentally empty.

Limitations:

- Word boxes do not directly detect overlap between letters inside one word.
- Text extraction can fail when fonts or encodings are mangled. That is still
  useful because it is a product failure for selectable text, but it is not a
  pure visual proof.
- Poppler's line grouping is an interpretation. We should tune thresholds and
  use it as a smoke/regression gate, not as a full typography oracle.

### Poppler rasterization: useful for smoke and artifacts

The Debian `pdftoppm` man page documents rendering PDF pages to image files and
supports PNG output plus DPI control. It defaults to 150 DPI.

Source: <https://manpages.debian.org/trixie/poppler-utils/pdftoppm.1.en.html>

Useful checks:

- Render the first page of each representative fixture to PNG.
- Verify non-zero PNG dimensions, which we already do.
- Optionally keep failed-render PNGs as CI artifacts.

Limitations:

- A non-empty PNG does not prove the text is readable.
- Pixel comparison needs baselines and can be noisy across Poppler/font
  versions unless the same CI image is used.

### MuPDF: best per-character geometry check

MuPDF has two relevant paths:

- `mutool draw` can render documents and extract structured text as XML or JSON.
- `mutool run` can execute JavaScript against MuPDF's API.

Sources:

- <https://mupdf.readthedocs.io/en/1.23.0/mutool-draw.html>
- <https://mupdf.readthedocs.io/en/latest/mutool-run.html>

The JavaScript `StructuredText` API can walk analyzed page text. The walker
calls `onChar(c, origin, font, size, quad, color)` for every character in a
line. It also exposes line and block callbacks with bounding boxes.

Sources:

- <https://mupdf.readthedocs.io/en/1.26.2/reference/javascript/types/StructuredText.html>
- <https://mupdf.readthedocs.io/en/1.26.8/reference/javascript/types/StructuredTextWalker.html>

Useful checks:

- For each horizontal line, collect character quads.
- Sort by origin or quad x coordinate.
- Fail if adjacent non-space character quads overlap too much.
- Fail if a character quad has non-positive area.
- Fail if line boxes collide vertically.

Limitations:

- `mutool` is not installed in this repo's current macOS environment.
- Adding MuPDF to GitHub Actions is possible on Linux, but it is another
  dependency to install and maintain on macOS and Linux CI.
- This is stronger than Poppler for letter overlap, but should be a second
  stage after Poppler TSV checks.

### Ghostscript: independent raster renderer

Ghostscript documents PNG devices including `png16m` and `pnggray`, DPI control,
and text/graphics antialiasing options. It is widely used for rasterizing PDF
and PostScript.

Source: <https://ghostscript.readthedocs.io/en/latest/Devices.html>

Useful checks:

- Render PDFs through Ghostscript as a second engine:
  `gs -dSAFER -dBATCH -dNOPAUSE -sDEVICE=png16m -r144 -o page-%03d.png input.pdf`
- Compare whether Ghostscript can render the same pages Poppler can.
- Use it to generate CI artifacts for visual inspection.

Limitations:

- Raster success is not an overlap detector.
- Pixel baselines can be sensitive to renderer and antialiasing differences.
- Ghostscript is best as a second-renderer smoke test, not the first geometry
  validator.

### ImageMagick compare and diff-pdf: visual regression tools

ImageMagick `compare` reports mathematical and visual image differences and has
documented exit behavior: `0` for similar images, `2` for errors, and a
non-zero difference result when images differ.

Source: <https://imagemagick.org/compare/>

`diff-pdf` visually compares two PDFs and exits `0` when there are no
differences and `1` when they differ. It can also emit a PDF showing highlighted
differences.

Source: <https://github.com/vslavik/diff-pdf>

Useful checks:

- Use only for stable golden visual fixtures.
- Store generated diff images or diff PDFs as CI artifacts when a regression
  fails.

Limitations:

- Requires committed baselines or generated reference PDFs.
- Can produce churn when renderer versions change.
- `diff-pdf` is not currently installed locally.

### qpdf remains structural, not visual

`qpdf --check` documents that exit status `0` indicates syntactic correctness,
but a file with no reported errors may still have stream content or specification
conformance issues.

Source: <https://qpdf.readthedocs.io/en/stable/cli.html#cmdoption-check>

This confirms why `qpdf` is necessary but insufficient for the visual problem.

## Recommended order

1. Add a Swift test helper around `pdftotext -tsv`.
2. Add a normal `swift test` case for representative generated PDFs:
   - body text with proportional base font,
   - monospaced text,
   - bold and italic spans,
   - table layout,
   - narrow page wrapping,
   - multi-page fixture.
3. Fail on invalid word boxes, same-line word overlap, and suspicious line-box
   collisions.
4. Keep the existing `pdftoppm` PNG smoke test, but preserve failed PNGs as
   artifacts in CI later.
5. Open a follow-up issue for MuPDF per-character quad validation. That is the
   stronger answer for letter-level overlap, but it is a new dependency.
6. Consider golden-image regression only after layout stabilizes. Start with
   one fixture and explicit tool versions to avoid noisy PRs.

## Local tool availability checked

On the current macOS machine:

- `pdftotext`: available at `/opt/homebrew/bin/pdftotext`.
- `pdftoppm`: available at `/opt/homebrew/bin/pdftoppm`.
- `qpdf`: available at `/opt/homebrew/bin/qpdf`.
- `gs`: available at `/opt/homebrew/bin/gs`.
- `magick`: available at `/opt/homebrew/bin/magick`.
- `mutool`: available at `/opt/homebrew/bin/mutool`.
- `diff-pdf`: not installed.

The first implementation used Poppler TSV geometry. The current canonical gate
also uses MuPDF because it is an independent renderer and extractor that can
inspect per-character quads.

## Canonical testing status

The first Poppler TSV geometry check lives in
`PDFVisualLayoutValidationTests.generatedPDFsDoNotHaveOverlappingPopplerWordBoxes`.
It is a fast Swift test that runs `pdftotext -tsv`, parses word and line boxes,
and fails on invalid boxes, same-line word overlap, words outside page bounds,
or line-box collisions.

MuPDF character-quad validation lives in
`PDFVisualLayoutValidationTests.generatedPDFsDoNotHaveOverlappingMuPDFCharacterQuads`.
It runs `mutool draw -F stext`, parses character quads, and fails on
non-positive glyph boxes, glyphs outside page bounds, same-word glyph overlap,
or glyph order moving backward inside a text run.

Raster comparison lives in
`PDFVisualLayoutValidationTests.popplerAndMuPDFRenderComparableInkBounds`. It
renders the first representative page through Poppler and MuPDF as raw PNM,
measures non-white pixels and ink bounds, and fails on blank renders, size
divergence, ink-bound divergence, or large ink-coverage divergence.

Together, these tests are now the canonical visual gate for layout-affecting
renderer changes. Remaining gaps are smaller: this is not a full
pixel-perfect golden image suite, but it no longer relies on manual inspection
or word-level geometry alone.
