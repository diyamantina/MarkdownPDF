---
number: 77
title: "Fonts: licences, coverage and the face builders settled"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:29:35+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/77
synced: 2026-11-24T12:19:19+01:00 5294c0ff8240
neutralized: 1
---

## What

List every font the package bundles or builds (the text faces, the symbol faces, the colour emoji face and the tool that builds it) with its licence, its source and its version, and check each licence allows redistribution inside a library and in the PDFs it writes (embedding terms). The licence of the builder used for the colour emoji face is not yet settled; settle it or replace the builder. Record glyph coverage per face from the face's own cmap.

## Why

A font with an unclear licence is a legal defect in a library that ships it.

## Oracle first

The reference is the licence text of each font and the embedding flags (the fsType field) read from the font file by the library's own parser. Exact match of the claimed and the read embedding permission.

## Acceptance

A table lists each face with licence, source, version and fsType, every licence is checked in or named as open with its owner, and the README links it.
