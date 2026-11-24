---
number: 76
title: "Complex scripts at 1.0: Arabic tiers, Hebrew polish, Chinese and Japanese polish, each shipped or a named limit"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:29:05+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/76
synced: 2026-11-24T12:19:19+01:00 1b133307424a
neutralized: 1
---

## What

Three open issues (48 Arabic GSUB contextual lookups and GPOS mark positioning, 53 Hebrew niqqud and cantillation positioning, 54 Chinese and Japanese system fonts, vertical text and line-break rules) are not closed. For 1.0 decide for each: finish it with its answer key (a shaping reference with known outputs per script), or write it as a named limit with an example of what is wrong today. Also state what is promised for Indic scripts.

## Why

A document in these scripts either looks right or the reader was told it may not.

## Oracle first

The reference per script is a published shaping behaviour with example strings and their expected glyph sequences. Every example is classified correct, divergent with the reason, or unsupported.

## Acceptance

Each of the three issues is closed or becomes a named limit in the documentation, and a table lists the examples with their result.
