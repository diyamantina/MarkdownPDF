# Source Code Typesetting Literature

Date: 2026-06-02

Issue: #101

This note records literature and standards that matter for rendering source code
inside MarkdownPDF output. The product boundary remains unchanged: production
implementation must be Pure Swift, must generate PDF bytes directly, and must
work on macOS and Linux without Apple-only renderers or non-Swift formatting
engines. iOS support is not implied.

## Scope

The immediate question is not how to reformat source code semantically. Markdown
already carries fenced code blocks as author-provided text. The first MarkdownPDF
source-code formatting problem is static PDF presentation:

- Preserve spaces, indentation, tabs, and line boundaries where possible.
- Keep code readable when lines are longer than the page width.
- Keep extraction order useful for copy and search.
- Avoid clipped glyphs, overlapping words, and broken page transitions.
- Decide whether syntax coloring belongs in the first implementation increment
  or a later one.

## Source Map

| Source | Type | Relevance |
|---|---|---|
| Donald E. Knuth and Michael F. Plass, "Breaking Paragraphs into Lines", Software: Practice and Experience, 1981. <https://gwern.net/doc/design/typography/tex/1981-knuth.pdf> | Scientific article | Establishes global line-breaking as an optimization problem. Relevant to prose and comments, but code blocks should not inherit space stretching or justification behavior. |
| Derek C. Oppen, "Prettyprinting", ACM TOPLAS, 1980. DOI 10.1145/357114.357115. <https://doi.org/10.1145/357114.357115> and accessible record <https://www.mendeley.com/catalogue/d931d658-9925-3f83-b6f2-8e8f7e7d8885/> | Scientific article | Canonical streaming pretty-printer algorithm. Relevant if MarkdownPDF ever formats parsed code, and useful as a model for bounded-memory line decisions. |
| Philip Wadler, "A Prettier Printer", 2003. <https://homepages.inf.ed.ac.uk/wadler/papers/prettier/prettier.pdf> | Technical paper | Defines a compact document algebra with nesting, grouping, and width-sensitive layout. Relevant for future structured code formatting, less relevant for preserving raw fenced text. |
| Advait Sarkar, "The impact of syntax colouring on program comprehension", PPIG, 2015. <https://ppig.org/papers/2015-ppig-26th-sarkar1/> | Empirical study | Syntax highlighting improved task completion time in a small eye-tracking study, with weaker effect for more experienced programmers. Supports investigating color later, not making it a baseline dependency. |
| "Syntax Highlighting as an Influencing Factor When Reading and Comprehending Source Code", Journal of Eye Movement Research, 2014. <https://www.mdpi.com/1995-8692/9/1/1> | Empirical study | Reports code reading differs from natural-language reading and discusses mixed evidence around color, fixation counts, and comprehension. Supports caution around broad syntax-color claims. |
| David Binkley et al., "The impact of identifier style on effort and comprehension", Empirical Software Engineering, 2013. <https://files.software-carpentry.org/training-course/2012/08/binkley-identifier-style-effort-comprehension-2012.pdf> | Empirical study | Shows code readability is not just paragraph readability. Identifier shapes, visual search, and eye movement matter. Supports preserving author code structure and avoiding arbitrary reflow. |
| John R. Miara et al., "Program Indentation and Comprehensibility", Communications of the ACM, 1983. <https://www.cs.umd.edu/~ben/papers/Miara1983Program.pdf> | Empirical study | Studies indentation level and blocking style in program comprehension. Supports preserving indentation and choosing moderate visual indentation for generated code blocks. |
| Yorimoto Kou and Shimpei Matsumoto, "Quantitative Quality Evaluation of the Impact of Indentation in Source Code Using Eye-Tracking", IIAI Letters on Institutional Research, 2024. DOI 10.52731/lir.v004.293. <https://cir.nii.ac.jp/crid/1390301529918660864> | Empirical study | Eye-tracking study focused on indentation and readability. Useful as follow-up evidence for #102 when comparing current renderer indentation behavior. |
| Cartic Ramakrishnan et al., "Layout-aware text extraction from full-text PDF of scientific articles", Source Code for Biology and Medicine, 2012. <https://link.springer.com/article/10.1186/1751-0473-7-7> | Scientific article | Shows PDF extraction quality depends on reading order, blocks, headers, figures, and layout classification. Relevant to code extraction and line-number policy. |
| ISO 32000-1:2008, PDF 1.7 reference. <https://opensource.adobe.com/dc-acrobat-sdk-docs/standards/pdfstandards/pdf/PDF32000_2008.pdf> | Standard | Defines text positioning, glyph metrics, word spacing, character spacing, encodings, and ToUnicode behavior. Relevant to every code block PDF emission change. |

## Findings

### Code blocks are not ordinary justified prose

DOCUMENTED: Knuth-Plass line breaking optimizes paragraph breaks using boxes,
glue, and penalties. It is powerful for prose because spaces can stretch and
shrink.

INFERENCE: Fenced code should not use prose justification. Stretching spaces in
code changes alignment and damages the visual role of indentation. The useful
part of line-breaking research is the idea of choosing better break positions
than greedy wrapping. The dangerous part is applying flexible whitespace to
source code.

Implementation direction:

- Keep code blocks ragged-right.
- Preserve literal spaces inside source lines.
- Use deterministic soft wrapping only when a source line cannot fit.
- Favor breaks after existing whitespace or punctuation, not arbitrary glyph
  splitting, unless an unbreakable token is wider than the code area.

