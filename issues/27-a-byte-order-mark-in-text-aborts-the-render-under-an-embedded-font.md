---
number: 27
title: "A byte-order mark in text aborts the render under an embedded font"
state: closed
labels: []
assignees: []
created: 2026-07-09T00:07:09+02:00
updated: 2026-07-09T01:16:36+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/27
synced: 2026-07-09T01:16:36+02:00 4f96c275db1c
neutralized: 1
---

`"AB\u{FEFF}CD"` rendered with `PDFOptions.embeddedFonts` throws `unsupportedComplexScriptScalar(scalar: "\u{FEFF}")` and aborts the whole render.

`PDFEmbeddedFontCatalog.requiresExplicitShapingSupport` rejects the range `0xFE70...0xFEFF` as "Arabic presentation forms", but U+FEFF is the byte-order mark / zero-width no-break space, not a letter (Arabic Presentation Forms-B is U+FE70..U+FEFE). A BOM pasted mid-document reaches text runs and kills the render.

The base-14 path draws it as a visible `?` instead.

Fix: strip U+FEFF (invisible formatting) before it reaches either path, and correct the mislabeled range.

Found by an adversarial text-encoding audit.
