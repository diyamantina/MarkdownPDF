---
number: 53
title: "Hebrew polish: niqqud/cantillation positioning (GPOS) and presentation ligatures"
state: open
labels: []
assignees: []
created: 2026-07-09T14:30:49+02:00
updated: 2026-07-10T02:35:30+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/53
synced: 2026-07-10T02:35:30+02:00 6559b6f1a488
neutralized: 1
---

Base Hebrew already renders correctly today (non-joining letters via cmap + the existing bidi RTL ordering + an embedded font; verified end to end). This issue tracks the remaining Hebrew refinements, to be done AFTER CFF (#49).

## Remaining
1. **Niqqud / vowel points** (U+05B0–05BD, U+05BF, U+05C1–05C2, U+05C7) and **dagesh/rafe/meteg**: base letters render, but the points sit at nominal positions without GPOS mark-to-base placement. Needs GPOS `mark`/`mkmk`, shared with Arabic harakat, tracked in #48. When #48 lands, add a Hebrew niqqud render-witness (vs hb-shape positions).
2. **Cantillation marks** (te'amim, U+0591–05AF): same GPOS positioning need; rarer (liturgical).
3. **Presentation-form ligatures** (e.g. alef-lamed U+FB4F) and Hebrew-specific `ccmp`: apply via the general `GSUBTable` if a font ships them.
4. **Final forms** (kaf/mem/nun/pe/tsadi sofit) are separate Unicode code points, so they already render without shaping, no work needed.

## Verification
Render pointed Hebrew (e.g. שָׁלוֹם) with an embedded font that has niqqud + GPOS anchors; confirm the points land on the correct base letters (raster + hb-shape position diff), and ToUnicode recovers the base + points.

Depends on #48 (GPOS) for the positioning; otherwise Hebrew is complete.
