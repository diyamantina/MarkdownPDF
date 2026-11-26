---
number: 71
title: "A torture test: one adversarial document that uses every feature and every edge at once"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:03:56+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/71
synced: 2026-11-24T12:19:19+01:00 fe02ac786cce
neutralized: 2
---

## What

In the spirit of the TeX trip test: one input document that exercises every block and inline construct, every option, every font path, every chart and diagram type, nesting to the documented depth, empty and maximal content, malformed and hostile Markdown. The complete output (the PDF bytes) is committed as the expected answer and compared byte for byte.

## Why

A single committed answer catches every change of behaviour, intended or not.

## Oracle first

The expected file is reviewed by hand once, then frozen; a change needs a reviewed diff of the expected file and the reader's text and structure report of it.

## Acceptance

The input and the expected PDF are committed, the test compares byte for byte, and a planted fault in any one rule turns it red.
