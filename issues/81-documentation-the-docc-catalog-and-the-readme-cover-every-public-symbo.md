---
number: 81
title: "Documentation: the DocC catalog and the README cover every public symbol and every option"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:36:12+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/81
synced: 2026-11-24T12:19:19+01:00 8edb889ed2bb
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
