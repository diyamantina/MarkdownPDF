---
number: 89
title: "The package and its tests build with twelve compiler warnings: unnecessary try, an unused value, a var never mutated"
state: closed
labels: ["bug"]
assignees: []
created: 2026-11-25T00:29:25+01:00
updated: 2026-11-26T03:33:17+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/89
synced: 2026-11-26T03:33:17+01:00 16859ba16637
neutralized: 2
---

## What

A build from scratch prints twelve warnings:

- nine `try` before a call that cannot throw: `Sources/MarkdownPDF/TrueTypeFontParser.swift:215`; in the tests `ArabicRenderIntegrationTests.swift:118` and `141` (the second inside an `#expect`), `ColorEmojiTests.swift:11`, `UndrawableEmojiTests.swift:16`, `MarkdownPDFRendererTests.swift:596`, `618`, `639` and `753`;
- one value never used: `Sources/MarkdownPDF/MarkdownPDFRenderer.swift:3288`, `endpoints` in the Mermaid edge routing;
- two `var` never mutated: `ColorTableTests.swift:98` and `TrueTypeGlyphOutlineTests.swift:188`.

## Evidence

MEASURED: a build of the package and its tests from an empty scratch folder. The first count of two came from an incremental test run, which prints only what it recompiles.

## Fix

Remove each at its root, and add a gate `scripts/check-warnings.sh` that builds from scratch and fails on any warning in `Sources/` or `Tests/`. State: fixed in the commit that follows; this issue closes with it.

## Comments

### Mihaela, 2026-11-26T03:33:17+01:00

Fixed in 0.19.0 (commit df84453): a build from scratch prints no warning, and scripts/check-warnings.sh fails the heavy gate on any new one. Re-checked on main ac49d9e: a build of the package and tests from an empty build folder, read by that script, shows no warning in Sources/ or Tests/.
