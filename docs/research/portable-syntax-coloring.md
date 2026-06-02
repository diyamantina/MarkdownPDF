# Portable Syntax Coloring Study

Date: 2026-06-02

Issue: #106

Decision in #106: defer visible syntax coloring until the source-code layout
baseline and witness stack were in place.

Implementation in #120: add opt-in portable syntax coloring for supported
fenced-code language hints. The default remains uncolored. Unsupported or
missing language hints render plain code with no warning in the PDF.

## Product Boundary

Production MarkdownPDF must remain Pure Swift, generate PDF bytes directly, and
work on macOS and Linux. Syntax coloring must not introduce PDFKit,
CoreGraphics, WebKit, browser renderers, LaTeX, JavaScript, Python, shell
renderers, C Markdown libraries, C PDF libraries, or Apple-only APIs. iOS
support is not implied.

## Sources

| Source | Observation | MarkdownPDF impact |
|---|---|---|
| GitHub Flavored Markdown spec, fenced code blocks. <https://github.github.com/gfm/#fenced-code-blocks> | The info string is metadata. The first word is typically used as a language name in HTML, but the spec does not mandate a treatment. | MarkdownPDF can keep language hints as metadata and is not required to color code to be GFM-compatible. |
| Advait Sarkar, "The impact of syntax colouring on program comprehension", PPIG 2015. <https://ppig.org/papers/2015-ppig-26th-sarkar1/> | Small eye-tracking study reports faster task completion with coloring and weaker effect for experienced programmers. | Coloring can help readability, but this evidence does not make coloring a correctness requirement. |
| Tanya R. Beelders and Jean-Pierre L. du Plessis, "Syntax highlighting as an influencing factor when reading and comprehending source code", Journal of Eye Movement Research, 2016. <https://bop.unibe.ch/JEMR/article/view/2429> | Fixations, fixation duration, and regressions were higher for black-and-white snippets, but not significantly. Students still preferred colored snippets subjectively. | Evidence is mixed enough that layout correctness, extraction, and portability should stay ahead of coloring. |
| Pygments token documentation. <https://pygments.org/docs/tokens/> | Uses a broad hierarchical token taxonomy: text, keyword, name, literal, string, number, operator, punctuation, comment, generic, and subtypes. | Useful as a taxonomy reference. Not suitable as a dependency because it is Python and broad language support would imply broad lexer obligations. |
| Tree-sitter syntax highlighting docs. <https://tree-sitter.github.io/tree-sitter/3-syntax-highlighting.html> | Highlighting is driven by parser trees plus `.scm` query files with captures such as keyword, function, type, property, and string. | Strong model, but not suitable as a dependency because it requires external parsers and non-Swift infrastructure. Query-driven capture names are useful design inspiration. |
| TextMate language grammar manual. <https://macromates.com/manual/en/language_grammars> | Grammars assign scope names through property-list grammar rules. | Broad ecosystem, but portable implementation would require grammar parsing and regex behavior outside the current scope. |
| SwiftSyntax README. <https://github.com/swiftlang/swift-syntax> | Provides a source-accurate tree representation for Swift source and is aligned with Swift toolchain releases. | Pure Swift and portable for Swift code, but language-specific and version-coupled. Not a general Markdown code coloring solution. |
| Splash README. <https://github.com/JohnSundell/Splash> | Pure Swift syntax highlighter for Swift code, advertised for Mac and Linux. | Possible source inspiration for a future Swift-only lexer. Not enough for broad fenced-code language claims. |

## Current Renderer Fit

MarkdownPDF already has the low-level PDF pieces needed for coloring:

- `PDFTextRun` has a `color`.
- `PDFPageCanvas` emits fill color operators before text runs.
- Code blocks already use a monospaced role and measured text runs.
- The visual witness stack already checks extraction, Poppler word boxes, MuPDF
  character quads, qpdf, pdfinfo, and raster output.

The missing piece is not PDF color output. The missing piece is a portable,
well-scoped tokenizer policy.

Current code block rendering expands tabs and wraps code into measured
`PDFTextRun` lines. A syntax-colored implementation would need token spans that
survive:

- tab expansion,
- soft wrapping,
- page fragmentation,
- extracted text order,
- embedded-font ToUnicode output,
- fallback to base PDF fonts,
- unsupported language hints.

## #106 Recommendation

Do not implement visible syntax coloring in #106.

Close #106 with a deferred recommendation:

1. Keep fenced code blocks uncolored in the current epic.
2. Treat the GFM info string as metadata only.
3. Do not claim language-specific coloring for any language.
4. Do not add highlighter dependencies.
5. Add a future issue only if a product need appears for colored code in PDF
   output.

## Implemented Portable Model

The #120 implementation starts with internal types equivalent to:

```swift
enum SourceCodeTokenKind {
    case text
    case keyword
    case identifier
    case string
    case number
    case comment
    case operatorToken
    case punctuation
    case error
}

struct SourceCodeToken {
    var lineIndex: Int
    var range: Range<String.Index>
    var kind: SourceCodeTokenKind
}
```

Rules:

- The token model must not rewrite code.
- Unsupported language hints render as plain code.
- Token ranges must refer to tab-expanded display text or must carry an
  explicit mapping from original source text to display text.
- Tokenization failure renders plain code, not partially corrupt color output.
- The tokenizer is deliberately narrow. It supports Swift, C-family and Metal
  hints, Python, and JSON. Broad language claims are not made.

## Color Policy

Use DeviceRGB colors only, matching the current output profile.

Future colors must satisfy:

- readable contrast against the existing gray code-block background,
- readable contrast in grayscale or print-like raster output,
- no dependence on color alone for extraction or correctness,
- stable PDF text extraction identical to the uncolored code text,
- deterministic operator output that can be inspected structurally.

## Required Witnesses For Coloring

The #120 implementation adds tests that prove:

- `pdftotext` extraction is unchanged from the uncolored code text.
- Poppler word boxes stay inside the code block and do not overlap.
- MuPDF character quads stay non-overlapping.
- qpdf validates syntax and streams.
- Poppler and MuPDF rasters are nonblank and comparable.
- The content stream emits expected fill colors for token runs.
- Unsupported language hints render plain code without warnings in the PDF.
- At least one code-heavy manuscript fixture includes comments, strings,
  numbers, identifiers, operators, punctuation, long lines, tabs, and page
  breaks.

## Platform Notes

- Portable macOS/Linux: the internal token model and color emission live in the
  shared Swift renderer.
- macOS-only: no part of this recommendation requires macOS APIs.
- Linux-only: Poppler interpretation differences belong in witness tolerance
  unless production PDF bytes need an OS-specific branch as a last resort.
- iOS: not claimed. iOS needs separate build and witness strategy before any
  support claim.

## Conclusion

Syntax coloring is useful presentation, not required correctness. The #120
implementation keeps it opt-in and backs it with extraction, Poppler geometry,
MuPDF character quads, qpdf, content-stream color inspection, and raster
witnesses.
