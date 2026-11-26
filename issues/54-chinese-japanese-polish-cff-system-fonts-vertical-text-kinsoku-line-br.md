---
number: 54
title: "Chinese/Japanese polish: CFF system fonts, vertical text, kinsoku line-break audit"
state: open
labels: ["enhancement"]
assignees: []
created: 2026-07-09T14:30:50+02:00
updated: 2026-11-26T03:33:15+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/54
synced: 2026-11-26T03:33:15+01:00 4c122990a41c
neutralized: 2
---

Base Chinese/Japanese already render correctly today with a TrueType (`glyf`) CJK font: each Han character / kana maps to one glyph via cmap (no shaping), and the engine already does CJK line breaking (`LineBreakOpportunityDetector`: breaks between ideographs, Japanese non-starters). Verified: 漢字 日本語 中文 あいう renders and extracts. This issue tracks the remaining CJK refinements, to be done AFTER Hebrew.

## Remaining
1. **CFF system fonts** (#49, in progress): most macOS CJK fonts (Hiragino, PingFang) and many Noto CJK builds are CFF-outline. #49 unlocks embedding them. Until then, a `glyf` CJK font (Arial Unicode, Noto Sans CJK TTF) is required.
2. **Vertical text** (`vert`/`vrt2`, tate-gaki): not supported. Advanced, rare in Markdown-to-PDF; low priority.
3. **Ruby / furigana**: no Markdown syntax for it; out of scope unless a syntax is added.
4. **CJK line-break polish**: kinsoku shori (line-break prohibition for leading/trailing punctuation) is partially handled (closing-punctuation rule exists); audit against UAX #14 CJK classes for edge cases.
5. **Full-width vs proportional metrics / CJK punctuation spacing**: verify advances for full-width forms and CJK punctuation.
6. **Japanese kana small forms, iteration marks**: render as-is via cmap (single glyphs); no shaping needed.

## Verification
Render a CJK paragraph (mixed Han + kana + CJK punctuation) with a CFF and a glyf font once #49 lands; confirm glyphs, line breaks (no orphaned punctuation), and ToUnicode.

Mostly done; the substantive remaining item is CFF fonts (#49).

## Comments

### Mihaela, 2026-11-26T03:33:13+01:00

Decided for 1.0 by #76.
