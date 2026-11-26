---
number: 7
title: "Figures do not separate themselves from the next block"
state: closed
labels: []
assignees: []
created: 2026-07-08T17:48:55+02:00
updated: 2026-07-08T18:10:11+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/7
synced: 2026-07-08T18:10:11+02:00 993d4a4c9c4c
neutralized: 2
---

`renderMermaidBlock` and `renderChart` both advance `y` by `plan.height + 12`. That 12pt is the figure's own padding inside its frame; a following paragraph's ascender consumes most of it, so the next line of text sits on the frame.

Measured with default options, `- alpha` style probe:

```
mermaid frame bottom y=718.25, next baseline y=706.25  -> gap 12pt
chart   frame bottom y=508.25, next baseline y=496.25  -> gap 12pt
```

At 11pt the ascender is ~8pt, leaving ~4pt of visible clearance. Every other block separates itself with `paragraphSpacing`. Figures should too, and the value should scale with the theme rather than being a hard 12.
