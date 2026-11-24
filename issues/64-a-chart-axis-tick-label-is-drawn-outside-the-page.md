---
number: 64
title: "A chart axis tick label is drawn outside the page"
state: closed
labels: []
assignees: []
created: 2026-11-24T00:24:30+01:00
updated: 2026-11-24T01:11:12+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/64
synced: 2026-11-24T01:11:12+01:00 0ab81f39de83
neutralized: 1
---

A chart axis tick label can be drawn outside the page.

Found by an audit before TileDown 0.17.0 (2026-11-24): in the showcase fixture `05-charts-dashboard.md` the label "20" on a chart axis is placed at x 639 on a page 612 points wide. The test `ShowcaseFixtureTests` holds this as a known issue (`withKnownIssue`, line 48), so it is not a failure today and no issue was filed.

Expected: every tick label of a chart lies inside the page and inside the chart's own frame, at every page size.

Acceptance: the known issue becomes a real expectation (every label box lies inside the page); an answer key apart from the layout code that computes, from the chart's data and the page width, where the labels must lie; a planted fault in the layout (the clamp removed) turns the test red; the library's own gate passes; the CHANGELOG has a Fixed entry.
