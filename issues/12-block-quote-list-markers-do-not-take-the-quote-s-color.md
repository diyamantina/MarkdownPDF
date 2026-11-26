---
number: 12
title: "Block quote list markers do not take the quote's color"
state: closed
labels: []
assignees: []
created: 2026-07-08T18:41:48+02:00
updated: 2026-07-08T22:58:53+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/12
synced: 2026-07-08T22:58:53+02:00 100180228e82
neutralized: 2
---

Follow-up to #4.

Inside a themed block quote, list item *text* resolves through the quote's `.blockQuote` role (italic face, quote color), but the bullet keeps the `.listMarker` role's own color and font.

```swift
var theme = PDFOptions.Theme.default
var quote = theme.style(for: .blockQuote)
quote.fontRole = .italic
quote.color = PDFColor(red: 0.01, green: 0, blue: 0.27)
theme.elements[.blockQuote] = quote
// render "> - item"
```

Emitted: item text as `/F3` at `0.010 0 0.270 rg`; bullet as `/F1` at `0 0 0 rg`.

`style(for:)` overrides only `.paragraph` and `.list` while `blockQuoteDepth > 0`. Inline code inherits the quote color but keeps its monospaced face, which seems right. Whether the marker should follow the quote's color, keep the theme's marker color, or gain its own `.blockQuote` derived color is a design call.

Same question applies to `.tableCell` and `.tableHeader` inside quotes, which currently do not recolor.
