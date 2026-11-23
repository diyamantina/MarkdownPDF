---
number: 41
title: "Embed a single face from a .ttc/.otc font collection (blocks system CJK/Arabic/Hebrew fonts)"
state: closed
labels: []
assignees: []
created: 2026-07-09T10:35:41+02:00
updated: 2026-07-09T11:17:16+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/41
synced: 2026-07-09T11:17:16+02:00 f92bb1590b58
neutralized: 1
---

The engine only embeds a single-face TrueType/OpenType file. Passing a `.ttc`/`.otc` collection throws `unsupportedFontFormat(format: "TrueType/OpenType Collection", guidance: "Extract a single face from the .ttc collection and embed that face; whole-collection embedding is not supported.")`.

This is a practical blocker for non-Latin scripts: most system fonts that cover CJK, Arabic, Hebrew, and Thai on macOS ship as `.ttc` collections (PingFang, Hiragino, Songti, Geeza Pro, ...). A user who wants to render those scripts cannot simply point the renderer at a system font; they must first extract a single face with an external tool (fonttools, etc.).

## Proposed
Accept a `.ttc`/`.otc` collection plus an optional face index (default 0): read the TTC header (`ttcf`, numFonts, per-face table-directory offsets) and embed the selected face, reusing the existing single-face path. This unblocks embedding system CJK/Arabic/Hebrew fonts directly.

Severity: enhancement. Non-Latin coverage on base-14 is impossible by design (WinAnsi), so embedding is the only route, and today that route rejects the fonts users actually have.
