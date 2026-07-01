# Source Code Renderer Analysis

Date: 2026-06-02

Issue: #102

This note compares the source-code typesetting research in
`source-code-typesetting-literature.md` with the current MarkdownPDF parser,
layout, PDF writer, and witness tests.

Product boundary: production code remains Pure Swift, writes PDF bytes directly,
and must work on macOS and Linux. This analysis does not introduce PDFKit,
CoreGraphics, WebKit, browser renderers, LaTeX, JavaScript, Python, shell
renderers, C Markdown libraries, or C PDF libraries. iOS support is not implied.

## Current Renderer Paths

| Area | Current path or symbol | Current behavior |
|---|---|---|
| Block AST | `MarkdownBlock.codeBlock(info:code:)` in `MarkdownBlock.swift` | Stores fenced-code info text and the full code string. |
| Inline AST | `MarkdownInline.code(String)` in `MarkdownBlock.swift` | Stores inline code as a single inline node. |
| Fenced-code parser | `BlockParser.parseFencedCodeBlock()` in `MarkdownParser.swift` | Detects triple backtick and triple tilde fences, stores info text, and joins raw code lines with `\n`. |
| Inline-code parser | `InlineParser.Scanner.parseCodeSpan()` in `InlineParser.swift` | Handles one-backtick code spans and replaces newlines with spaces. |
| Block dispatch | `MarkdownPDFRenderer.render(_:)` in `MarkdownPDFRenderer.swift` | Sends Mermaid code blocks to the Mermaid renderer and all other code blocks to `renderCodeBlock(_:)`. |
| Code block layout | `MarkdownPDFRenderer.renderCodeBlock(_:)` | Splits source lines, wraps each through `wrappedLines(_:maxWidth:)`, draws gray background fragments, and paginates by measured line height. |
| Shared wrapping | `MarkdownPDFRenderer.wrappedLines(_:maxWidth:)`, `tokenize(_:)`, `splitOversizedToken(_:maxWidth:)` | Reuses the general line-break path for prose, tables, HTML fallback, headings, inline runs, and code blocks. |
| Line-break detector | `LineBreakOpportunityDetector` | Converts tabs to single spaces, breaks after spaces, and splits no-space scripts by character. |
| Text width | `PDFEmbeddedFontCatalog.width(of:fallbackFontSet:)`, `PDFTextRun.width(fontSet:)` | Uses embedded font shaping when supplied, otherwise standard PDF font metrics. |
| PDF text emission | `PDFPageCanvas.drawTextRun(...)` | Emits text operators with either PDF base-font literal strings or embedded CID text plus ToUnicode maps. |
| Code font policy | `PDFOptions.FontSet.pdfBase`, `PDFOptions.FontSet.pdfBaseMonospaced`, `PDFOptions.EmbeddedFonts.monospaced` | Uses Courier by default for code roles, with caller-supplied embedded monospace font support. |
| Block quotes | `MarkdownPDFRenderer.render(_:)` case `.blockQuote` | Uses indentation only. The portable renderer no longer emits vertical quote border strokes. |
| Visual witnesses | `PDFVisualLayoutValidationTests`, `PopplerTextLayout`, `MuPDFStructuredText` | Validate generated PDFs with Poppler word boxes, MuPDF character quads, text extraction, qpdf, pdfinfo, and raster comparison. |

## Research Alignment

### What already aligns

- Fenced code is preserved as author-provided text. The parser does not attempt
  to parse or reformat arbitrary programming languages.
- Code blocks use a monospace role. The default role is Courier, and the
  embedded-font path can provide an explicit monospace font without discovering
  platform fonts.
- Code layout is metric-driven. The renderer measures runs before drawing, and
  tests already inspect Poppler word boxes, MuPDF character quads, and rasters.
- Line numbers are not emitted. That keeps extracted text from interleaving
  visual line-number columns with code.
- Block quotes are now portable indentation-only output, which avoids the
  vertical stroke collision reported during manual artifact review.

### What does not yet align

- Tabs do not have a code-specific column policy. `LineBreakOpportunityDetector`
  normalizes each tab to one space before wrapping, which is acceptable for
  prose but not for source indentation.
- Code blocks reuse prose wrapping. `renderCodeBlock(_:)` sends each source line
  through `wrappedLines(_:maxWidth:)`, so code has no dedicated visual line
  model for indentation, continuation segments, tab stops, blank lines, or
  future language labels.
- Inline code only supports the simplest CommonMark shape. `parseCodeSpan()`
  does not handle multiple-backtick delimiters or literal backticks inside code
  spans.
- Fenced-code parsing records only a three-character fence marker. It accepts a
  closing line that starts with the same three characters, but it does not model
  longer opening fence length or the exact CommonMark closing-fence rule.
