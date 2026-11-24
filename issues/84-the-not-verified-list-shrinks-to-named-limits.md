---
number: 84
title: "The not-verified list shrinks to named limits"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:42:16+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/84
synced: 2026-11-24T12:19:19+01:00 98888feb0c9b
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
