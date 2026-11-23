---
number: 21
title: "Unmatched inline openers parse in O(n^2) time (DoS)"
state: closed
labels: []
assignees: []
created: 2026-07-08T23:40:15+02:00
updated: 2026-07-09T00:03:27+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/21
synced: 2026-07-09T00:03:27+02:00 bd72a87a5a25
neutralized: 1
---

A run of inline openers with no matching closer parses quadratically. Each failed opener scans to end-of-string for its closer (`firstUnescaped("]")`, `firstIndex(">")`, `firstIndex(")")`), then `consumeText` advances a single character and the loop retries, so n openers cost O(n^2).

Measured (debug): `[` x1000 = 0.021s, x2000 = 0.079s, x4000 = 0.322s. Clean 4x per 2x doubling. A single ~KB line of `[`, `![`, `<`, or `[a](` wedges the parser for seconds; ~1 MB is minutes.

Triggers: `[`xn, `![`xn, `<`xn, `[a](`xn (has `]` but no `)`). Reproduces in debug and release. No crash, pure CPU DoS. Any untrusted Markdown reaches it.

Confirmed independently by two adversarial hunters. Outside the region the block-level nesting cap covers.

Fix: memoize, per parse, the earliest index from which each close character is known absent, and short-circuit later scans.
