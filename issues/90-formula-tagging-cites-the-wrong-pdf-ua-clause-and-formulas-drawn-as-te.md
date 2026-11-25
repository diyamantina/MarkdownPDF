---
number: 90
title: "Formula tagging cites the wrong PDF/UA clause, and formulas drawn as text have no Formula element with an Alt"
state: open
labels: ["bug"]
assignees: []
created: 2026-11-25T11:58:38+01:00
updated: 2026-11-25T11:58:40+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/90
synced: 2026-11-25T11:58:40+01:00 9c6072aefb54
neutralized: 2
---

Status as of 2026-11-25. Host main read: 19b9b01cde6bda83920af0b702e002ac0ffd1f9f.

## Part 1: the wrong clause is cited

The source comments, two test headers and the changelog say that a formula carries a Formula element with spoken alternative text because of "PDF/UA-1, 7.9" (with WCAG 2.2, 1.1.1).

The Matterhorn Protocol 1.02 (the PDF Association's failure-condition list for PDF/UA-1), page 8, puts mathematical expressions under Checkpoint 17:

- 17-001: content is a mathematical expression but is not tagged with a Formula tag (clause 7.7-1, judged by a human).
- 17-002: a Formula tag is missing an Alt attribute (clause 7.7-1, checked by machine).
- 17-003: Unicode mapping requirements are not met (clause 7.7-2, checked by machine).

In the same table clause 7.9 is Notes and References (checkpoint 19). The citation should read clause 7.7, with the checkpoint numbers 17-001 to 17-003.

Where to change (read at the host main above; the line numbers are approximate and must be re-read):

- Sources/MarkdownPDF/MarkdownPDFRenderer.swift near lines 1875 and 4824 (comments).
- Tests/MarkdownPDFTests/PDFFormulaAlternativeTests.swift and PDFInlineFormulaAlternativeTests.swift (the header comment of each).
- CHANGELOG.md (the entry that cites the clause).
- Other files that match the text 7.9 (a search of Tests/ found three more files, unrelated to formulas in the names: MermaidBackEdgeRenderTests, TileApprovedGeometryTests and a mermaid golden fixture: check whether they cite the clause or only contain the digits).

Acceptance: a search of the repository for "PDF/UA-1, 7.9" prints nothing, and the new text names clause 7.7 and the three checkpoints. A docs and comment change only; no behaviour changes.

Basis: DOCUMENTED (the free archived copy of the Matterhorn Protocol 1.02, page 8, read; also the PDF Association's Tagged PDF syntax guide, section 4.3.2, which cites PDF/UA-1 clause 7.7 for the Alt requirement). The text of ISO 14289-1 clause 7.7 itself was not read: UNVERIFIED.

## Part 2: formulas drawn as text have no Formula element and no Alt

Today (read at the host main above):

- A display formula becomes a Formula element with an Alt (MarkdownPDFRenderer.swift near lines 1882 to 1905; test PDFFormulaAlternativeTests).
- An inline formula that becomes a box (a fraction, a root, a space) becomes a Formula child of its paragraph with Alt and ActualText (near lines 4291 to 4300 and 4822 to 4832; test PDFInlineFormulaAlternativeTests).
- An inline formula that is drawn as text (text, symbols, accents, matrices, scaled delimiters, scripts) is drawn by the ordinary text path with no structure element: it is plain content of the enclosing paragraph (near lines 4268 to 4290, 4310 to 4373 and 4836 to 4842). The test inlineMatrixIsText asserts only that the document text contains the spoken form; it asserts nothing about the structure tree.
- A mixed formula such as x + \frac{a}{b} is split: loose text plus a Formula for the fraction only. Superscripts are drawn raised but extract as adjacent characters (x^2 extracts as x2).

What the free sources say (secondary to the standard):

- Matterhorn 17-001: content that is a mathematical expression and is not tagged Formula is a failure; it is judged by a human. 17-002: every Formula needs an Alt; a machine checks it. 17-003: glyphs need a Unicode mapping.
- The PDF Association's Tagged PDF syntax guide (2019, section 4.3.2): a Formula covers an inline or a display formula; ActualText is preferred only on very small pieces such as ligatures.
- ISO 32000-1: an illustration element (Formula is one) should have an Alt or an ActualText or both; illustration content is to be complete graphics objects and not lie between the text-object operators.
- The PDF Association's Math in PDF guide (2026): PDF/UA-1 is not recommended for math because it has no provisions for tagging mathematical content; it supports only alternative text.

Open question, UNVERIFIED: how ISO 14289-1 clause 7.7 reconciles a Formula element with text drawn inside a text object (the syntax guide shows a Formula holding text; ISO 32000-1 says illustration content does not lie between BT and ET). The standard's own text was not read.

Proposed slice, oracle first (nothing implemented):

1. Fetch and read ISO 14289-1 clause 7.7 (the online preview was refused; find a free draft or the standard) and record it as DOCUMENTED in Knowledge/.
2. Extend the library's own reader (PDFDocumentReader) to expose ActualText and per-element text; it exposes /Alt only today.
3. Write the red test: for "Before $x^2 + y^2$ after." and for "$x + \frac{a}{b}$" the paragraph has exactly one Formula descendant, its Alt equals the whole formula's linearized text (the MathParser linearizedText is the answer key), there is still exactly one paragraph, and the text "Before" and "after." is still in the document text. Negative controls: an unparsable inline source makes no Formula; a plain paragraph makes none.
4. Decide, from the read standard and not by assumption, whether nested box Formulas are kept or merged into one outer Formula.
5. Then change the renderer so the test is green; plant a fault that turns it red.

Not verified in this issue: nothing was built or run; the line numbers; the behaviour with a real screen reader (the LaTeX project's tests, free to read, found NVDA with a math speech engine reads MathML in Foxit and Acrobat; VoiceOver was not tested by anyone found).
