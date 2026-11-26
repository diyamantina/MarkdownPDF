---
number: 75
title: "Emoji and symbols the face cannot draw: named, with the reason and what the PDF shows instead"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:10:31+01:00
updated: 2026-11-24T13:31:26+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/75
synced: 2026-11-24T13:31:26+01:00 dd9bdf030498
neutralized: 2
---

## What

The whole-set report (Tests/MarkdownPDFTests/Unicode/whole-set-report.txt, Unicode 18.0) measures 7210 entries: 6708 drawn, 502 reported, 0 wrong. The reported set is 9 single emoji, 10 modifier sequences and 5 skin tone components of Unicode 18.0, plus the symbol blocks Miscellaneous Technical (96), Miscellaneous Symbols (44), Dingbats (3), Supplemental Arrows-B (120) and Miscellaneous Symbols and Arrows (215). Name each set by code point range, give the reason (no glyph in any bundled face), and state what the PDF shows in its place (the report line, a placeholder). Decide per block: add a face that covers it, or keep it as a named limit. Re-measure when the face or the Unicode version changes.

## Why

The 1.0 claim must say exactly which characters are not drawn.

## Oracle first

The reference is the Unicode data files (emoji-test and the assigned code points of the blocks) compared with the faces' own cmap and COLR tables, read by the library's own parser. Exact equality of the drawn and reported sets with the report.

## Acceptance

One section lists every undrawn set with the reason and the substitute, the report regenerates byte for byte, and a check fails when a code point is reported but not in the section.

## Comments

### Mihaela, 2026-11-24T13:31:26+01:00

Correction after reading the code on 2026-11-24. The reason for the 5 skin tone components is not proved to be no glyph in any face: the CHANGELOG records that the same reason was once applied to them wrongly. Give each set its own measured reason. Name the existing report reasons and the omitUndrawableEmoji option, and what is drawn instead (a stand-in letter under the base fonts, the missing-glyph box under an embedded face). The report regenerates only in the whole-set test's write mode.
