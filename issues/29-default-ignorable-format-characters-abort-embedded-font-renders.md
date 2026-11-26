---
number: 29
title: "Default-ignorable format characters abort embedded-font renders"
state: closed
labels: []
assignees: []
created: 2026-07-09T00:29:19+02:00
updated: 2026-07-09T14:08:29+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/29
synced: 2026-07-09T14:08:29+02:00 52df2d54f92b
neutralized: 2
---

Follow-up to #27 (which fixed U+FEFF). Under an embedded font whose cmap lacks them, every default-ignorable format character aborts the whole render with `TrueTypeGlyphMappingError.missingGlyph` (policy `.reject`, TrueTypeGlyphMapper.swift:93): U+200B ZWSP, U+200C ZWNJ, U+200D ZWJ, U+2060 word joiner, U+00AD soft hyphen, U+202A/202C/202E bidi controls, U+2028 line sep, U+2029 paragraph sep. Base-14 draws `?` for all except U+00AD.

Per Unicode, default-ignorable code points without glyph support should render invisibly, not as a missing glyph. A ZWSP pasted from a web page is as plausible as a BOM.

Two shapes:
1. Invisible/zero-width formatting (ZWSP, ZWNJ, ZWJ, WJ, SHY, bidi controls, LS/PS): drop before glyph mapping, like #27 does for U+FEFF.
2. Emoji/combining marks the font genuinely lacks (U+1F600, a stray U+0301): these legitimately need a glyph; the fix is a per-scalar notdef/`?` fallback instead of aborting the whole document (TrueTypeGlyphMapper MissingGlyphPolicy).

Also: the outline/bookmark `/Title` path WinAnsi-encodes non-ASCII (draws `?`), separate from page-text stripping, so #27's strip does not reach it. And a file-leading BOM changes document structure (parser never strips it). Related to the title-encoding issue.

Found by the adversarial critic on #27.
