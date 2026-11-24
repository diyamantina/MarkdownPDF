---
number: 65
title: "MarkdownPDF 1.0 checklist"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T10:56:18+01:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/65
synced: 2026-11-24T12:19:19+01:00 b86e25d3c64c
neutralized: 1
---

## What

The checklist of everything that must be closed or decided before MarkdownPDF 1.0 is tagged. Each line is an issue labelled `before-1.0`.

### Gate

MarkdownPDF goes to 1.0 together with TileDown and MathTypeset. None of the three is released as 1.0 alone: TileDown 1.0 is released only when MathTypeset and MarkdownPDF each have their own 1.0 checklist done. The order of the releases is MathTypeset 1.0, then MarkdownPDF 1.0, then TileDown 1.0.

### First: the oracle

- [ ] #66 MarkdownPDF 1.0 oracle: the answer key of every correctness surface, stated before the work. The items marked "blocked by #66" below wait for it.

### Promise

- [ ] #67 Public API reviewed and nested under the package name
- [ ] #86 1.0 is frozen: bug fixes only after the last feature, and the public API is one reviewed file
- [ ] #82 MarkdownPDF depends on a released MathTypeset 1.0, by version

### Correctness (blocked by #66)

- [ ] #68 The reader meets hostile files: a corpus of malformed PDFs with exact expected errors
- [ ] #69 Every written file is verified by the library's own reader
- [ ] #70 Text extraction round trip: what is drawn is what the reader extracts
- [ ] #71 A torture test: one adversarial document that uses every feature and every edge at once
- [ ] #72 Determinism: the same input and version give byte-identical output on every machine

### Named limits

- [ ] #73 The disabled tests are restored or become named limits: a rasterizer inside the library
- [ ] #74 The PDF/A and PDF/UA conformance tests are restored or become named limits
- [ ] #75 Emoji and symbols the face cannot draw: named, with the reason and what the PDF shows instead
- [ ] #76 Complex scripts at 1.0: Arabic tiers, Hebrew polish, Chinese and Japanese polish, each shipped or a named limit
- [ ] #84 The not-verified list shrinks to named limits

### Fonts

- [ ] #77 Fonts: licences, coverage and the face builders settled

### Speed

- [ ] #78 Performance: measured rows with paired release numbers, and a bound on memory
- [ ] #79 The Apple counterpart: where the Apple path is better, chosen by a paired release measurement

### Documentation and release

- [ ] #80 Literate: each correctness-critical algorithm has its reason, its invariant and a worked example in the DocC catalog
- [ ] #81 Documentation: the DocC catalog and the README cover every public symbol and every option
- [ ] #83 Gaps that the TileDown 1.0 work finds in MarkdownPDF
- [ ] #85 Platforms, packaging and the release path
- [ ] #87 Errata log: every defect found after the 1.0 candidate is recorded

Open issues that are not on this list (#48, #53 and #54, the complex scripts) are decided by #76.

## Why

One place to see how far 1.0 is, and to tell a reader what is promised and what is not.

## Oracle first

The checklist is complete when every item above is closed and `issuesync --check` agrees. The reference for "every issue labelled `before-1.0` is on the list" is the host's own issue list filtered by that label; a labelled issue that is missing from the list, or a list item whose issue lacks the label, is a defect of this issue. The list is counted once at tagging time and that count is the floor.

## Acceptance

Every checkbox above is ticked, every linked issue is closed or has its decision written down, and `issuesync --repo . --check` prints nothing and exits 0.

## Not in scope

Work not tied to one of the issues above.
