---
number: 49
title: "CFF (Type2) outline embedding (FontFile3 / CIDFontType0) for CJK/Arabic system fonts"
state: closed
labels: []
assignees: []
created: 2026-07-09T13:18:46+02:00
updated: 2026-07-09T16:23:31+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/49
synced: 2026-07-09T16:23:31+02:00 6506615c1b23
neutralized: 2
---

The embedder only supports TrueType (`glyf`) outlines. An OpenType-CFF font (`OTTO` sfnt, a `CFF ` table with Type2 charstrings) is rejected with `unsupportedFontFormat("OpenType CFF", "FontFile3 / CIDFontType0 ... staged but not implemented")`. This blocks the fonts users actually reach for on macOS: the system CJK and Arabic fonts are largely CFF (Hiragino Sans/Sans GB, PingFang, most Noto CJK `.otf`/`.ttc` builds). CJK and Hebrew otherwise render today (they need no shaping); the only remaining blocker for their common system fonts is CFF embedding.

## Scope
- Parse the `CFF ` table: Header, Name/Top/String/Global-Subr INDEXes, the Top DICT (CharStrings, Private, FDArray/FDSelect for CID-keyed CFF, charset, ROS), and the CharStrings INDEX (Type2 charstrings).
- Subset: keep the used glyphs' charstrings + the subrs they call (Type2 `callsubr`/`callgsubr` with the bias), rebuild the INDEXes and DICT offsets. CID-keyed CFF (FDArray/FDSelect) must be handled for CJK.
- Emit: `FontFile3` with `/Subtype /OpenType` (or `/Type1C`/`/CIDFontType0C`), wired into the existing CIDFontType0/Type2 machinery. Verify /ToUnicode, /W, and glyph ids.

## Oracle
Subset with `hb-subset` (installed) as the reference and diff structure; validate output with qpdf/mutool/pdftotext; render a CJK + Arabic sample from a real CFF font (Hiragino/PingFang) and confirm glyphs + extraction.

Severity: high for CJK/Arabic system-font support. Large (a Type2 charstring interpreter + CFF subsetter), so likely phased: non-CID `CFF ` first, then CID-keyed.
