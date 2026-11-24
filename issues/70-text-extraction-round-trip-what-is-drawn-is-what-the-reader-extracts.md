---
number: 70
title: "Text extraction round trip: what is drawn is what the reader extracts"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:03:24+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/70
synced: 2026-11-24T12:19:19+01:00 aa6bb9ba1710
neutralized: 1
---

## What

For each script and for emoji, render a text, read it back with the library's reader and compare with the source text: Latin with accents, Greek, Cyrillic, Arabic (logical order), Hebrew, Devanagari if supported, CJK, vertical text, emoji sequences, ligatures, soft hyphens, combining marks. State the relation exactly (equal after the documented normalisation) and list each case as equal, intentionally different with the reason, or unsupported.

## Why

A document that cannot be searched or copied as it was written is defective for accessibility and for search.

## Oracle first

The reference is the source text, with a stated normalisation. Exact equality for the covered scripts, an explicit list of divergences otherwise.

## Acceptance

A table lists every script and emoji class with its result, a test enforces the table, and a planted wrong ToUnicode entry is caught.
