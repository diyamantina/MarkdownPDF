# CJK and combining-diacritics rendering

Date: 2026-06-02

Issue: #122

This note expands the existing complex-script and embedded-font research to two
scalar ranges the current fixture groups do not yet cover: Unicode combining
diacritics across scripts, and CJK / kanji ideographs. It is portable macOS and
Linux research, not an implementation promise until Swift source and witnesses
exist.

## Product boundary

The shared renderer remains Pure Swift and Linux-buildable, generates PDF bytes
directly, and must not depend on CoreText, CoreGraphics, AppKit, UIKit, PDFKit,
WebKit, browser renderers, LaTeX, JavaScript, Python, shell renderers, HarfBuzz,
or C font / PDF / Markdown libraries. iOS support is not claimed.

## What already exists

- Base profile: ASCII U+0020-U+007E only, every other scalar replaced with `?`
  (`markdownpdf-output-profile.md`).
- Opt-in embedded fonts: Type 0 / CIDFontType2 + FontFile2 + ToUnicode,
  Identity-H, Latin-first, one scalar to one glyph, deterministic subsetting
  (`portable-embedded-fonts-tounicode-plan.md`).
- Shaped cluster model with one-to-many / many-to-one / many-to-many ToUnicode
  (#82) and shaped emission (#86), with fixture groups for Latin combining
  marks, ligatures, Arabic, Hebrew, Indic, Thai/Khmer
  (`complex-script-shaping-bidi-roadmap.md`,
  `complex-script-fixture-witness-policy.md`).

## Gaps this note addresses

- CJK / kanji is absent from every existing fixture group.
- Combining diacritics exist only as the narrow Latin combining-mark group; there
  is no cross-script combining-mark policy and no manuscript-scale fixture.

## Standards anchors

- Unicode UAX #14 line breaking, ID class for ideographs:
  <https://www.unicode.org/reports/tr14/>
- Unicode UAX #15 normalization forms (NFC / NFD):
  <https://www.unicode.org/reports/tr15/>
- Unicode UAX #11 East Asian Width:
  <https://www.unicode.org/reports/tr11/>
- TrueType `cmap` format 12 for supra-BMP scalars and CJK coverage.

## Combining diacritics model

- Treat a base scalar plus its trailing combining marks as one cluster in the
  #82 shaped cluster model.
- ToUnicode must map the emitted character codes back to the full source scalar
  sequence so extraction is normalization-faithful.
- Mark positioning:
  - If portable GPOS mark attachment is implemented, witness that mark quads do
    not overlap the base glyph quad incorrectly.
  - If GPOS is not implemented, marks render at default advance. This must be
    documented as a known limitation and either gated to scripts where stacked
    default-advance marks are acceptable, or kept unsupported and visible. Silent
    broken stacking is not allowed.
- Normalization: accept NFC and NFD input. Do not silently renormalize source in
  a way that breaks ToUnicode round-tripping.

## CJK / kanji model

- Glyph mapping: parse `cmap` format 12 in addition to format 4 so supra-BMP and
  full CJK ranges resolve to glyph ids. Most Han text is one scalar to one glyph;
  no shaping is required for the baseline.
- Metrics: use fullwidth advances from `hmtx`. Do not assume Latin advance
  widths. East Asian Width (UAX #11) informs wrapping and column estimates.
- Line breaking: implement UAX #14 ID-class behavior. Break opportunities exist
  between most ideographs, with the standard non-breaking exceptions (for example
  before closing punctuation and after opening punctuation). Implement and unit
  test break opportunities before changing line selection.
- Subsetting pressure: CJK fonts are large. Subset only the used scalars, assign
  deterministic compact CIDs, and emit a CIDToGIDMap stream when CIDs do not
  equal glyph ids. Keep object ordering deterministic.
- Vertical writing, ruby, and Han-unification variant selection remain out of
  scope for the baseline.

## Witness policy

Reuse the complex-script witness stack:

- `qpdf --check` with no warnings; base-font default PDFs still omit font files
  and ToUnicode.
- Swift structural checks for Type 0 parent, CIDFontType2 descendant,
  FontDescriptor / FontFile2, ToUnicode reference, and page resource usage.
- `pdftotext` faithful extraction for both diacritic and CJK fixtures.
- `pdftotext -tsv` boxes inside page bounds with no same-line overlap.
- MuPDF structured text: positive, non-overlapping character quads.
- Poppler and MuPDF raster comparison for nonblank, comparable ink bounds.
- macOS and Linux both run the same portable suite.

## Font fixture policy

The public repo stores no font binaries. Current tests use generated Swift
TrueType fixtures for deterministic parser, subset, writer, and visual witness
coverage. If future work needs a real open font corpus, it should add an
explicit opt-in environment variable and skip only when the path is absent,
naming the missing path in the skip reason.

## Ordered work

1. Add `cmap` format 12 parsing and CJK glyph mapping with unit tests.
2. Add fullwidth metric handling and East Asian Width-aware width estimation.
3. Add UAX #14 ID-class line-break opportunity detection with unit tests.
4. Extend the cluster model and ToUnicode for cross-script combining diacritics.
5. Decide and document the mark-positioning policy (GPOS or default-advance
   fallback) with geometry witnesses.
6. Add manuscript-scale CJK + diacritics fixtures and full witness coverage.
7. Add negative tests for missing glyphs and unsupported scalars.

## Implementation notes

- #122 implements the first CJK line-breaking increment in
  `LineBreakOpportunityDetector`: Han, kana, hangul, CJK Extension A,
  compatibility ideographs, and supplementary CJK ranges are treated as
  no-space script scalars.
- The detector now protects CJK opening and closing punctuation boundaries and
  unit-tests breaks between ideographs, kana, hangul syllables, and CJK
  punctuation runs.
- The synthetic TrueType test fixture now has a CJK format 12 profile. Parser,
  mapper, and renderer tests prove 1000-unit `hmtx` advances for ideographs,
  CID width emission, ToUnicode extraction, and narrow-page wrapping without
  committing a real font file.
- A committed `cjk-diacritics-manuscript.md` fixture now runs through the visual
  witness stack with an embedded synthetic font. It covers CJK line breaking,
  Latin text, ordered lists, Latin `e` plus U+0301, CJK plus U+0301, qpdf,
  Poppler extraction and geometry, MuPDF character quads, and Poppler/MuPDF
  raster comparison.
- Missing CJK glyphs are covered by a typed negative test. Remaining work is
  limited to any East Asian Width fallback policy for text rendered without an
  embedded font.

## Reference implementations

The following vendored sources under `researchcode/` are study-only references.
They must be reimplemented in the pure Swift embedded-font and shaped-cluster
path. Do not add HarfBuzz, ICU, Pango, Skia, or other C/C++ runtime dependencies.

HarfBuzz:

- `researchcode/harfbuzz/src/hb-ot-shape.cc`: `hb_ot_position_plan`,
  `_hb_ot_shape_fallback_mark_position`, and `fallback_mark_positioning` show the
  GPOS-or-fallback decision for combining diacritics. The Swift path should use
  embedded-font GPOS mark-to-base data when present, else keep a visible
  zero-advance fallback.
- `researchcode/harfbuzz/src/hb-buffer.cc`: `merge_clusters_impl` and
  `hb_buffer_set_cluster_level` show how source scalars stay attached to ligated
  glyph runs for multi-scalar ToUnicode.
- `researchcode/harfbuzz/src/hb-font.cc`:
  `hb_font_get_nominal_glyphs_default`,
  `hb_font_get_variation_glyph_default`, and
  `hb_font_get_glyph_h_advance_default` describe the consumer contract for
  `cmap` format 4 and 12 lookup plus horizontal advances.

Pango:

- `researchcode/pango/pango/shape.c`: `pango_hb_shape` writes `log_clusters`
  and `is_cluster_start`, which is the cluster-to-source-character back-map
  needed by ToUnicode.
- `researchcode/pango/tests/LineBreakTest.txt` and
  `researchcode/pango/tests/validate-log-attrs.c`: Unicode UAX #14 conformance
  vectors and validation shape for a future complete line-break implementation.
- `researchcode/pango/pango/pango-layout.c`: `can_break_at` and `process_line`
  show how computed break attributes drive greedy wrapping.
- `researchcode/pango/pango/fonts.c`: `g_unichar_iswide` is a reference point
  for East Asian Width behavior when a fallback width policy is added.

Skia:

- `researchcode/skia/src/pdf/SkClusterator.cpp`: `next()` groups glyphs that
  share a cluster id and finds each cluster's UTF-8 source span.
- `researchcode/skia/src/pdf/SkPDFDevice.cpp`: PDF text emission uses clusters
  for ToUnicode, records multi-scalar source text when needed, and falls back to
  ActualText spans for true many-glyph clusters.
- `researchcode/skia/src/pdf/SkPDFMakeToUnicodeCmap.cpp`:
  `SkPDFAppendCmapSections` and `append_bfchar_section_ex` show CMap section
  coalescing and multi-scalar UTF-16BE targets.

Future vendoring candidate:

- `unicode-linebreak` (`src/lib.rs`, Rust, Apache-2.0) is a useful reference for
  the complete UAX #14 rule engine. Track vendoring separately through #137.

Spec anchors remain Unicode UAX #14, UAX #11, UAX #15, OpenType `cmap` format
4/12, and OpenType GPOS mark attachment.

## Platform notes

- Portable macOS / Linux: every behavior above belongs in the shared renderer.
- macOS-only: no behavior here requires macOS APIs.
- iOS: not claimed.
