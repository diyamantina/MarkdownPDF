---
number: 82
title: "MarkdownPDF depends on a released MathTypeset 1.0, by version"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:36:44+01:00
updated: 2026-11-24T13:34:09+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/82
synced: 2026-11-24T13:34:09+01:00 c0d1ae47c1c8
neutralized: 1
---

## What

The math adapter uses MathTypeset. At 1.0 the dependency is a released version range of MathTypeset 1.0, not a branch. The two go to 1.0 together; this item is the order of the releases: MathTypeset 1.0 is tagged first, then this package pins it and tags its own 1.0.

## Why

A tagged library must not depend on a moving branch.

## Oracle first

The reference is the resolved dependency graph of a clean checkout: every dependency is a tagged version.

## Acceptance

The manifest names a version range, the resolved file shows a tag, and a check fails when a dependency is a branch or a revision.

## Comments

### Mihaela, 2026-11-24T13:34:09+01:00

Correction after reading the code on 2026-11-24. The dependency is a branch today (branch main in the manifest). Package.resolved is ignored by the repository, so there is no resolved file to inspect: decide whether it is committed, or state the check on the manifest alone.
