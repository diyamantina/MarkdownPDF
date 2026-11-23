---
number: 5
title: "No way to force a page break from Markdown"
state: closed
labels: []
assignees: []
created: 2026-07-08T17:24:06+02:00
updated: 2026-07-08T17:50:39+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/5
synced: 2026-07-08T17:50:39+02:00 731c0e0797ec
neutralized: 1
---

The engine can size a page (`PDFOptions.PageSize`) but never starts one on demand. `startNewPage()` is called only when content overflows. A document therefore cannot control its own pagination.

This blocks any slide-deck or one-section-per-page output: there is no markup that means "start the next page here".

CommonMark has no page-break construct, so the directive has to be chosen. An HTML comment (`<!-- pagebreak -->`) is invisible in every other Markdown renderer, which keeps the source portable. It has to be matched before `parseHTMLBlock`, which currently swallows comments and draws them as visible text.

A page break is a separator, not content, so it must never manufacture a blank page: trailing breaks, leading breaks, and consecutive breaks all need to collapse.
