---
number: 69
title: "Every written file is verified by the library's own reader"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T10:58:22+01:00
updated: 2026-11-24T13:28:41+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/69
synced: 2026-11-24T13:28:41+01:00 75a823e0ae5d
neutralized: 2
---

## What

For every PDF the test suite writes, check with the library's reader: every cross-reference offset is exact, every object is reachable, no reference dangles, every stream ends where its length says, each font is subset and its widths equal the font's own, the page tree counts its pages and each child names its parent. Run it over the whole corpus of test documents, not only a few, and add the negative cases (one fault at a time) that the check must catch.

## Why

A writer is correct only against a reader that does not share its code. The byte inspectors of the test target already share nothing with the reader; this item makes the check total.

## Oracle first

The reference is the independent byte inspection of the test target compared with the reader's findings. They must agree on every file of the corpus.

## Acceptance

One check walks every test document, the two readers agree on all of them, and planted faults (an offset off by one, a dangling reference, a wrong width) are each caught.

## Comments

### Mihaela, 2026-11-24T13:28:41+01:00

Correction after reading the code on 2026-11-24. One of the three byte inspectors of the test target (PDFImageObjects) imports the library and calls its deflate coder, so it does not share nothing with the writer; the check must say which inspectors are independent. The reader exposes only a font name and whether it is embedded, not widths, so a check that a width equals the font's own needs the reader (or the inspector) to expose widths first.
