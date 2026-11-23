---
number: 10
title: "Theme .blockQuote backgroundColor is still ignored"
state: closed
labels: []
assignees: []
created: 2026-07-08T18:16:24+02:00
updated: 2026-07-08T23:03:39+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/10
synced: 2026-07-08T23:03:39+02:00 3fff678be97f
neutralized: 1
---

Follow-up to #4, which made `fontRole`, `color`, and `borderColor` effective for block quotes.

`backgroundColor` remains ignored. Unlike the left rule, a fill has to be painted **under** text that is already on the page, and a quote's height is not known until its nested blocks have rendered. The left rule sidesteps this because it sits in the 14pt gutter and can be stroked afterwards without covering anything.

`renderCodeBlockFragment` can fill a background because it computes its own height up front (`lines.count * lineHeight + padding * 2`). A block quote holds arbitrary blocks, including nested quotes, lists, and figures, so no such closed form exists.

Two ways out:

1. Give `PDFContentStream` an operator-prepend (or an insert-after-page-background) API, render the quote, then insert the fill rectangles for each page segment beneath the content already emitted.
2. Dry-run the quote on a copy of the layout (`Layout` is a struct, `PDFPageCanvas` is a class, so a copy would need care) to measure per-page extents, then draw the fill and render for real.

Until then, callers setting `theme.elements[.blockQuote]?.backgroundColor` see no effect. The doc comment on `drawBlockQuoteRule` records this.