- Extraction is tested at the fixture level, but there is no focused assertion
  that a soft-wrapped code line reconstructs predictably from Poppler text
  extraction.
- Existing fixtures cover code blocks, but the code-specific stress surface is
  still implicit. The source-code epic needs a fixture with mixed tabs, leading
  spaces, long URLs, long identifiers, blank lines, punctuation-heavy generic
  code, adjacent headings, adjacent quotes, and page breaks inside code blocks.
- The screenshot regressions show a spacing policy gap around dense code block,
  quote, paragraph, and heading transitions. The renderer has local spacing
  values, but no named source-code block model that makes those transitions a
  first-class invariant.

## Gap Matrix

| Gap | Category | Impact | Next issue |
|---|---|---|---|
| Dedicated source-code visual line model is missing | Correctness | Code indentation and continuation behavior depends on prose wrapping rules. | #103 |
| Deterministic tab expansion is missing | Correctness | Tabs collapse to one space before measurement, damaging author indentation. | #103, #104 |
| Code block continuation policy is implicit | Readability | Long lines wrap, but continuations are not modeled as source-line segments. | #103, #104 |
| Code block spacing with quotes and headings is not named | Readability | Dense manuscript content can look crammed even when individual glyph boxes do not overlap. | #104, #105 |
| Soft-wrapped code extraction lacks a focused witness | PDF extraction | Copy and search behavior can regress without failing current broad assertions. | #105 |
| Inline code span parsing is incomplete | Correctness | CommonMark code spans with literal backticks are not represented faithfully. | Future issue or #104 if scoped small |
| Fenced-code closing rules are approximate | Correctness | Longer fences and edge cases can parse differently from CommonMark. | Future issue or #104 if scoped small |
| Syntax coloring lacks a portable tokenizer policy | Implementation complexity | Coloring could create unsupported language claims and contrast regressions. | #106 |

## Recommended Order

The existing epic order remains correct.

1. #103 should define the portable source-code model before code changes. The
   model should name source lines, visual continuation segments, code padding,
   tab width, continuation indentation, blank lines, extraction order, and page
   break behavior.
2. #104 should implement the baseline model in Swift. It should replace the
   prose wrapping path for fenced-code blocks with the dedicated code model,
   keep block quotes indentation-only, and fix spacing around code, quotes,
   paragraphs, and headings.
3. #105 should harden witnesses. It should add focused extraction and geometry
   assertions for soft-wrapped code, tabs, leading spaces, page-crossing code
   blocks, quote adjacency, and the reported no-vertical-quote-line policy.
4. #106 should remain an investigation. Syntax coloring should not block the
   baseline because it requires tokenizer scope, contrast policy, extraction
   policy, and language-support boundaries.

## Implementation Notes For #103

The smallest portable model should be internal first:

- `SourceCodeBlock`: literal source lines plus optional info string.
- `SourceCodeLine`: original text and tab-expanded text.
- `SourceCodeSegment`: one visual segment with source-line index, segment index,
  displayed text, x offset, measured width, and extraction-order intent.
- `SourceCodeLayoutPolicy`: tab width, code font size, line height, padding,
  continuation indent, and soft-wrap break preference.

The model should not expose public API unless a consumer needs it. The renderer
can start with private types in `MarkdownPDFRenderer.swift` or a small internal
file if the implementation becomes hard to read.

## Implementation Notes For #104

The baseline renderer change should:

- Expand tabs to fixed columns before measurement.
- Preserve leading spaces on the first visual segment.
- Use a predictable continuation indent for wrapped segments.
- Keep each source line's continuation segments adjacent in PDF emission order.
- Reserve vertical padding before and after the code block fragment.
- Continue to use Courier or the caller-supplied embedded monospace role.
- Keep block quotes indentation-only, with no vertical border stroke in portable
  output.
- Re-check dense code, quote, paragraph, and heading sequences from the
  manuscript fixtures.

## Implementation Notes For #105

Witnesses should prove more than syntax validity:

- Poppler text extraction contains expected code fragments in source order.
- Poppler TSV word boxes remain inside page bounds and do not overlap.
- MuPDF character quads do not overlap inside code-heavy pages.
- Poppler and MuPDF rasters both render nonblank, comparable pages.
- A focused code fixture includes tabs, leading spaces, long identifiers, long
  URLs, blank lines, quote adjacency, heading adjacency, and a page break inside
  a code block.
- The block quote stroke regression is checked structurally and through a dense
  visual fixture.

## Platform Notes

- Portable macOS/Linux: all recommended baseline changes can live in the shared
  Swift renderer and test suite.
- macOS-only: none of the baseline changes require macOS-only APIs.
- Linux-only: Poppler interpretation differences should remain test-side
  tolerance policy unless production behavior has a real Linux rendering bug.
- iOS: not claimed. iOS would need its own validation plan because the current
  witness stack depends on command-line tools in development and CI.
