---
number: 83
title: "Gaps that the TileDown 1.0 work finds in MarkdownPDF"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:41:45+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/83
synced: 2026-11-24T12:19:19+01:00 09a113a53975
neutralized: 2
---

## What

TileDown writes its PDFs through this library. Keep here the list of PDF faults that the TileDown 1.0 work finds (layout, fonts, emoji, charts, links, accessibility), each as a regression test with its source, and close each by fixing it or by naming it as a limit.

## Why

The projects go to 1.0 together; a gap found by the consumer must not be lost.

## Oracle first

The reference is the document that failed, kept as a regression test with the expected result stated.

## Acceptance

Every gap found is a test, fixed or named as a limit, before the 1.0 tag.
