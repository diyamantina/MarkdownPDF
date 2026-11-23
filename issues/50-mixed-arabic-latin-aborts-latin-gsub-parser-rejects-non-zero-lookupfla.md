---
number: 50
title: "Mixed Arabic+Latin aborts: Latin GSUB parser rejects non-zero lookupFlag"
state: closed
labels: []
assignees: []
created: 2026-07-09T14:07:03+02:00
updated: 2026-07-09T14:17:14+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/50
synced: 2026-07-09T14:17:14+02:00 1fd39d236585
neutralized: 1
---

A line mixing Arabic (or another complex script) with Latin, using an embedded font whose `latn` GSUB uses a non-zero lookupFlag (e.g. Noto Naskh Arabic's IgnoreMarks), aborts the whole document with `unsupportedGSUBLookupFlag(8)`.

This is PRE-EXISTING (main and the #47 branch both fail identically): the Latin shaper `OpenTypeShaper`/`GSUBLigatureParser` throws on any non-zero `lookupFlag` (`guard lookupFlag == 0`). The new general `GSUBTable` (Arabic path) deliberately tolerates lookupFlag; the Latin parser should do the same. Repro: `"قال hello لي"` or `"رقم 123 كبير"` with Noto Naskh embedded.

## Fix
Make `OpenTypeShaper.GSUBLigatureParser` tolerant of the mark/ligature/base IGNORE lookup flags (they do not affect simple Latin `liga`/`rlig` ligation without GDEF), matching `GSUBTable`. Or route the Latin ligature path through the general `GSUBTable`. Then a mixed Arabic+Latin line renders (each run shaped by its script's path, ordered by bidi).

Verify: `"قال hello لي"` renders with joined Arabic + upright Latin, bidi-correct, no abort.
