---
number: 81
title: "Documentation: the DocC catalog and the README cover every public symbol and every option"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:36:12+01:00
updated: 2026-11-24T13:33:28+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/81
synced: 2026-11-24T13:33:28+01:00 079eb526fc05
neutralized: 1
---

## What

Every public symbol has a documentation comment; the catalog has an article for each product, a page for every option with its default, the error list with each error's cause, the supported Markdown with each construct, and the limits. The README matches the catalog and the CHANGELOG.

## Why

A 1.0 library is used from its documentation.

## Oracle first

The reference is the compiler's symbol list compared with the documented symbols; the options list compared with the options type.

## Acceptance

A check fails on an undocumented public symbol or option, the catalog builds without warnings, and the README claims match tests.

## Comments

### Mihaela, 2026-11-24T13:33:28+01:00

Correction after reading the code on 2026-11-24. The documentation target does not depend on the library target and the workflow builds only that target, so it sees no public symbol: a check that fails on an undocumented public symbol needs the catalogue wired to the library first. README contradictions to fix here: one line says only DejaVu is bundled while another lists three font sets; lines near the top ask for help with colour emoji and cite an old epic; and it claims the same geometry on iOS while another line says iOS support is not claimed. The README has no install section and no package line.
