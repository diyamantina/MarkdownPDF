---
number: 77
title: "Fonts: licences, coverage and the face builders settled"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:29:35+01:00
updated: 2026-11-24T13:32:48+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/77
synced: 2026-11-24T13:32:48+01:00 5f0d7465e884
neutralized: 2
---

## What

List every font the package bundles or builds (the text faces, the symbol faces, the colour emoji face and the tool that builds it) with its licence, its source and its version, and check each licence allows redistribution inside a library and in the PDFs it writes (embedding terms). The licence of the builder used for the colour emoji face is not yet settled; settle it or replace the builder. Record glyph coverage per face from the face's own cmap.

## Why

A font with an unclear licence is a legal defect in a library that ships it.

## Oracle first

The reference is the licence text of each font and the embedding flags (the fsType field) read from the font file by the library's own parser. Exact match of the claimed and the read embedding permission.

## Acceptance

A table lists each face with licence, source, version and fsType, every licence is checked in or named as open with its owner, and the README links it.

## Comments

### Mihaela, 2026-11-24T13:32:48+01:00

Correction after reading the code on 2026-11-24. The package builds no font and has no font build script: Twemoji.ttf is a prebuilt third-party file (twemoji-colr, release 17.0.3). The open point is the licence of that builder as the issue says, not a tool of this repository. There is no separate symbol face; symbols come from DejaVu. The README font section is prose with no version, source or embedding flag per face.
