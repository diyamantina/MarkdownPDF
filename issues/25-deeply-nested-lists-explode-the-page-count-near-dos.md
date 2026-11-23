---
number: 25
title: "Deeply nested lists explode the page count (near-DoS)"
state: closed
labels: []
assignees: []
created: 2026-07-08T23:57:01+02:00
updated: 2026-07-09T00:32:54+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/25
synced: 2026-07-09T00:32:54+02:00 ef1437662916
neutralized: 1
---

`renderList` adds 24pt of indent per nesting level with no clamp (`MarkdownPDFRenderer.swift:823`). Past the page width, `contentWidth` goes negative; `wrappedLines` with a non-positive width emits one token per line, each triggering a page break.

Measured (A4 default): 100-deep list → 81 pages, 200-deep → 488 pages, 400-deep → 2330 pages / 17 MB. Super-linear from a few KB of markdown. Same input on a 20000pt-wide page is 1-2 pages, proving geometry drives it.

The parser caps nesting at 32, but `54 + 32*24 = 822 > 595` already overflows an A4 page, so the cap does not prevent it.

Fix: clamp cumulative list indent so a minimum content column always remains.