### Pretty printing is a later problem, not the baseline problem

DOCUMENTED: Oppen and Wadler describe algorithms that format structured
documents, usually built from parsed source or another tree. These algorithms
decide where groups, nests, and breaks should appear.

INFERENCE: MarkdownPDF should not parse arbitrary languages in the first source
formatting increment. A fenced code block is already formatted input. Rewriting
it as if MarkdownPDF knows the language would change meaning, create language
support obligations, and add hard-to-test behavior.

Implementation direction:

- First implement faithful presentation of raw fenced text.
- Treat language labels as metadata for captions, future color, or policy, not
  as permission to reformat the program.
- Reuse pretty-printer ideas only for an internal visual line model: line,
  indent, tab stop, segment, soft break, page break.

### Syntax coloring has evidence, but it is not a safe first dependency

MEASURED: Sarkar reports a small controlled eye-tracking study where syntax
highlighting improved task completion time and the effect weakened with
programming experience.

DOCUMENTED: Later eye-movement work discusses mixed or finer-grained evidence,
including code reading differences from natural-language reading and color
effects that are not always visible in the same metrics.

INFERENCE: Syntax coloring may help, but it is not required to make PDF code
blocks correct. It also introduces tokenization, color profile, contrast, and
copy-extraction questions. It should follow the baseline layout work unless a
very small language-agnostic token model is chosen.

Implementation direction:

- Do not block baseline source-code formatting on syntax coloring.
- Keep syntax coloring issue #106 as an investigation after layout is stable.
- If color is added, require contrast and extraction witnesses, and avoid
  language claims beyond implemented tokenizers.

### PDF extraction requires logical ordering, not only good pixels

DOCUMENTED: Layout-aware PDF extraction research shows that PDF text extraction
can fail when reading order and block structure do not match the logical
document. Headers, footers, captions, and layout boxes can interrupt extracted
narrative.

INFERENCE: For code blocks, visual line numbers are risky if they become
interleaved with code text during extraction. The first implementation should
avoid line numbers or emit them in a way tests can prove does not corrupt the
copied code.

Implementation direction:

- Emit code text in source order.
- Keep each visual continuation in an extraction order that reconstructs the
  source line as predictably as possible.
- Defer line numbers until the project has a tagged-PDF or artifact policy for
  numbers.
- Test both visual geometry and extracted text.

### The PDF writer must stay metric-driven

DOCUMENTED: ISO 32000-1 defines text positioning and glyph displacement through
font metrics, text state, character spacing, word spacing, text showing
operators, and font encodings. MarkdownPDF already validates text extraction and
geometry with qpdf, Poppler, and MuPDF.

INFERENCE: Source-code formatting must be driven by the same glyph measurement
model used for emitted PDF bytes. Tests that only inspect strings are not
enough. The witness stack needs Poppler word boxes, MuPDF character quads, and
raster comparison for code-heavy fixtures.

Implementation direction:

- Use Courier or embedded monospace metrics consistently for code roles.
- Expand tabs to fixed column stops before measuring.
- Ensure soft wraps reserve visible continuation width if a continuation marker
  is chosen.
- Add code-heavy visual witness fixtures before claiming the layout is correct.

## Proposed First Model

The first source-code formatting model should be conservative:

1. Treat fenced code content as literal source text.
2. Normalize line endings only.
3. Expand tabs to deterministic columns, with a default tab width documented in
   the renderer options or internal policy.
4. Lay out each source line in a code area with fixed left and right padding.
5. Preserve leading spaces on the first visual segment of each source line.
6. Soft-wrap long source lines into continuation segments when needed.
7. Preserve extraction order by emitting continuation segments immediately after
   the preceding segment.
8. Do not add syntax coloring in the baseline.
9. Do not add line numbers in the baseline.
10. Validate through structural, extraction, geometry, and raster witnesses.

## Witness Requirements

The implementation issues should include fixtures with:

- Deep indentation.
- Mixed tabs and spaces.
- Long strings and URLs.
- Long identifiers with no spaces.
- Punctuation-heavy generic code.
- Comments and blank lines.
- Code blocks crossing page boundaries.
- Adjacent prose, tables, and Mermaid blocks.

Required witnesses:

- Swift structural checks for page count, stream lengths, fonts, and xref.
- `qpdf --check`.
- `pdfinfo` for page size and page count.
- `pdftotext` for extractable code fragments.
- `pdftotext -tsv` for word boxes and off-page checks.
- MuPDF structured text for character quads.
- Poppler and MuPDF raster comparison for code-heavy pages.

## Platform Notes

- Portable macOS/Linux: all findings above can be implemented in the shared
  Swift renderer and validated with existing qpdf, Poppler, and MuPDF tools.
- macOS-only: none of the baseline findings require macOS-only APIs.
- iOS: not claimed. iOS would need explicit tests and a validation plan because
  the current witness stack depends on external command-line tools in CI.

## Open Questions For #102

- Which current renderer symbols own fenced-code measurement and wrapping?
- Does inline code use the same monospace width policy as fenced blocks?
- Do current code blocks preserve tabs, or do they collapse during parsing?
- Can extracted text reconstruct soft-wrapped code without introducing extra
  spaces?
- Should line numbers be rejected for now or reserved behind a future tagged-PDF
  issue?
