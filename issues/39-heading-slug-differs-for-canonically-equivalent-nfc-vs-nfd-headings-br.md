---
number: 39
title: "Heading slug differs for canonically-equivalent (NFC vs NFD) headings, breaking internal links"
state: closed
labels: []
assignees: []
created: 2026-07-09T03:28:41+02:00
updated: 2026-07-09T03:48:04+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/39
synced: 2026-07-09T03:48:04+02:00 0349a3babad0
neutralized: 1
---

Found by the adversarial critic reviewing #37/#38 (low severity, PLAUSIBLE, pre-existing; untouched by that fix).

## Problem
The heading-slug / named-destination generator drops a combining mark differently from the equivalent precomposed character, so two canonically-equivalent headings produce different anchor slugs:
- Decomposed heading `Cafe` + U+0301 → destination slug `cafe-du-monde` (the base letter `e` survives, the mark is dropped).
- Precomposed heading `Café` (U+00E9) → slug `caf-du-monde` (the whole `é` is dropped).

A document that links to a heading using one normalization form while the heading is authored in the other gets an internal link that misses its target.

## Fix direction
NFC-normalize (or otherwise canonicalize) heading text before slug generation so canonically-equivalent headings yield the same slug, and apply the same normalization to intra-document link targets. This aligns with the base-14 NFC work in #37 but lives in the slug/destination path, which #38 did not touch.

Severity: low (needs mixed-normalization input), but it is a real internal-link correctness gap.
