---
number: 13
title: "A figure or table opening a block quote can still orphan the rule"
state: closed
labels: []
assignees: []
created: 2026-07-08T18:41:53+02:00
updated: 2026-07-08T22:50:47+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/13
synced: 2026-07-08T22:50:47+02:00 e4f9a36008dd
neutralized: 2
---

Follow-up to #4.

`blockQuoteLeadingHeight(of:)` reserves what the quote's first block needs before `topY` is captured, so a page break happens before the rule's origin is recorded. It handles `.heading` and `.codeBlock`, the two blocks whose own `ensureSpace` exceeds one line by a lot.

Not handled: a quote whose first block is a table, a Mermaid diagram, a native chart, or a standalone image. `renderMermaidBlock` reserves `plan.height + 12`, `renderStandaloneImage` reserves the scaled image height, and `renderTable` reserves per row. Any of these can still break the page after `topY` was captured, leaving a rule segment on a page that carries no quote content.

Repro shape (mirrors the heading case that is now fixed):

```markdown
Filler.        <- repeated until the page is nearly full

> ![figure](tall.png)
>
> quoted body
```

A general fix would capture the rule's origin lazily, at the first drawing operation performed while `blockQuoteDepth > 0`, rather than reserving per block kind. That needs a hook at the drawing choke points (`drawRuns`, `drawImage`, `drawMermaidPlan`), or a `didDrawInQuote` flag reset by `startNewPage`.
