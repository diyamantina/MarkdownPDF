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

## Platform notes

- Portable macOS / Linux: every behavior above belongs in the shared renderer.
- macOS-only: no behavior here requires macOS APIs.
- iOS: not claimed.
