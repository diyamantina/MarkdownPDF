---
number: 74
title: "The PDF/A and PDF/UA conformance tests are restored or become named limits"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:10:00+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/74
synced: 2026-11-24T12:19:19+01:00 662441b0e496
neutralized: 1
---

## What

Five test groups (about nine cases) that required a full conformance verdict for PDF/A-2a and PDF/UA-1 are disabled because no validator lives in the package (see Docs/NOT-VERIFIED.md). Decide for the 1.0: implement the checks of the two standards against the object graph the reader already walks (fonts, colour and output intent, metadata, structure tree and parent tree, annotations, trailer), with a negative case for each rule, or keep them as named limits that say exactly which rules are checked and which are not.

## Why

A conformance claim must say which rules were checked.

## Oracle first

The reference is the text of the two standards, one rule at a time, with a minimal passing and a minimal failing file for each implemented rule.

## Acceptance

Every rule that is claimed has a passing and a failing file, the documentation lists the claimed and the unchecked rules, and no README line says conformant beyond what is checked.
