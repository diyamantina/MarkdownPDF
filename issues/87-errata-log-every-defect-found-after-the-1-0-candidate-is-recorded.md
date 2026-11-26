---
number: 87
title: "Errata log: every defect found after the 1.0 candidate is recorded"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T12:01:50+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/87
synced: 2026-11-24T12:19:19+01:00 d7cbb87b347b
neutralized: 2
---

## What

Keep a log in the repository: for each defect found after the 1.0 candidate, its number, the date, the cause and the test that now holds it. The log ships with the release.

## Why

A fix without a recorded cause and a test comes back.

## Oracle first

The reference is the issue list: every issue closed as a bug after the candidate has a row.

## Acceptance

The log exists and ships, and a check fails when a closed bug has no row.
