---
number: 84
title: "The not-verified list shrinks to named limits"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:42:16+01:00
updated: 2026-11-24T13:34:50+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/84
synced: 2026-11-24T13:34:50+01:00 befe94552908
neutralized: 1
---

## What

Docs/NOT-VERIFIED.md is the list. At 1.0 every remaining item has a name, a reason and a place in the documentation, and nothing is left as an unnamed gap. The two big groups are the pixel checks and the conformance checks (the two items above); this issue also covers every other skipped or conditional test and every documented assumption, and links the list from the README status text.

## Why

The 1.0 claim must say exactly what is not covered.

## Oracle first

The reference is the list of every disabled, skipped or conditional test and every assumption in the documentation.

## Acceptance

One section lists every remaining limit with a name and a reason, and a check fails when a disabled test or an assumption is missing from it.

## Comments

### Mihaela, 2026-11-24T13:34:50+01:00

Correction after reading the code on 2026-11-24. Read the two items above as issues 73 and 74. Conditional tests missing from Docs/NOT-VERIFIED.md: ArabicRenderIntegrationTests also needs HarfBuzz but the list names three suites; the 7 tests that need the colour emoji fixture and the 3 that need the open TrueType fixture are not listed. The check must cover every disabled or conditional test, not only the disabled ones.
