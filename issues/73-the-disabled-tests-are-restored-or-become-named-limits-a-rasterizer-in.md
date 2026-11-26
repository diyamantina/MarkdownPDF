---
number: 73
title: "The disabled tests are restored or become named limits: a rasterizer inside the library"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:09:29+01:00
updated: 2026-11-24T13:30:03+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/73
synced: 2026-11-24T13:30:03+01:00 6b6ba8a90523
neutralized: 2
---

## What

Fourteen tests carry a disabled trait because they need to turn a page into pixels (counted today: 14 disabled tests in 12 files, all named in Docs/NOT-VERIFIED.md). Decide for the 1.0: either build a rasterizer inside the package (path fills and strokes, images with soft masks, glyph outlines from the embedded TrueType and CFF programs, with the comparisons restated as a comparison of the raster with the geometry the reader reports) and enable the tests, or keep each test as a named limit with a reason and a place in the documentation. Nothing stays as an unnamed gap.

## Why

A number such as fourteen disabled tests with no names is a hidden debt. A named limit is something a reader can judge.

## Oracle first

The reference is the list produced by searching the tests for the disabled trait, compared with the rows of Docs/NOT-VERIFIED.md. Planted faults: a disabled test with no row; a row whose reason is empty.

## Acceptance

Each of the fourteen is enabled or is a named limit, a check fails when a disabled test has no row, and the README status text links the section.

## Comments

### Mihaela, 2026-11-24T13:30:03+01:00

Correction after reading the code on 2026-11-24. The count splits: of the 14 disabled tests, 9 need a rasterizer and 5 need a PDF/A and PDF/UA validator (one suite, CoverPageTests, is in both groups). This issue owns the 9 and issue 74 owns the 5; read fourteen as nine here. Docs/NOT-VERIFIED.md names all 14 and the README links that file (not a section).
