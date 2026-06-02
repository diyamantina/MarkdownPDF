# Source Code Formatting Model

Date: 2026-06-02

Issue: #103

This document defines the first portable source-code formatting model for
MarkdownPDF. It is an implementation contract for the next source-code rendering
issues, not a public API promise.

Product boundary: the renderer must remain Pure Swift, generate PDF bytes
directly, and work on macOS and Linux. The model does not require PDFKit,
CoreGraphics, WebKit, browser renderers, LaTeX, JavaScript, Python, shell
renderers, C Markdown libraries, or C PDF libraries. iOS support is not implied.

## Inputs

MarkdownPDF targets CommonMark plus GitHub Flavored Markdown tables and images.
For code formatting, the relevant compatibility source is the GitHub Flavored
Markdown spec:

- Tabs used for Markdown block structure behave with 4-character tab stops.
- A fenced code block starts with a fence of at least three backticks or tildes.
- A closing fence must use the same character and be at least as long as the
  opening fence.
- Fenced code blocks can be followed directly by paragraphs and other blocks.
- A fenced code block info string is metadata. The first word is typically used
  as a language name, but the spec does not require a presentation.
- Code spans use equal-length backtick delimiter strings. Line endings become
  spaces, and one leading and trailing space are stripped only when both exist
  and the content is not all spaces.

Source: <https://github.github.com/gfm/>

## Baseline Scope

The baseline source-code model covers:

- Fenced code block layout.
- Inline code span presentation.
- Tabs, leading spaces, blank lines, long tokens, and page breaks.
- Extraction order for source lines and soft-wrapped continuations.
- Spacing around adjacent code, block quotes, paragraphs, and headings.
- Witness requirements for Poppler, MuPDF, qpdf, pdfinfo, raster output, and
  structural inspection.

The baseline source-code model does not cover:

- Syntax coloring.
- Language parsing.
- Semantic pretty printing.
- Visible line numbers.
- Tagged PDF structure.
- macOS-only font discovery.
- iOS validation.

## Internal Model

The first implementation must keep these types internal to the renderer. A
public API should be added only after a real consumer needs to configure it.

### SourceCodeBlock

`SourceCodeBlock` represents one fenced code block after Markdown parsing.

Fields:

- `info`: optional raw info string.
- `languageHint`: optional first whitespace-delimited word from `info`.
- `sourceLines`: ordered `[SourceCodeLine]`.
- `policy`: `SourceCodeLayoutPolicy`.

Rules:

- `languageHint` is metadata only in the baseline.
- Non-Mermaid language hints are not rendered as visible labels.
- Mermaid remains a separate explicit code-block path.
- The original source line order is the PDF emission order.

### SourceCodeLine

`SourceCodeLine` represents one author line from the fenced block.

Fields:

- `index`: zero-based source line index.
- `originalText`: the raw line after Markdown line-ending normalization.
- `displayText`: `originalText` with tabs expanded to spaces.
- `leadingColumnCount`: count of leading display columns before the first
  non-space scalar.
- `isBlank`: true when `displayText` is empty or all spaces.

Rules:

- Source line boundaries are mandatory breaks. The layout never joins two
  source lines into one visual line.
- Blank source lines produce blank visual segments with normal code line height.
- Tabs are expanded for display and extraction in the baseline. Literal tab
  extraction is a future feature if needed.

### SourceCodeSegment

`SourceCodeSegment` represents one visual segment of one source line.

Fields:

- `sourceLineIndex`: source line index.
- `segmentIndex`: zero-based segment index inside the source line.
- `text`: display text emitted into the PDF content stream.
- `xOffsetColumns`: visual columns added before drawing this segment. The value
  is zero for the first segment of a source line.
- `measuredWidth`: width in PDF points.
- `isSoftWrappedContinuation`: true when `segmentIndex > 0`.

Rules:

- Segment order must match extraction order.
- Continuation segments immediately follow their previous segment in PDF
  content stream order unless a page break is required.
- A segment is never split during PDF drawing. Splitting decisions happen before
  emission.
- Trailing spaces may be removed from a visual segment when they occur only at a
  soft-wrap boundary, but leading indentation on the first segment is preserved.

### SourceCodeLayoutPolicy

`SourceCodeLayoutPolicy` defines deterministic layout values.

Fields:

- `tabWidthColumns`: 4.
- `fontRole`: monospaced.
- `fontSize`: `baseFontSize * 0.9`.
- `lineHeight`: `fontSize * 1.4`.
- `horizontalPadding`: 6 PDF points.
- `verticalPadding`: 6 PDF points above and below code text.
- `minimumFollowingBlockGap`: `max(8, baseFontSize * 0.75)` PDF points.
- `continuationIndentColumns`: 2.
- `maximumContinuationIndentColumns`: 8.

Rules:

- The code area is the current content width minus horizontal padding on both
  sides.
- The first visual segment draws at the code area left. Its `text` includes
  expanded leading spaces so extraction and display preserve indentation.
