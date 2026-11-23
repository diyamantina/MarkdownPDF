---
number: 47
title: "Wire Arabic shaping into the render path (routing, RTL ordering, ToUnicode)"
state: closed
labels: []
assignees: []
created: 2026-07-09T12:50:34+02:00
updated: 2026-07-09T14:11:37+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/47
synced: 2026-07-09T14:11:37+02:00 bb6c05c39b70
neutralized: 1
---

Follow-up to #46 (Arabic shaping core, merged). The joining + GSUB positional shaping now exists and is oracle-verified, but it is NOT wired into the render path, so Arabic still draws unshaped in actual PDFs. This issue is that integration.

## Scope
- Route runs that `ArabicShaper.containsJoiningScript` detects through `ArabicShaper.shape` instead of the plain cmap path (embedded-font path only; base-14 cannot draw Arabic).
- RTL visual ordering via `BidiParagraphOrdering` (bidi algorithm; PureTextResearch BIBLIOGRAPHY §5c). Shape in logical order, then order runs visually.
- Emit `/ToUnicode` from each shaped glyph's `sourceScalarRange` (already carried by `ArabicShaper.ShapedGlyph`), so extraction recovers the original base characters even though glyphs are positional forms/ligatures.
- Advances from the shaped glyphs' hmtx.

## Two hazards the adversarial review flagged specifically for this phase
1. **Do NOT strip default-ignorable format controls before Arabic shaping.** ZWJ (U+200D) and ZWNJ (U+200C) carry joining semantics (force/break a join); the Latin-path strip (#29) must not run ahead of the shaper for Arabic runs. Relatedly, the count-mismatch fallback in `ArabicShaper.shape` (the `guard baseGlyphs.count == scalars.count` branch) silently returns base glyphs with NO positional shaping, if anything upstream changes the scalar/glyph count (e.g. a pre-strip), all shaping is silently disabled. Make that path robust or assert.
2. **Shape before subsetting.** `numGlyphs` used by the shaper's out-of-range guards is the full font's count; the shaper must run on the un-subset font, before the subsetter renumbers glyphs.

## Verification
Extend the hb-shape differential test to a full `render()` witness: extract text (pdftotext/mutool) and confirm the drawn glyph run for an Arabic paragraph matches the shaped order, RTL-correct, with recoverable ToUnicode.
