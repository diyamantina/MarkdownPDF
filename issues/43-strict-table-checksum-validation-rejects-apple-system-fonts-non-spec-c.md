---
number: 43
title: "Strict table-checksum validation rejects Apple system fonts (non-spec checksums)"
state: closed
labels: []
assignees: []
created: 2026-07-09T10:52:45+02:00
updated: 2026-07-09T11:32:32+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/43
synced: 2026-07-09T11:32:32+02:00 cff1884eb231
neutralized: 2
---

Found while implementing #41 (TTC support). The parser validates every table's checksum and throws `invalidTableChecksum` on any mismatch. Real Apple system fonts routinely have non-spec table checksums, so they are rejected even though they are structurally valid and render fine.

Confirmed:
- `Apple Symbols.ttf` (single face) → `invalidTableChecksum(tag: "head", ...)`.
- `Songti.ttc` (glyf outlines) → `invalidTableChecksum(tag: "head", ...)`.
- Non-Apple fonts (Arial Unicode, Liberation, DejaVu) validate and embed fine.

The `head` `checkSumAdjustment` is already zeroed before hashing, so the code is spec-correct; the fonts themselves carry wrong checksums. This blocks embedding Apple system fonts (the ones a macOS user reaches for), and it is orthogonal to TTC (it hits single-face `.ttf` too).

## Context
The engine subsets and rebuilds the font, so the original table checksums are not needed for correct output. Structural validation (`invalidTableBounds`, per-table parsers) still catches genuinely corrupt fonts. Reference engines treat checksum validation as optional (reportlab gates it behind a `validate` flag, off by default).

## Proposed
Make a table-checksum mismatch non-fatal for the embedding path (skip, or downgrade to a diagnostic), keeping the structural/bounds guards. Optionally keep strict validation available behind a flag for callers who want it. This unblocks Apple system fonts (glyf ones) without weakening corruption detection that actually matters.

Severity: medium, blocks a common real-world embedding case.
