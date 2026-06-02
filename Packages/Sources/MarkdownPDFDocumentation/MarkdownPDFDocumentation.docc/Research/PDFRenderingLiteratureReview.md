# PDF rendering literature review

This note records a source-backed research pass on PDF rendering, document
typesetting, and validation. It complements `mac-pdf-renderer-research.md` by
focusing on literature and standards that apply to both Linux and macOS.

## Scope

Applied constraints:

- Cross-platform findings must remain implementable in pure Swift.
- Linux support is mandatory for the portable `MarkdownPDF` product.
- OS-specific APIs may inform optional experiments, but must not define the
  shared renderer architecture.
- The public repo must not add JavaScript, Python, shell renderers, browser
  drivers, PDFKit, WebKit, LaTeX, C Markdown libraries, or C PDF libraries.
- Every platform-specific claim must say whether it is cross-platform,
  Linux-compatible, macOS-compatible, OS-specific, or research-only.

## Summary

DOCUMENTED: The most relevant literature says article-grade PDF output is a
typesetting and document-semantics problem, not only a byte-serialization
problem. High-quality output needs line-breaking, pagination, font handling,
semantic structure, metadata, and validation.

REPO IMPACT: The Linux and macOS renderer should own the common document model,
layout decisions, table layout, structural PDF writer, font model, and fast
structural tests in pure Swift. Platform APIs can be optional backends later,
but the primary implementation path should not depend on Apple frameworks.

## Typesetting algorithms

DOCUMENTED: Knuth and Plass describe paragraph breaking as an optimization over
the whole paragraph instead of a greedy line-at-a-time decision. Their model uses
boxes, glue, and penalties, and selects optimum breakpoints with dynamic
programming.

Source:
https://typographix.binets.fr/files/knuth-plass-breaking.pdf

REPO IMPACT:

- Keep the current greedy wrapper as the simple baseline.
- Add a future pure-Swift paragraph breaker behind a small internal seam.
- Use measured font advances from the active font set as box widths.
- Treat spaces, hyphenation points, inline code, links, and math-like spans as
  separate penalty classes.
- Start with ragged-right optimization before full justification.

DOCUMENTED: Plass's pagination work frames page breaking as a separate
typesetting problem with page constraints, inserts, footnotes, and total
badness. Google Books exposes only metadata and limited text, so this source is
useful as a pointer, not enough for implementation details.

Source:
https://books.google.com/books/about/Optimal_Pagination_Techniques_for_Automa.html?id=SmogAQAAIAAJ

REPO IMPACT:

- Do not hard-code page breaking into individual render functions forever.
- Move toward a vertical layout list that can score candidate page breaks.
- Tables, figures, headings, and ToC entries should produce explicit vertical
  boxes with keep rules.

DOCUMENTED: NIST's 1967 state-of-the-art review establishes that automatic
typographic-quality typesetting was already treated as a broad systems problem,
not a simple printer output problem.

Source:
https://www.nist.gov/publications/automatic-typographic-quality-typesetting-techniques-state-art-review

REPO IMPACT:

- Keep the renderer architecture layered: parse, shape/measure, lay out, then
  serialize PDF.
- Avoid coupling PDF object writing to Markdown parsing.

Platform note: These algorithms are cross-platform. They can and should be
implemented in pure Swift for Linux and macOS.

## Unicode and text shaping

DOCUMENTED: Unicode UAX #14 defines line break opportunities, but not the final
choice of which break opportunity to use. The final selection belongs to higher
level layout software.

Source:
https://www.unicode.org/reports/tr14/

REPO IMPACT:

- A future pure-Swift line breaker should separate break-opportunity discovery
  from line-selection policy.
- Even if an OS-specific shaper is added later, the portable target still needs
  its own baseline rule set for common scripts.
- Add fixtures for no-space scripts and combining marks before claiming Unicode
  line-breaking quality.

DOCUMENTED: Unicode UAX #9 defines bidirectional text ordering. It warns that
formatting characters introduce state that affects rendering.

Source:
https://www.unicode.org/reports/tr9/

REPO IMPACT:

