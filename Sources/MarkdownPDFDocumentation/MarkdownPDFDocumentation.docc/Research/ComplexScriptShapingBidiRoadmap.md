# Complex script shaping and bidi roadmap

Status: done on 2026-06-01. #86 is done through PR #94, and #85 is done
through PR #93.

Scope: this note defines the next epic after the Latin-first embedded-font
foundation. It is portable macOS and Linux research. It is not a macOS-only
plan, not an iOS claim, and not an implementation promise until source and tests
exist.

## Current boundary

The current portable renderer can embed caller-provided TrueType data and write
Type 0 / CIDFontType2 text with ToUnicode maps for the Latin-first profile. That
profile intentionally does not claim complex-script shaping, bidirectional
layout, ligatures, mark positioning, vertical writing, ruby text, emoji, color
fonts, variable fonts, or full OpenType shaping.

Unsupported text must not silently become a quality claim. Future issues need
fixtures and witnesses before they can claim support for any script or feature.

## Standards and source anchors

Unicode UAX #14 defines line-break opportunities, but final line selection is a
higher-level layout decision:

https://www.unicode.org/reports/tr14/

Unicode UAX #9 defines bidirectional text ordering and explicit formatting
controls:

https://www.unicode.org/reports/tr9/

OpenType defines glyph substitution and positioning tables needed for many
scripts:

https://learn.microsoft.com/en-us/typography/opentype/spec/overview

HarfBuzz documents shaping as transforming Unicode code points into positioned
glyphs from a selected font. Its concepts are useful, but HarfBuzz itself is a C
dependency and is outside the shared renderer boundary:

https://harfbuzz.github.io/shaping-concepts.html

## Boundary matrix

| Area | Portable source of truth | Renderer responsibility | Out of scope for the shared renderer |
|---|---|---|---|
| Line breaking | Unicode UAX #14 line-break classes and pair rules. | Find legal break opportunities in logical text and feed them to the existing line selection algorithm. | Locale dictionary breaking, typographic justification, and platform text engines. |
| Bidirectional text | Unicode UAX #9 paragraph levels, embedding controls, isolates, and neutral resolution. | Keep logical source text, compute a visual run order for drawing, and prove extraction expectations with Poppler and MuPDF. | Claims that visual order or extracted order is correct before fixtures cover mixed RTL/LTR text. |
| Glyph substitution | OpenType GSUB tables for the scripts and features a future issue names explicitly. | Map source clusters to glyph ids without losing the source scalar sequence needed for ToUnicode. | Full universal shaping in one issue, HarfBuzz as a linked dependency, and Apple-only shaping inside the core. |
| Glyph positioning | OpenType GPOS advances, offsets, marks, and cursive attachment for the supported increment. | Preserve advances and offsets in the shaped text model before emitting PDF text operators. | Kerning or mark positioning claims without geometry witnesses. |
| Shaping concepts | HarfBuzz shaping model, clusters, buffer properties, script/language/direction inputs, and feature flags. | Reuse the concepts as design vocabulary and test expectations. | Importing, linking, shelling out to, or vendoring HarfBuzz. |
| macOS adapter research | CoreText can be investigated only as a product adapter outside the portable core. | Keep any macOS-only discovery behind a separate adapter plan and mark it macOS-only. | Treating macOS results as Linux behavior or as iOS support. |

The portable contract is standards-driven, not platform-driven. A future macOS
adapter may help compare measurements or prototype shaping behavior, but the
shared renderer can only claim behavior implemented in Swift and verified on
macOS and Linux.

## Issue #80 boundary

#80 is documentation and tracker work only. It does not add renderer code,
fixtures, parser tables, or public API. It defines the line where future issues
must begin:

- #81 must turn the fixture groups below into explicit expected text, geometry,
  raster, and failure-policy witnesses.
- #82 must introduce a shaped cluster model before any renderer path changes.
- #83 must implement portable line-break opportunities separately from bidi and
  shaping.
- #84 must implement bidi ordering separately from OpenType shaping.
- #85 must prototype a narrow pure Swift shaping increment before broad script
  claims.
- #86 must emit PDF only after the model, fixtures, line breaking, bidi, and
  first shaping increment are proved.

## Portable versus platform-specific

Portable core work must be pure Swift and Linux-buildable. It can use Unicode
and OpenType specifications as implementation inputs, but it must not depend on
CoreText, CoreGraphics, AppKit, UIKit, PDFKit, WebKit, browser renderers, LaTeX,
JavaScript, Python, shell renderers, or C shaping/PDF/Markdown libraries.

A future macOS product adapter may investigate CoreText shaping or measurement,
but that work belongs outside the shared renderer. macOS results do not imply
Linux behavior and do not imply iOS support. iOS support remains unimplemented
and untested until an explicit iOS target and witness suite exist.

