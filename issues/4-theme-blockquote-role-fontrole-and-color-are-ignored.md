---
number: 4
title: "Theme .blockQuote role: fontRole and color are ignored"
state: closed
labels: []
assignees: []
created: 2026-07-08T17:19:34+02:00
updated: 2026-07-08T18:46:03+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/4
synced: 2026-07-08T18:46:03+02:00 22feac10b409
neutralized: 1
---

The `.blockQuote` case in `MarkdownPDFRenderer.render(_:)` indents `margins.left` by 14 and renders nested blocks. It consults `style(for: .blockQuote)` only through `blockQuoteTopSpacing` and `blockQuoteBottomSpacing`, which read `spacingBeforeMultiplier` and `spacingAfterMultiplier`.

So of the `ElementStyle` surface exposed for the `.blockQuote` role, the spacing multipliers are live, and `fontRole`, `color`, `backgroundColor`, `borderColor`, and `underline` are inert: nested paragraphs render with the `.paragraph` style.

A caller setting `theme.elements[.blockQuote] = ElementStyle(fontRole: .italic, color: navy, borderColor: teal)` sees no visual change. Either honor the style (a left border rule and a body color are the obvious ones) or narrow the public surface so it cannot be set.