- The current ASCII-oriented portable writer cannot claim complex-script or bidi
  correctness.
- Bidi support should be a documented future feature with dedicated fixtures.
- An OS-specific path may delegate shaping and bidi to a platform shaper, but
  the portable path remains cross-platform and must not depend on it.

DOCUMENTED: The OpenType specification describes glyph substitution and
positioning tables needed for high-quality typography and correct display of
Unicode text in many scripts.

Source:
https://learn.microsoft.com/en-us/typography/opentype/spec/overview

DOCUMENTED: HarfBuzz describes shaping as transforming Unicode code points into
positioned glyphs from a chosen font. It also notes that complex scripts need
script-specific shaping models.

Source:
https://harfbuzz.github.io/shaping-concepts.html

REPO IMPACT:

- For embedded fonts, the renderer needs to distinguish source Unicode,
  shaped glyph ids, glyph advances, and PDF character codes.
- The portable renderer can support Latin first, but the public API and test
  names should avoid implying full OpenType shaping until implemented.
- Directly using HarfBuzz is out of scope for this repo because it is a C
  dependency, but its documentation is useful for the model.

Platform note: Unicode and OpenType are cross-platform standards. Platform text
engines are optional implementation help only.

## PDF semantics and validation

DOCUMENTED: The Library of Congress format note records that PDF 2.0 is ISO
32000-2 and that no-cost downloads are available through the PDF Association. It
also notes that tagged PDF has a structure tree in addition to the content tree.

Source:
https://wwws.loc.gov/preservation/digital/formats/fdd/fdd000474.shtml

DOCUMENTED: The PDF Association maintains the PDF specification archive,
including ISO 32000-2:2020, ISO 32000-1:2008, and related technical
specifications.

Source:
https://pdfa.org/resource/pdf-specification-archive/

DOCUMENTED: The PDF Association tagged PDF guide is intended for implementers of
tagged PDF and PDF/UA.

Source:
https://pdfa.org/resource/tagged-pdf-best-practice-guide-syntax/

REPO IMPACT:

- Visible ToC and PDF outline support should be separate from tagged PDF.
- Tagged PDF and PDF/UA need a logical structure tree, not just drawing
  commands.
- PDF/A and PDF/UA should be optional targets with explicit validation gates,
  not accidental byproducts of normal rendering.

DOCUMENTED: veraPDF implements PDF/A and PDF/UA validation using formalized
validation profiles for machine-checkable requirements.

Source:
https://docs.verapdf.org/validation/

DOCUMENTED: A 2017 veraPDF paper describes the project as an open source,
industry-supported PDF/A validator for cultural heritage institutions, reviewed
with PDF Association involvement.

Source:
https://www.sciencedirect.com/org/science/article/abs/pii/S2059581617000319

REPO IMPACT:

- Fast unit tests should continue to check structural invariants directly.
- For PDF/A or PDF/UA milestones, add optional external validation in CI only if
  repo policy permits the tool. Otherwise document manual validation steps and
  keep core tests pure Swift.

Platform note: PDF standards are cross-platform. veraPDF is a Java tool and is
research/validation context only, not a dependency for this Swift package.

## Fonts and extraction quality

DOCUMENTED: Adobe's PDF 1.7 reference describes font programs and ToUnicode CMap
support. The search result exposed the relevant areas, but implementation should
use the full PDF reference or ISO text directly before coding.

Source:
https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.7old.pdf

DOCUMENTED: Fischer, Lundell, and Gamalielsson study PDF/A conformance and font
usage in public-sector PDFs. Their abstract highlights that PDF/A-1 requires
fonts to be legally embeddable for universal rendering, and that proprietary
fonts such as Times New Roman and Arial are common.

Source:
https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4210105

REPO IMPACT:

- Embedded font work must track font license and embeddability metadata.
- For a public repo, do not commit font binaries.
- Default PDF base fonts remain valuable for small, portable PDFs.
- The macOS target can discover installed fonts, but font embedding policy must
  be explicit and testable.

