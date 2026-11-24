---
number: 69
title: "Every written file is verified by the library's own reader"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T10:58:22+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/69
synced: 2026-11-24T12:19:19+01:00 1ffd1d36ec53
neutralized: 1
---

## What

For every PDF the test suite writes, check with the library's reader: every cross-reference offset is exact, every object is reachable, no reference dangles, every stream ends where its length says, each font is subset and its widths equal the font's own, the page tree counts its pages and each child names its parent. Run it over the whole corpus of test documents, not only a few, and add the negative cases (one fault at a time) that the check must catch.

## Why

A writer is correct only against a reader that does not share its code. The byte inspectors of the test target already share nothing with the reader; this item makes the check total.

## Oracle first

The reference is the independent byte inspection of the test target compared with the reader's findings. They must agree on every file of the corpus.

## Acceptance

One check walks every test document, the two readers agree on all of them, and planted faults (an offset off by one, a dangling reference, a wrong width) are each caught.
