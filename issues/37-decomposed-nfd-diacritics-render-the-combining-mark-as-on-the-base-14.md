---
number: 37
title: "Decomposed (NFD) diacritics render the combining mark as ? on the base-14 path"
state: closed
labels: []
assignees: []
created: 2026-07-09T02:57:50+02:00
updated: 2026-07-09T03:28:42+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/37
synced: 2026-07-09T03:28:42+02:00 ef137adcf8b1
neutralized: 2
---

## Problem
The base-14 (WinAnsi) render path applies no Unicode normalization, so a decomposed (NFD) diacritic draws its base letter correctly and then the combining mark as `?`, because the mark is not a WinAnsi code point. Text pasted from the web or read from an HFS+ path (macOS hands back NFD) is the common source.

Confirmed on the shipped base-14 path:
- `cafe` + U+0301 → content stream `(cafe?)` (should be `café`); precomposed `café` (U+00E9) → `(caf\351)` correct.
- `nin` + U+0303 → `(nin?o)`; precomposed `niño` → correct.
- `s` + U+030C → `(s?)`; the precomposed `š` (U+0161) is in CP1252, so NFC would fix it.

## Fix
NFC-normalize on the base-14 encoding chokepoint only. `PDFTextEncoding.portableText` (and `portableScalars`) feed base-14 width, the drawn WinAnsi bytes, and the ActualText span; the embedded path reads `run.text` directly and is not affected. Normalizing `e + U+0301` to `é` (U+00E9) makes it a single WinAnsi byte that renders and extracts correctly, and it also recovers the NFD forms of `š`/`ž`/`à`/`ü`/... whose precomposed char is in CP1252. NFC is canonical-equivalent, so extraction still recovers the real text.

## Out of scope (documented, not this bug)
Characters with no WinAnsi code point even when precomposed (Croatian `č` U+010D, `ć` U+0107, `đ` U+0111) cannot be drawn by base-14 Helvetica at all and remain `?` on that path; they require an embedded font, where the shaper already attaches combining marks. This issue is only about NFD forms that have a WinAnsi precomposed equivalent.

## Tests
Render decomposed `é`, `ñ`, `š`, `ü` on the base-14 path and assert the content stream carries the precomposed WinAnsi byte, not `(...?...)`; assert the embedded path (run.text) is unchanged.
