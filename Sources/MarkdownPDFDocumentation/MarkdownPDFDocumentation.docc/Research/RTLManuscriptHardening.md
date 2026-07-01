# RTL manuscript hardening

Date: 2026-06-02

Issue: #123

This note expands `complex-script-shaping-bidi-roadmap.md` from a minimal bidi
foundation to manuscript-scale right-to-left content. It is portable macOS and
Linux research, not an implementation promise until Swift source and witnesses
exist.

## Product boundary

The shared renderer remains Pure Swift and Linux-buildable, generates PDF bytes
directly, and must not depend on CoreText, CoreGraphics, AppKit, UIKit, PDFKit,
WebKit, browser renderers, LaTeX, JavaScript, Python, shell renderers, HarfBuzz,
or C font / PDF / Markdown libraries. iOS support is not claimed.

## What already exists

- #84 added a portable bidi paragraph ordering profile.
- #85 added pure Swift shaping increments; #86 added shaped embedded-font
  emission with ToUnicode.
- Fixture groups name Arabic and Hebrew, but as planning sets, not support
  claims. There is no manuscript-scale RTL fixture across real block kinds.

## Standards anchors

- Unicode UAX #9 bidirectional algorithm, embedding levels, isolates, neutral
  and number resolution, and mirrored characters:
  <https://www.unicode.org/reports/tr9/>
- Unicode UAX #14 line breaking interacts with bidi at run boundaries:
  <https://www.unicode.org/reports/tr14/>
- BidiMirroring data for paired punctuation mirroring.

## Separate facts: logical order vs visual order

Source extraction order and visual draw order are different requirements. A
fixture can demand an RTL visual run order for drawing while still requiring
logical-order extraction through ToUnicode. Every RTL fixture must state both
expectations before code changes.

## Manuscript-scale scope

- Block kinds: paragraphs, headings, ordered and unordered lists, tables, and
  block quotes, each containing RTL text.
- Mixed direction: Arabic and Hebrew runs interleaved with LTR words, ASCII and
  European numbers, and punctuation.
- Number handling: resolve European and Arabic-Indic numbers per UAX #9 so they
  read correctly inside RTL runs.
- Mirroring: mirror paired punctuation (brackets, parentheses, angle brackets)
  in RTL runs using BidiMirroring data.
- Base direction: support an RTL paragraph base direction where the content
  requires it, not only isolated RTL runs inside an LTR paragraph.
- Tables: column order and per-cell direction must be defined; document whether
  table column order follows base direction in this milestone or is deferred.

## Failure policy

Unsupported bidi controls, unbalanced isolates, or missing glyphs render a
visible fallback marker or throw a typed error. Silent wrong visual order, lost
logical extraction, overlapped glyphs, or dropped marks are not acceptable.

## Witness policy

- `qpdf --check` with no warnings.
- Swift structural checks for the embedded-font object graph and resources.
- `pdftotext` extracts Arabic and Hebrew in logical source order.
- An explicit visual run order assertion for at least one mixed RTL / LTR /
  number line.
- `pdftotext -tsv` boxes inside page bounds with no same-line overlap.
- MuPDF structured text: positive, non-overlapping character quads in RTL runs.
- Poppler and MuPDF raster comparison for nonblank, comparable ink bounds.
- A mirroring witness proving paired punctuation is mirrored in an RTL run.
- macOS and Linux both run the same portable suite.

## Font fixture policy

The public repo stores no font binaries. Use generated Swift TrueType fixtures
for deterministic tests and a CI-installed or environment-provided open font that
covers Arabic and Hebrew through an `MARKDOWNPDF_OPEN_FONT_PATH`-style variable.
Tests needing such a font may skip only when the path is absent, naming the
missing path.

## Ordered work

1. Add manuscript-scale RTL fixtures (Arabic + Hebrew) across block kinds.
2. Add UAX #9 number and neutral resolution coverage with unit tests.
3. Add BidiMirroring-based paired-punctuation mirroring with a geometry witness.
4. Define RTL paragraph base-direction behavior and table column-order policy.
5. Add the full witness stack for visual order and logical extraction.
6. Add negative tests for unsupported controls and missing glyphs.

## Platform notes

- Portable macOS / Linux: every behavior above belongs in the shared renderer.
- macOS-only: no behavior here requires macOS APIs.
- iOS: not claimed.

## Reference implementations

All four engines split bidi the same way our pipeline should: resolve UAX #9
levels over logical text, split into same-level / same-script runs, shape each
run, then apply rule L2 to reorder into visual order while keeping the logical
buffer for extraction through ToUnicode. None reimplements UAX #9 directly:
Pango delegates to FriBidi, SILE delegates to ICU, and Typst delegates to
`unicode-bidi`. This validates our pure Swift #84 profile as the novel local
piece.

Pango, C, LGPL-2.1+, reference only:

- `researchcode/pango/pango/pango-layout.c`: `reorder_runs_recurse()` around
  line 6025 and `pango_layout_line_reorder()` around line 6090 implement UAX #9
  rule L2 run reordering with a single-direction fast path. Base direction P2 /
  P3 comes through `pango_find_base_dir()`.

SILE, Lua, MIT, closest analog because it reorders typeset boxes:

- `researchcode/sile/packages/bidi/init.lua`: `create_matrix()` around line 22
  models L2 as a permutation, including the example `Levels [0,0,0,1,1] ->
  [1,2,3,5,4]`; `splitNodelistIntoBidiRuns()` around line 111 consumes ICU
  `icu.bidi_runs`; `package:reorder()` around line 195 reorders nodes, with a
  neutral-resolution fallback around lines 206 through 223; `reverse_each_node()`
  around line 61 reverses glyph order in RTL boxes.

HarfBuzz, C++, MIT-style, per-run shaping after bidi and mirroring:

- `researchcode/harfbuzz/src/hb-ot-shape.cc`: `hb_ot_rotate_chars()` around line
  651 mirrors brackets through `unicode->mirroring()` with an `rtlm` feature
  fallback around lines 664 through 668; `hb_ensure_native_direction()` around
  line 588 reverses RTL-run graphemes while keeping numeric runs in native LTR
  order. This is the authoritative model for our BidiMirroring step.

Typst, Rust, Apache-2.0, clean split-and-reorder model:

- `researchcode/typst/crates/typst-layout/src/inline/shaping.rs`:
  `shape_range()` around line 717 splits runs by `level != prev_level || script
  change` around line 750 before shaping; `prepare.rs` line 78 builds levels
  through `unicode-bidi` `BidiInfo::new`.
- `researchcode/typst/crates/typst-layout/src/inline/line.rs`: `reorder()`
  around line 249 uses `bidi.visual_runs()` to compute visual-order ranges for
  rendering while retaining logical ranges for ToUnicode extraction.

To vendor under #137:

- `fribidi/lib/fribidi-bidi.c`, LGPL, reference UAX #9 implementation.
- `unicode-bidi/src/{implicit,explicit,prepare,level}.rs`, MIT / Apache, clean
  pure UAX #9 implementation.

Spec anchors:

- Unicode UAX #9, especially P2 / P3, W / N / I resolution, L1, and L2.
- Unicode UAX #14 for line breaking.
- UCD `BidiMirroring.txt` for paired punctuation mirroring.
