---
number: 2
title: "Unordered list items draw no marker"
state: closed
labels: []
assignees: []
created: 2026-07-08T17:19:16+02:00
updated: 2026-07-08T17:50:24+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/2
synced: 2026-07-08T17:50:24+02:00 0e933d9d97b5
neutralized: 1
---

`MarkdownPDFRenderer.renderList` draws a marker only when `start != nil` (ordered) or the item has a checkbox. Unordered items get the 24pt indent and no glyph, so every bullet list renders as bare indented lines.

`PDFOptions.ElementRole.listMarker` exists and `baseElements` styles it for all three built-in themes, so the role is advertised in the public theme surface but unreachable for the case it most obviously describes.

Repro:

```swift
let data = try MarkdownPDFRenderer().render(markdown: "- alpha\n- beta\n")
// no bullet glyph in the content stream
```

Complication: the marker glyph must be chosen per font. Base-14 can draw U+2022 (WinAnsi 0x95), but `PDFEmbeddedFontCatalog.covers` returns false there because no embedded entry exists. An embedded font may cover neither U+2022 nor a hyphen. And under PDF/UA-1 or PDF/A-2a a base-14 marker would make `validateConformance` fail the whole document.
