---
number: 79
title: "The Apple counterpart: where the Apple path is better, chosen by a paired release measurement"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:30:38+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/79
synced: 2026-11-24T12:19:19+01:00 3277c8698189
neutralized: 1
---

## What

The package has a pure core and a Mac target. For each step where an Apple framework could be faster (compression, image decoding, colour, text measurement, vector maths) decide by a paired release measurement whether a counterpart is used, and prove it equal to the pure path by a differential test (exact equality, or a derived and named tolerance, or fall back and report unsupported). Record each decision.

## Why

A released app uses the Apple path where it is measurably better; the pure path stays the answer key and the path on Linux.

## Oracle first

The reference is the pure path. The differential test compares the two on the whole document corpus.

## Acceptance

Each decision is recorded with its measured numbers, every counterpart that is used has its differential test, and the pure core imports no Apple framework (checked).