DOCUMENTED: Bast and Korzen describe PDF as layout-based: it specifies fonts and
positions rather than semantic units such as words, paragraphs, captions, and
roles. They built a benchmark from 12,098 scientific articles and evaluated text
extraction tools.

Source:
https://ad-publications.cs.uni-freiburg.de/benchmark.pdf

DOCUMENTED: DeepPDF frames scholarly PDFs as difficult for text extraction
because publications were historically intended for print rather than machine
consumption.

Source:
https://www.ornl.gov/publication/deeppdf-deep-learning-approach-extracting-text-pdfs?page=1

REPO IMPACT:

- "Looks right in Preview" is not enough.
- Add tests that inspect ToUnicode maps, text extraction order, links,
  destinations, and structure once those features exist.
- Keep semantic information from Markdown as long as possible instead of
  flattening everything into positioned text too early.

Platform note: These findings are cross-platform.

## Reader consistency

DOCUMENTED: A study on PDF reader and file inconsistencies analyzed 2,313 PDF
files, then used automated techniques on over 230K documents. The authors report
cross-reader inconsistencies and 30 unique Linux reader bugs.

Source:
https://link.springer.com/article/10.1007/s10664-018-9600-2

REPO IMPACT:

- Do not rely on one viewer as the only oracle.
- Structural tests should be the default fast gate.
- Later release testing can sample multiple readers on Linux and macOS, but that
  should stay outside the pure Swift unit-test core unless implemented as a
  documented optional manual gate.

Platform note: Cross-reader testing is cross-platform in principle. Concrete
viewer choices are platform-specific.

## Tables, figures, and charts

DOCUMENTED: PDF table detection literature repeatedly treats tables as difficult
because table structures vary and PDF preserves presentation more than table
semantics.

Source:
https://journals.sagepub.com/doi/10.1177/0165551514551903

DOCUMENTED: Wang, Phillips, and Haralick generated table ground truth and
evaluated table detection on 1,125 pages, 518 table entities, and 10,941 cell
entities. Their work emphasizes cell, row, column, and header structure.

Source:
https://gsl.lab.asu.edu/wp-content/uploads/sites/117/2022/05/tableicdar01.pdf

REPO IMPACT:

- Table rendering should keep an internal table model with row groups, header
  rows, column alignment, spanning cells, and cell boxes.
- Article-grade table layout should avoid flattening cells into unrelated text
  positions before pagination.
- Future tagged PDF work should preserve table semantics.

DOCUMENTED: Cleveland and McGill's graphical perception work provides a
scientific foundation for statistical graphics using elementary visual encodings.

Sources:

- https://faculty.washington.edu/aragon/classes/hcde411/w13/readings/cleveland84.pdf
- https://academic.oup.com/jrsssa/article/150/3/192/7106201

REPO IMPACT:

- Native chart primitives should start with high-value encodings: position on a
  common scale, aligned bars, dot plots, line plots, and scatter plots.
- Pie charts and angle/area-heavy encodings should not be first-class priority
  for scientific articles.
- Chart rendering should stay vector-native in PDF where possible.

Platform note: Table and chart layout logic is cross-platform. Rendering through
the hand-written PDF writer is the primary Linux and macOS path.

## Recommended order

1. Keep fast structural PDF tests for both Linux and macOS.
2. Add a pure-Swift vertical layout model before adding advanced macOS drawing.
3. Add a pure-Swift text measurement abstraction backed by base font metrics
   now and optional platform shapers later.
4. Add a pure-Swift paragraph breaker for Latin text, using Knuth-Plass ideas
   after fixtures prove current greedy weaknesses.
5. Add table layout as structured layout boxes.
6. Add PDF font embedding and ToUnicode tests as explicit milestones.
7. Add optional PDF/A or PDF/UA targets after validation strategy is settled.

## Open questions

- Which PDF version should the shared renderer target first: PDF 1.7 for broad
  compatibility, PDF 2.0 for better semantics, or configurable output?
- Should the portable writer add Type 0 fonts before or after the macOS renderer
  exists?
- What validation tools are acceptable in GitHub Actions while preserving the
  repo's Swift-only source and tooling policy?
- What is the minimum Unicode support claim for the first public release?
