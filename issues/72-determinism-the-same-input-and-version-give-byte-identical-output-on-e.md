---
number: 72
title: "Determinism: the same input and version give byte-identical output on every machine"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:08:58+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/72
synced: 2026-11-24T12:19:19+01:00 291ba8aa3e8d
neutralized: 1
---

## What

Check that the library writes the same bytes for the same input and options on macOS and Linux, on a second run, and under a different locale, time zone and working directory: no dates (the creation date comes from an option or is absent), no random identifiers, no paths, no dictionary or set iteration order, no locale dependent formatting.

## Why

Documents and sites built from them are compared byte for byte, and a reproducible build is part of trust.

## Oracle first

The reference is the committed expected output of the torture test, written on both platforms and twice.

## Acceptance

A test writes the torture document twice in one process and compares, a script compares the hashes from both platforms, and a planted dictionary order dependence is caught.
