---
number: 72
title: "Determinism: the same input and version give byte-identical output on every machine"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:08:58+01:00
updated: 2026-11-24T13:29:22+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/72
synced: 2026-11-24T13:29:22+01:00 6af6e48bb84d
neutralized: 2
---

## What

Check that the library writes the same bytes for the same input and options on macOS and Linux, on a second run, and under a different locale, time zone and working directory: no dates (the creation date comes from an option or is absent), no random identifiers, no paths, no dictionary or set iteration order, no locale dependent formatting.

## Why

Documents and sites built from them are compared byte for byte, and a reproducible build is part of trust.

## Oracle first

The reference is the committed expected output of the torture test, written on both platforms and twice.

## Acceptance

A test writes the torture document twice in one process and compares, a script compares the hashes from both platforms, and a planted dictionary order dependence is caught.

## Comments

### Mihaela, 2026-11-24T13:29:22+01:00

Correction after reading the code on 2026-11-24. No date is written today and no date option exists: the sentence that the creation date comes from an option describes nothing that exists. The image loader falls back to the process working directory when no base address is given (PDFImage.swift line 66): that is a working-directory dependence to decide. Two calls format numbers without a locale argument (the renderer and the Mermaid code). The trailer identifier is the fixed string MarkdownPDF-PDFA, written only for profiles that need it. A set and dictionary iteration audit has not been done. The cross-platform comparison step depends on the committed torture document of issue 71 and needs a workflow step that does not exist; list 71 as a blocker.
