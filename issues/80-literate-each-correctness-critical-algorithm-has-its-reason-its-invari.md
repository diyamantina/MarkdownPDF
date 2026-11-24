---
number: 80
title: "Literate: each correctness-critical algorithm has its reason, its invariant and a worked example in the DocC catalog"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:31:10+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/80
synced: 2026-11-24T12:19:19+01:00 8f6486e7f12e
neutralized: 1
---

## What

List the correctness-critical algorithms (cross-reference table writing, object numbering, font subsetting and width tables, ToUnicode maps, the bidirectional order, Arabic joining, the line breaker, table column sizing, pagination and keep-together, chart tick selection, the colour emoji sequence segmenter, the index collation). For each: the reason, the invariant, the measurement next to the code, and a worked example with concrete numbers in the DocC catalog that a test reproduces.

## Why

A reader must be able to understand and re-implement the algorithm from the documentation.

## Oracle first

The reference is the worked example, computed by hand, which the same test reproduces.

## Acceptance

A list of the algorithms is in the documentation, each has its three parts and a worked example that a test reproduces, and the DocC catalog builds without warnings.
