---
number: 30
title: "WinAnsi advance widths wrong for AE, germandbls, fractions, ordinals (off-page)"
state: closed
labels: []
assignees: []
created: 2026-07-09T00:47:33+02:00
updated: 2026-07-09T01:05:44+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/30
synced: 2026-07-09T01:05:44+02:00 fec0509e4108
neutralized: 1
---

`StandardFont.WidthTable.width(for:)` returned the width of `?` (556 for Helvetica) for any WinAnsi scalar outside ASCII that was neither in the small hand-written `winAnsiPunctuation` table nor decomposable to an ASCII base. So Æ (true 1000), ß (611), ½/¼/¾ (834), ª (370), º (365), Ø (778), the superscripts, Þ, Ð, and the broken bar all measured at 556.

Consequences (confirmed by an adversarial audit):
- `pdfBase` (no /Widths emitted): the viewer paints the true metric while layout used 556, so a line of 60 Æ paints to x=604 on a 595pt page, past the 541 right margin.
- Embedded TrueType (subtype writes /Widths): the wrong 556 is written into /Widths, so viewers advance 556 under a wider glyph and overlap.

The hand table was also shared across faces, but Helvetica-Bold advances differ from regular at 31 code points.

Fix: generate complete per-face WinAnsi width tables from the Adobe Core-14 AFM metrics (via the WinAnsi encoding vector), so every advance is exact. Also corrects two ASCII values (quotesingle, grave) that carried the curly-quote width.

Found by the model-driven text-encoding audit; fixed against the AFM reference metrics.
