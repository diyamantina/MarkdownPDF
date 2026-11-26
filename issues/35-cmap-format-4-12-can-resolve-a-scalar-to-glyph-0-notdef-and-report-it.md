---
number: 35
title: "cmap format 4/12 can resolve a scalar to glyph 0 (.notdef) and report it as covered"
state: closed
labels: []
assignees: []
created: 2026-07-09T02:21:13+02:00
updated: 2026-07-09T02:49:33+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/35
synced: 2026-07-09T02:49:33+02:00 63cd3a751c01
neutralized: 2
---

Found by the adversarial critic while verifying #33/#34; confirmed reproducible but pre-existing (the branch dates to commit b6920485, 2026-06-01), so it was split out rather than folded into #34.

## Problem
`Format4CMap.glyphID(for:)` (`Sources/MarkdownPDF/TrueTypeGlyphMapper.swift:257-258`) returns `(code + idDelta) mod 65536` on the `idRangeOffset == 0` branch **without checking for a resulting glyph index of 0**, unlike the glyph-array branch (line ~268) which rejects a raw glyph id of 0. In a TrueType cmap, glyph 0 **is** `.notdef` (the missing glyph), so a segment that resolves a scalar to glyph 0 should be treated as "unmapped", not "found".

Because the lookup returns "found (glyph 0)" instead of nil:
- `TrueTypeGlyphMapper.resolve` never reaches the `.reject`/`.useNotdef` policy, so `covers(_:font:)` reports the scalar as **covered** while it actually renders as `.notdef`.
- Under a conformance profile the `.reject` gate added in #34 never fires (the lookup said "found"), so `render` succeeds and ships a file that references `.notdef` in content. veraPDF 1.30 rejects it on ISO 14289-1 clauses **7.21.7** and **7.21.8**, i.e. a spec-violating document under a PDF/UA-1 conformance claim.

## Reproduction (confirmed)
Patched the `.latinWitness` synthetic font: segment 2 `idDelta` from -63 to -65 so 'A' maps to glyph 0, fixed the table checksum. Then:
- `TrueTypeGlyphMapper(.reject).map("A")` returns glyphID 0 without throwing; `covers("A") == true` yet 'A' draws notdef.
- `render(markdown: "A")` under `.pdfUA1` succeeds; veraPDF fails 7.21.7 + 7.21.8.

## Also (PLAUSIBLE, not built)
The glyph-array branch (line ~271) returns `(rawGlyphID + idDelta) mod 65536` after checking only `rawGlyphID != 0`; the post-`idDelta` sum can still be 0. `Format12CMap.glyphID(for:)` has the analogous question for a group whose arithmetic yields `startGlyphID == 0`.

## Fix
Treat a resolved glyph index of 0 as unmapped (return nil) on **both** format-4 branches after the `idDelta` addition, and check the analogous case in format 12. Then the existing `.reject`/`.useNotdef`/`covers()` machinery handles it correctly (refuse under conformance, notdef fallback otherwise, uncovered for math transliteration).

Severity: medium (requires a pathological but spec-representable cmap).