## First fixture groups

The first fixture policy should cover:

- Latin ligatures and combining marks.
- Arabic or another script that requires contextual joining and bidi handling.
- Hebrew or another RTL script with mixed numbers and LTR words.
- At least one Indic script with combining marks or reordering behavior.
- Thai or Khmer no-space line-break opportunities.
- Unsupported controls, scripts, fonts, or shaping features that must throw
  typed errors or render explicit visible fallback.

Fixtures should keep font handling repository-safe. Do not commit font binaries.
Use generated Swift fixtures where possible and CI-installed or
environment-provided open fonts for smoke tests. The detailed policy lives in
`complex-script-fixture-witness-policy.md`.

## First script and feature gates

The first profile must be explicit about the scripts and features it supports.
These groups define the minimum fixture planning set, not a support claim:

| Group | Feature pressure | Required witness before support can be claimed |
|---|---|---|
| Latin combining marks | Multiple scalars may produce one positioned cluster. | Source-faithful extraction and no overlapping character quads. |
| Latin ligatures | Multiple scalars may map to one glyph. | ToUnicode maps the ligature glyph back to the original scalar sequence. |
| Arabic | Contextual joining, direction, cursive attachment, marks, and mixed numbers. | Bidi paragraph order, shaped glyph ids, extraction, and raster geometry all pass on macOS and Linux. |
| Hebrew | RTL runs mixed with LTR words, punctuation, and numbers. | Visual order and source extraction expectations are named and witnessed. |
| Indic script | Reordering, conjuncts, matras, and combining behavior. | Cluster model proves many-to-one and one-to-many mappings before drawing. |
| Thai or Khmer | No-space line-break opportunities. | UAX #14 break opportunities are tested before line selection changes. |
| Unsupported controls or fonts | Inputs outside the supported profile. | Typed errors or explicit visible fallback, never silent broken text. |

## Text model requirement

The next implementation cannot treat one Unicode scalar as one glyph forever.
The internal model needs separate fields for:

- Source Unicode scalar range.
- Cluster source text used for extraction.
- Glyph ids selected by the shaper.
- Glyph advances and optional offsets.
- PDF character codes assigned by the subset planner.
- ToUnicode scalar sequences for each emitted PDF character code or cluster.

This model must support one-to-one, one-to-many, many-to-one, and many-to-many
relationships. Examples include ligatures, split glyphs, combining sequences,
and shaped clusters.

## Ordered issues

1. #80 Research Unicode line breaking, bidi, and shaping boundaries.
2. #81 Add complex-script fixture corpus and witness policy.
3. #82 Model shaped text clusters and multi-scalar ToUnicode data.
4. #83 Add portable Unicode line-break opportunity detection.
5. #84 Add portable bidi paragraph ordering profile.
6. #85 Prototype pure Swift OpenType shaping increments.
7. #86 Emit shaped embedded-font clusters with ToUnicode witnesses.

## Roadmap

```mermaid
flowchart TD
    S0["Phase 0<br/>#80 Standards and boundary<br/>Done"]
    S1["Phase 1<br/>#81 Fixtures and witnesses<br/>Done"]
    S2["Phase 2<br/>#82 Shaped cluster model<br/>Done"]
    S3["Phase 3<br/>#83 Line-break opportunities<br/>Done"]
    S4["Phase 4<br/>#84 Bidi ordering<br/>Done"]
    S5["Phase 5<br/>#85 Pure Swift shaping increments<br/>Done"]
    S6["Phase 6<br/>#86 PDF emission and ToUnicode clusters<br/>Done"]

    S0 --> S1 --> S2 --> S3 --> S4 --> S5 --> S6

    classDef done fill:#e8f5e9,stroke:#2e7d32,color:#111;
    classDef active fill:#e3f2fd,stroke:#1565c0,color:#111;
    classDef review fill:#f3e5f5,stroke:#7b1fa2,color:#111;
    classDef next fill:#fff8e1,stroke:#f9a825,color:#111;
    classDef todo fill:#eef3ff,stroke:#3367d6,color:#111;
    class S0,S1,S2,S3,S4,S5,S6 done;
```

## Witness policy

Every behavior issue in #79 needs evidence that matches the claim:

- qpdf structural validation with no warnings.
- Swift structural checks for object graph, stream, resource, page, font, image,
  and annotation invariants.
- Poppler text extraction for source-faithful text.
- Poppler `pdftotext -tsv` geometry for word and line boxes.
- MuPDF structured text for character quads.
- Poppler and MuPDF raster comparison for ink bounds.
- macOS and Linux verification for the shared renderer.

If a feature cannot meet that witness bar, the implementation must keep it
unsupported and visible rather than claiming support.
