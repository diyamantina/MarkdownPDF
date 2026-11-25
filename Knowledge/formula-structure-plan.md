# Formulas in the structure tree: what is there, what the standards ask, and the plan (issue 90, part 2)

Status: a plan, nothing implemented. Read against host main a23c0eab (contains 07e82d9f). Marks: MEASURED (read in a run), READ (the file and line were read and checked), DOCUMENTED (a document says it), UNVERIFIED, PROPOSAL (a design, UNVERIFIED until a test holds it).

## What the code does today (READ, checked at the lines)

- `MarkdownPDFRenderer.swift` 4226: the inline math is parsed and only `parsed.root` is used; the linearized text of the whole formula (`parsed.linearizedText`) is discarded. 4257 to 4375: the node kinds `.fraction`, `.radical`, `.space` become a box run; `.text`, `.symbol`, `.accent`, `.matrix`, `.scaledDelimiter` and `.scripts` become ordinary text runs (scripts at 0.68 size with a baseline shift).
- `PDFTextRun.swift` 4 to 27 (field list): a run carries text, font, size, colour, underline, strikethrough, link, baseline offset, destinations, index term and `inlineMathBox`. It carries no identifier of the formula it belongs to.
- 4823 to 4836: a box run opens a `Formula` element with the formula's spoken text as Alt, draws the box inside actual-text marked content, and closes the element. `PDFTaggedContentBuilder.swift` has one place that attaches drawn content to an element (`markCurrentElement`, called once, at `MarkdownPDFRenderer.swift` 4754, for the paragraph); so the box `Formula` owns no content of its own: its ink is inside the paragraph's marked content and the element is an empty child of the paragraph.
- `PDFTaggedContentBuilder.swift` 36 to 38: `endElement` does nothing unless the element is on top of the stack, so an element left open makes the paragraph's own close a no-op.
- `PDFDocumentReader.swift` 160 to 167: the reader exposes a structure element's type, Alt, the count of its marked contents and its children; not its ActualText, page, marked-content identifier or text.

So three things are true that the issue text did not say: (1) the formula drawn as text has no element at all; (2) a mixed formula such as `x + \frac{a}{b}` is split: loose text and one `Formula` for the fraction; (3) even the box `Formula` does not hold the content it names, it is an empty element with an Alt.

## What the free sources say about it

- DOCUMENTED (the Matterhorn Protocol 1.02, page 8, read and checked): a mathematical expression not tagged Formula is failure 17-001 (clause 7.7-1, a human judges it); a Formula without an Alt is 17-002 (7.7-1, machine); Unicode mapping is 17-003 (7.7-2).
- DOCUMENTED (the veraPDF PDF/UA-1 profile, read as a text file, rule 7.7-1 at lines 847 to 858, read and checked; the validator was not run): the rule tests only a Formula that already exists: Alt not empty, or ActualText present. Nothing in the profile looks for math with no Formula around it. This differs from the Matterhorn wording (Alt) and from the syntax guide (Alt required): a checker accepts ActualText instead of Alt. A Formula with both satisfies every reading.
- DOCUMENTED (the PDF Association syntax guide, section 4.3.2, read by a reader): a Formula covers an inline or a display formula; ActualText is preferred only on very small pieces.
- UNVERIFIED: the wording of ISO 14289-1 clause 7.7 itself, and how it reconciles a Formula with text inside a text object (ISO 32000-1, 14.8.4.5, says illustration content is not between the text-object operators). No validator is run in this repository's work: the capability would have to be added to MarkdownPDF first, with tests. Until then the claim is "the structure tree has the shape the sources describe", never "conforms".

## What the books say that applies (DOCUMENTED, with sections)

- Dragon 6.7 (pp. 410 to 415, makelist and backpatch checked in the text): when the target is not yet known during one pass, leave it open on a list and fill it when it is known. PROPOSAL: open the formula at its first run, collect each emitted range, fill the one element's extent when the last run is written.
- EaC 5.1 (p. 221 to 226, checked): after translation starts the intermediate form is definitive, and facts recorded about it must be tied to exact points in it. PROPOSAL: the structure tree is that record, tied to content ranges at emission time.
- EaC Appendix B.1 (checked): a validation pass that walks the representation and fails on a malformed one. PROPOSAL: a pass that walks the document tree and the emitted structure tree together.
- The books do not cover testing a generator's output against its input; the oracle below is our own.

## The oracle (PROPOSAL)

Answer key: the linearized text of the whole formula (`MathParser().parse(source).linearizedText`), the same text the display formula already uses as Alt. Invariant: for every inline formula node, the structure tree has exactly one `Formula` element in its paragraph, its Alt equals the answer key, it owns the marked content of all the runs the formula drew, and the paragraph keeps the text around it. The choice between text runs and boxes does not change it.

## The slice, in order (PROPOSAL)

1. Reader first, with tests: expose the page and marked-content identifier of each element's content and the text under it (and ActualText), so a test can assert which glyphs belong to which element. Today it cannot.
2. Red tests (each red today; planted faults must turn the green ones red):
   - `textOnlyInlineFormulaIsOneFormula`: `Before $x^2 + y^2$ after.`: the paragraph has one `Formula` whose Alt is the whole spoken form; the paragraph's own text still holds Before and after.
   - `mixedFormulaIsOneFormulaNotNested`: `$x = \frac{a}{b}$`: one `Formula`, Alt equal to the whole form (today: the fraction's Alt only), no `Formula` inside a `Formula`.
   - `formulaHoldsItsContent`: `$\frac{a}{b}$` and the text formula: the `Formula` has at least one marked content, and the paragraph's marks do not hold the formula's glyphs.
   - `formulaAcrossLinesIsOneFormula`: a long formula wrapped over two lines: one `Formula` with a mark on each line.
   - Negative controls: an unparsable inline source makes no `Formula`; a paragraph without math makes none; a display formula is unchanged.
3. The change: add to the text run the identifier of the formula and its whole alternative text (set where the math is parsed, copied wherever a run is rebuilt: the script runs and the retokenizing copy); open the element at the first run of a formula and close it after the last, closing and reopening the paragraph's marked content around it (a mark is refused inside an open sequence); keep the open element in renderer state across lines and pages; drop the Alt and the nested element from an inner box run. A link around a formula: the link annotation is made only for text runs today, so a link around a box gets none: a separate, named gap.
4. The gate: the 210-file corpus. Untagged output must be byte-identical; tagged output changes only for inline math, and the changed files are listed and read with the reader (a byte comparison says that they differ, not what differs).

## Hazards found by reading

- A formula wrapped across lines or a page: the element id must live in renderer state across `drawRuns` calls.
- The bidirectional drawing path returns before the box branch (`MarkdownPDFRenderer.swift` 4811 to 4815): unread, UNVERIFIED how a formula behaves there.
- Which other tests render inline math with tagging on, and whether the corpus is tagged: UNVERIFIED, to be read before the change.
- `PDFTaggedContentTests.swift` 106 counts marked contents per element: it may change.

## Decisions for the owner (a design choice, not a fact)

- Whether nested box formulas are merged into the outer one (this plan) or kept.
- Whether a formula drawn as text gets an Alt only, ActualText only, or both (this plan: both, as the box formula has today, since a checker accepts either and a guide asks for Alt).
- Whether the PDF 2.0 route (MathML as an associated file) is a later slice (the free sources say PDF/UA-1 does not recommend itself for math and PDF/UA-2 requires MathML).
