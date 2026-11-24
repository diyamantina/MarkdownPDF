---
number: 67
title: "Public API reviewed and nested under the package name"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T10:57:21+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/67
synced: 2026-11-24T12:19:19+01:00 f9eb1061c7f1
neutralized: 1
---

## What

Every public type is nested as MarkdownPDF.Area.Name. Review the public symbols of every product (MarkdownPDF, MarkdownPDFMac, MarkdownPDFLinux, MarkdownPDFResume, MarkdownPDFDocumentation): many are flat names with a PDF or Markdown prefix (for example PDFDocumentReader, PDFOptions, MarkdownDocument, MarkdownPDFRenderer, MarkdownPDFError). For each: keep, rename into a namespace that mirrors the folder, or make internal. Record the decision, and write the old to new table for the CHANGELOG. This is breaking and belongs before 1.0.

## Why

The top namespace is the package name. After 1.0 a rename is a major version.

## Oracle first

The reference is the compiler's symbol list for each product compared with the reviewed list in the repository.

## Acceptance

Every public symbol is nested under MarkdownPDF, one type per file named after the full nested name, the reviewed list is in the repository, the CHANGELOG carries the old to new table, and a check fails on a flat public name.
