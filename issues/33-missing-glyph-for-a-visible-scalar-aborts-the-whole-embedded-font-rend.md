---
number: 33
title: "Missing glyph for a visible scalar aborts the whole embedded-font render (notdef fallback)"
state: closed
labels: []
assignees: []
created: 2026-07-09T01:16:36+02:00
updated: 2026-07-09T02:19:57+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/33
synced: 2026-07-09T02:19:57+02:00 6d1861454232
neutralized: 1
---

Split from #29 (shape 2). #29's shape 1 (strip invisible default-ignorable format controls) is handled in PR #32. This tracks the remaining, distinct concern.

## Problem
When an embedded font's cmap genuinely lacks a glyph for a **visible** scalar (an emoji U+1F600, a stray combining mark U+0301 with no base, a CJK glyph the subset omits), `TrueTypeGlyphMapper.map` under the default `.reject` policy throws `missingGlyph` and aborts the **whole document**. One unsupported character should not lose the entire render.

Unlike shape 1, these are not default-ignorable: they legitimately want a glyph. The correct behavior is a per-scalar `.notdef` (tofu) fallback for that one scalar, not a document abort.

## Why it is not a trivial policy flip
`PDFEmbeddedFontCatalog.covers(_:font:)` probes coverage with `(try? mapper.map(...)) != nil` and depends on `.reject` semantics to decide, per math symbol, between the Unicode glyph and an ASCII transliteration. Globally switching the catalog/shaper default to `.useNotdef` would make `covers()` always return true and regress math rendering. `OpenTypeShaper` also defaults to `.reject`.

## Proposed shape
- Give the render path (`mapping(for:)` / `shapedMapping(for:)`) a `.useNotdef` mapper/shaper (structs, so flip `missingGlyphPolicy` on a copy of the entry's mapper), while keeping `covers()` on a strict, policy-independent coverage probe (resolve each scalar; false if any would fall to notdef).
- Verify the notdef path is sound end to end: glyph 0 is included in the subset, `/Widths`/hmtx[0] advance is correct, the ToUnicode CMap maps the character code back to the original scalar, and the content stream emits pdfCharacterCode 0 correctly.
- Test: an emoji and a stray combining mark under the synthetic witness font render (tofu) instead of aborting; math `covers()` still distinguishes covered vs uncovered symbols.

## Also related (separate, smaller)
- The outline/bookmark `/Title` path WinAnsi-encodes non-ASCII (draws `?`) independently of page-text stripping, so neither #27 nor #32 reaches it. A file-leading BOM changes document structure because the parser never strips it. Fold into the title-encoding work.

## Comments

### Mihaela, 2026-07-09T01:35:13+02:00

Adversarial review of PR #32 surfaced two more items that belong here rather than in the invisible-control strip, because deleting them changes meaning:

- **Line/paragraph separators (U+2028/U+2029).** They are Zl/Zp word boundaries, not default-ignorable. PR #32 deliberately does not strip them (deleting fused the words they split). Under an embedded font whose cmap omits them they still abort with missingGlyph, and base-14 paints `?`. The faithful fix is to normalize them to a break (or a space) at the parser input boundary, so they become a real boundary instead of a stray run scalar.
- **Interlinear annotation controls (U+FFF9..U+FFFB).** Ruby delimiters; deleting a separator merges annotation into base text. Same normalization-not-deletion treatment.

Both are the same shape as the emoji/notdef case: a scalar the font lacks should degrade gracefully (notdef or normalized break), never abort the document.
