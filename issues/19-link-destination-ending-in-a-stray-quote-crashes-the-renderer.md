---
number: 19
title: "Link destination ending in a stray quote crashes the renderer"
state: closed
labels: []
assignees: []
created: 2026-07-08T23:22:01+02:00
updated: 2026-07-08T23:41:36+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/19
synced: 2026-07-08T23:41:36+02:00 ffefd40d151b
neutralized: 1
---

`InlineParser.parseDestination` (InlineParser.swift:255) crashes the whole render on a six-character input:

```swift
try MarkdownPDFRenderer().render(markdown: "[a](\")")
// Swift/Range.swift:761: Fatal error: Range requires lowerBound <= upperBound
```

Also reproduces with `[site](https://example.com\")` and `![alt](url\")`, i.e. any link or image whose destination's only `"` is its trailing character, which a stray quote in a pasted URL easily produces.

When the first `"` is the last character, `titleStart = index(after: quote) = endIndex` and `titleEnd = index(before: endIndex) = quote`, so `raw[titleStart ..< titleEnd]` is a reversed range.

A title should be taken only when there is an opening quote strictly before the closing quote at the end. Otherwise the trailing quote is part of the destination.

Found by an adversarial fuzz of the inline parser.
