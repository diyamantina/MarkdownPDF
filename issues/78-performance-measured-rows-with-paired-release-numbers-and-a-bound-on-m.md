---
number: 78
title: "Performance: measured rows with paired release numbers, and a bound on memory"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:30:06+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/78
synced: 2026-11-24T12:19:19+01:00 a9f5c28fa743
neutralized: 1
---

## What

Measure the time and peak memory of rendering a fixed set of documents (a short note, an article with images, a long manuscript, a document with many charts, a large table, a document with emoji, an index) in a release build: old and new back to back, medians, load printed, machine named. Record the rows in the repository and state the memory bound per page. State which part of a run takes how much by a profile, not by guess.

## Why

A claim of speed needs a number, and a guessed win is not made.

## Oracle first

The reference is the slow, obviously correct path kept as the answer key; an optimized path must produce the same bytes.

## Acceptance

The rows are in the repository with the machine, load and date, the profile of the slowest case is recorded, and no optimization is merged without its paired number.