- A continuation segment draws at:
  `min(sourceIndentColumns + continuationIndentColumns,
  maximumContinuationIndentColumns)`.
- If the page or margin configuration leaves too little width for that
  continuation indent, the implementation may reduce continuation indentation
  until at least 8 columns remain for text.
- Code text remains ragged-right. The renderer must not justify or stretch
  spaces in source code.

## Wrapping Policy

The wrapping algorithm is greedy and metric-driven in the baseline.

For each source line:

1. Expand tabs to spaces using 4-column stops.
2. Measure with the same font metrics used for PDF emission.
3. If the full display line fits in the code area, emit one segment.
4. If it does not fit, choose the last usable break opportunity before the
   width limit.
5. Prefer break opportunities in this order:
   - after spaces,
   - after punctuation that is common in code paths or expressions,
   - after camel-case separators only if a later issue defines that behavior,
   - before the width limit by scalar or grapheme cluster when no better break
     exists.
6. Repeat until the source line is fully segmented.

Punctuation break characters for the first implementation:

```text
.,;:/\\()[]{}<>+-=*%&|!?_
```

Long unbreakable identifiers, hashes, and URLs must still stay inside the page.
When necessary, they split at grapheme cluster boundaries.

## Block Spacing Policy

Code block layout must reserve visible space around neighboring blocks.

Rules:

- The gray code background surrounds only code text and padding.
- The following block must start at least `minimumFollowingBlockGap` below the
  code background.
- A block quote following code uses indentation only and must not draw a
  vertical border stroke.
- A heading following a block quote or code block must apply its heading top
  spacing after the previous block has fully advanced `y`.
- Code, quote, paragraph, and heading adjacency is a model invariant because it
  caused manual artifact regressions.

## Inline Code Policy

Inline code is not the same model as fenced code.

Rules:

- Inline code remains one or more `PDFTextRun` values with the monospaced role.
- Inline code does not receive a background fill in the baseline.
- Inline code participates in paragraph wrapping as an atomic run unless a
  future issue adds code-span-specific splitting.
- The parser should eventually match GFM equal-length backtick delimiters and
  code-span whitespace normalization. That parser work can be implemented with
  #104 if it stays small, or as a separate follow-up issue if it expands.

## Page Break Policy

Code blocks may span pages.

Rules:

- A page fragment must contain the code background for only the visible
  segments on that page.
- The renderer may break between visual segments, including between
  continuations of one source line.
- The renderer must not break inside one segment.
- A code block must make forward progress on every page. At least one visual
  segment must fit after padding; otherwise the renderer must reduce padding or
  use the existing oversized-block policy instead of looping.
- Extraction order remains source order across page breaks.

## PDF Emission Policy

Rules:

- The emitted font role is `.courier` with `PDFOptions.FontSet.pdfBase` unless
  the caller supplies an embedded monospace font.
- Measurement and emission must use the same `PDFTextRun` text after tab
  expansion.
- The baseline must emit expanded spaces, not literal tabs, because PDF
  viewer tab interpretation is not a portable layout guarantee.
- No line-number text is emitted in the baseline.
- No non-Mermaid language label text is emitted in the baseline.
- PDF text operators for a source line's segments are emitted in visual order
  and source order.

## Witness Requirements

The #104 implementation and #105 witness hardening must cover:

- Mixed tabs and spaces.
- Deep indentation.
- Long identifiers with no spaces.
- Long URLs and file paths.
- Punctuation-heavy generic code.
- Blank lines inside code blocks.
- Code blocks that cross pages.
- Code directly followed by block quotes.
- Block quotes directly followed by headings.
- Code directly followed by paragraphs.
- Code inside manuscript-scale fixtures.

Required checks:

- Swift structural inspection for valid streams, resource usage, page count, and
  xref offsets.
- `qpdf --check`.
- `pdfinfo` page size and page count.
- `pdftotext` extraction for expected code fragments in source order.
- `pdftotext -tsv` for word boxes inside page bounds and no overlap.
- MuPDF structured text for character quad overlap.
- Poppler and MuPDF raster comparison for nonblank, comparable pages.
- A structural check that portable block quotes do not emit vertical border
  strokes.

## Platform Notes

- Portable macOS/Linux: every baseline behavior above belongs in the shared
  Swift renderer.
- macOS-only: no baseline behavior requires macOS APIs.
- Linux-only: Poppler interpretation differences belong in test witness
  tolerance unless production PDF bytes require an OS-specific branch as a last
  resort.
- iOS: not claimed. iOS needs its own build and witness strategy before support
  can be asserted.

## Deferred Work

- Syntax coloring and tokenization remain #106.
- Visible line numbers need a separate extraction policy.
- Tagged PDF structure is out of scope for the baseline.
- Exact literal tab extraction is deferred until there is a product requirement.
- Full GFM parser compliance for code spans and long fences may be implemented
  in #104 if small, or split into follow-up parser issues.
