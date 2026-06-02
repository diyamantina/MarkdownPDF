# Issue 122 source references

Staged source and reference materials gathered for issue #122, vendored study-only under `researchcode/`.

## Reference implementations (vendored in `researchcode/`)

Study-only (reimplement in the pure-Swift embedded-font + shaped-cluster path; no HarfBuzz/ICU dependency).

HarfBuzz (C++, "Old MIT" permissive):
- `researchcode/harfbuzz/src/hb-ot-shape.cc` - `hb_ot_position_plan` / `_hb_ot_shape_fallback_mark_position` (~L1029, L1089) + the `plan.fallback_mark_positioning` flag (~L206): the GPOS-or-fallback decision for combining diacritics. Mirror this two-branch logic: use embedded-font GPOS mark-to-base when present, else zero-advance stack the mark over the base.
- `researchcode/harfbuzz/src/hb-buffer.cc` - `merge_clusters_impl` (~L547, MIN-cluster + monotone extend) and `hb_buffer_set_cluster_level` (~L1245): the cluster model that keeps source scalars attached to ligated glyph runs. Source-of-truth for emitting a correct multi-scalar ToUnicode CMap.
- `researchcode/harfbuzz/src/hb-font.cc` - `hb_font_get_nominal_glyph(s)_default` (~L152/168), `hb_font_get_variation_glyph_default` (~L208), `hb_font_get_glyph_h_advance_default` (~L229): the consumer contract our cmap-format-4/12 parser must satisfy (BMP via fmt 4, CJK supra-BMP via fmt 12, fullwidth h-advance for ideographs).

Pango (C, LGPL - reference only, do not copy):
- `researchcode/pango/pango/shape.c` - `pango_hb_shape` writing `log_clusters` + `is_cluster_start` (~L419-532): the cluster-to-source-char back-mapping for ToUnicode; `pango_hb_font_get_nominal_glyph` (~L88) cmap callback.
- `researchcode/pango/tests/LineBreakTest.txt` + `researchcode/pango/tests/validate-log-attrs.c`: the official Unicode UAX#14 conformance vectors and a per-rule (LB2-LB12) validator. Use as the test suite for the pure-Swift CJK ID-class breaker.
- `researchcode/pango/pango/pango-layout.c` - `can_break_at` / `process_line` (~L3551, L4471): how computed `is_line_break` attrs drive greedy wrapping; for CJK every ID-class ideograph is a break opportunity on both sides.
- `researchcode/pango/pango/fonts.c` (~L2999, `g_unichar_iswide`, UAX#11): East Asian Width source for fullwidth metrics (advance = em for W/F class).

skia (C++, BSD-3) - the multi-scalar ToUnicode path, gold for diacritics/CJK:
- `researchcode/skia/src/pdf/SkClusterator.cpp` - `next()` (~L43): groups glyphs sharing a cluster id, finds each cluster's UTF-8 byte span. The primitive that preserves source scalars across many-to-one (ligature) and one-to-many (decomposition) mappings. `is_reversed()` (~L15) detects RTL runs.
- `researchcode/skia/src/pdf/SkPDFDevice.cpp` (~L1018-1063): clusters drive ToUnicode - single-glyph-single-codepoint needs nothing; missing codepoint records multi-scalar source into `glyphToUnicodeEx[gid]`; true many-glyph falls back to `/Span<</ActualText utf16>>BDC`.
- `researchcode/skia/src/pdf/SkPDFMakeToUnicodeCmap.cpp` - `SkPDFAppendCmapSections` (~L207, bfchar/bfrange coalescing with the high-byte guard) + `append_bfchar_section_ex` (~L113, multi-scalar UTF-16BE targets, written before bfrange). Exact CMap writer for diacritic/CJK round-trip.

To-vendor (see #137): `unicode-linebreak` (Rust, Apache-2.0) `src/lib.rs` for the actual UAX#14 ID-class rule engine.

Spec anchors: Unicode UAX #14 (ID class), UAX #11 (East Asian Width), UAX #15 (normalization), OpenType cmap (fmt 4/12) + GPOS mark attachment.
