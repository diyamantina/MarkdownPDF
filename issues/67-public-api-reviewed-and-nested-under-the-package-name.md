---
number: 67
title: "Public API reviewed and nested under the package name"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T10:57:21+01:00
updated: 2026-11-24T13:27:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/67
synced: 2026-11-24T13:27:19+01:00 b3adaf6e7bd5
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

## Comments

### Mihaela, 2026-11-24T13:27:19+01:00

Correction after reading the code on 2026-11-24. MarkdownPDFDocumentation is a target, not a product, and has no public symbol; MarkdownPDFMac is a product only on a macOS host. Twelve file-scope public types are flat today (MarkdownBlock, MarkdownInline, MarkdownPDF, MarkdownPDFError, MarkdownDocument, MarkdownMath, MarkdownParser, MarkdownPDFRenderer, MarkdownSource, PDFColor, PDFDocumentReader, PDFOptions); the public enum MarkdownPDF already exists with Render, Render.Report, Render.UndrawnPolicy and Render.Output, so the target is the rest. The namespacing check today only counts file-scope types per file; the check on flat public names is new work.
