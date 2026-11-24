---
number: 66
title: "MarkdownPDF 1.0 oracle"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T10:56:50+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/66
synced: 2026-11-24T12:19:19+01:00 89be6f995ef9
neutralized: 1
---

## What

State, before any production work of the 1.0 series, the answer key of every correctness surface of the library. The surfaces, read from the code: (1) the PDF writer (objects, cross-reference table, streams, page tree, outlines, links, metadata); (2) the PDF reader (PDFDocumentReader: objects, structure, text, words); (3) TrueType and CFF font handling (parse, subset, embed, widths, ToUnicode); (4) text shaping (Arabic joining, Hebrew, bidirectional order, GSUB and GPOS, vertical text); (5) colour emoji (COLR and CPAL, sequences); (6) the Markdown parser and the block layout (lists, tables, quotes, keep-together, pagination); (7) drawn content (charts, Mermaid diagrams, tiles, source code highlighting); (8) tagged PDF (PDF/UA and PDF/A structure); (9) the index and the table of contents; (10) the math adapter to MathTypeset. For each surface write: the correctness question; the input domain; the authority (a closed form, a slow reference, a differential path, a live platform witness, an evidence ledger); the equivalence relation (exact by default, a derived or measured and named tolerance only); the failure report; the classification of every case (handled, failed, unsupported, intentionally divergent, ineligible, blocked, with no silent skip); the negative controls (a planted fault that must turn the check red); and the parity of any optimized path with the slow path. List which 1.0 items are blocked until their oracle exists.

## Why

Without an answer key, a passing test only says the code agrees with itself. The library already holds ledgers (the whole-set emoji report, the not-verified list); this issue makes every surface state its authority the same way.

## Oracle first

This issue is the oracle: one document with one section per surface and a test that fails when a surface has no section.

## Acceptance

A document names the surfaces above (and any the review adds) with every field listed, a test fails when a section is missing or empty, and the issues blocked on it say so in a comment.
