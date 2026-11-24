---
number: 89
title: "Two tests use try? on an initializer that does not throw: the compiler warns at every test build"
state: open
labels: ["bug"]
assignees: []
created: 2026-11-25T00:29:25+01:00
updated: 2026-11-25T00:29:25+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/89
synced: 2026-11-25T00:29:25+01:00 894db52bacba
neutralized: 2
---

## What

The full test build prints two warnings, `no calls to throwing functions occur within 'try' expression`:

- `Tests/MarkdownPDFTests/ColorEmojiTests.swift:11`: `return try? PDFOptions.EmbeddedFontSource(data: data, baseName: "Twemoji")`
- `Tests/MarkdownPDFTests/UndrawableEmojiTests.swift:16`: `return (try? Data(contentsOf: url)).flatMap { try? PDFOptions.EmbeddedFontSource(data: $0, baseName: "Twemoji") }`

## Evidence

MEASURED: `PDFOptions.EmbeddedFontSource.init(data:baseName:faceIndex:)` (`Sources/MarkdownPDF/PDFOptions.swift:284`) is not a throwing initializer, so each `try?` inside these two lines does nothing and the value it wraps is never nil. The warnings are in the log of the full test run of 2026-11-24 (1020 tests in 124 suites, 1 warning); the first one is on the first line, the second is the inner `try?` of the second line. The `try?` on `Data(contentsOf:)` in the second line is real and stays.

## Fix

No shortcut: remove the two `try?` and the optional handling that only existed because of them, in the same way in both files, and keep the suite green with no warning. A test first: the build log of the test targets must contain no `no calls to throwing functions` warning (the repository treats a warning as a finding).

## Not part of this issue

The pair of commits that records the math spacing of MathTypeset in this repository does not touch these files.
