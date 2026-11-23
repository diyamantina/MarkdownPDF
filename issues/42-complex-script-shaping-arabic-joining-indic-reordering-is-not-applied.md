---
number: 42
title: "Complex-script shaping (Arabic joining, Indic reordering) is not applied; Arabic renders in isolated forms"
state: closed
labels: []
assignees: []
created: 2026-07-09T10:35:41+02:00
updated: 2026-07-09T14:10:12+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/42
synced: 2026-07-09T14:10:12+02:00 2ecac75056d9
neutralized: 1
---

Under an embedded font that covers Arabic (e.g. Arial), Arabic text renders but is **not shaped**: letters appear in isolated forms instead of contextually joined initial/medial/final forms, so a word like `العربية` shows as disconnected glyphs rather than connected script. The render does not abort (it succeeds), but the output is incorrect for a native reader. The same applies to other complex scripts that require shaping (Indic conjuncts and matra reordering, etc.).

The current shaper (`OpenTypeShaper`) implements only the Latin GSUB ligature increment; `requiresExplicitShapingSupport` throws `unsupportedComplexScriptScalar` for some blocks (Syriac, Thaana, Indic, Thai, Khmer, Hebrew/Arabic presentation forms) but the main Arabic block (U+0600–U+06FF) falls through and renders unshaped. `BidiParagraphOrdering` handles RTL run ordering but not glyph joining.

## Scope / options
- Minimum: make the behavior consistent and honest, e.g. treat the main Arabic block like the other complex scripts (explicit `unsupportedComplexScriptScalar`) so callers get a clear signal instead of silently-wrong output; document the limitation.
- Full: implement Arabic joining (GSUB `init`/`medi`/`fina`/`isol` + `rlig`/`mark`) and, longer term, Indic reordering, to render these scripts correctly.

Severity: correctness for complex scripts. Not a diacritics issue (Latin, Greek, Cyrillic render correctly); tracked because the current path produces visibly wrong Arabic rather than a clear refusal.

## Comments

### Mihaela, 2026-07-09T10:55:13+02:00

Grounded in the MarkdownPDFResearch corpus (harfbuzz pipeline files, typst, fribidi/unicode-bidi, pango, sile). Note: the corpus has only harfbuzz's pipeline files (`hb-ot-shape.cc`, `hb-buffer.cc`, `hb-font.cc`, `hb-shape.cc`); the Arabic shaper proper (`hb-ot-shaper-arabic*.{cc,hh}`) is upstream, not vendored. That absence is itself a signal: Arabic joining is a self-contained ~1,000-line module, not something threaded through the whole engine.

## The key insight (scoping)
`init`/`medi`/`fina`/`isol` are ordinary GSUB single-substitution lookups. This engine already runs GSUB (for Latin `rlig`) and already has `BidiParagraphOrdering` for RTL run ordering. So Arabic joining is not a new substitution engine, it is a state machine that decides *which of four features to enable per glyph* before the existing GSUB apply step, plus the bidi/segmentation prerequisites.

## Pipeline (bidi MUST precede shaping)
1. Bidi resolution → per-character embedding levels (fribidi `fribidi-bidi.c:517`; unicode-bidi `prepare.rs:54`). Reverse RTL runs to logical processing order.
2. Script + direction run segmentation → runs uniform in (script, level, font) (typst `shaping.rs:717-778` is the cleanest ~50-line template; pango itemization; sile `bidi/init.lua`).
3. Shaping per run: the Arabic joining state machine sets `init/medi/fina/isol` masks (harfbuzz `setup_masks` hook, `hb-ot-shape.cc:757-765`), then the existing GSUB apply consumes them (`hb-ot-shape.cc:264-267`), then GPOS (`:271-275`).
4. Positioning/assembly; RTL runs laid right-to-left.

## Joining state machine
Per-codepoint joining type: D (dual), R (right), L (left), C (join-causing, e.g. tatweel/ZWJ), T (transparent, combining marks, skipped when computing neighbors), U (non-joining). Walk the run in logical order tracking the previous non-transparent letter; a small transition table keyed by (state, joining type) assigns each letter its positional form (isol/init/medi/fina). Transparent marks pass through.

cmap must map Arabic BASE codepoints (U+0621–U+064A), NOT the legacy Presentation Forms blocks (U+FE70+/U+FB50+); GSUB then selects the positional glyph.

## Minimal GSUB feature order for Arabic
`ccmp` → `locl` → `isol`/`init`/`medi`/`fina` (masked per glyph) → `rlig` (mandatory: lam-alef) → `calt`. Then GPOS `mark`/`mkmk` for vowel marks.

## Phasing
- **Phase 0 (prerequisite, unavoidable):** real-ish bidi (levels + RTL reversal) and script/direction segmentation. The engine has RTL ordering already; needs level assignment and script runs. Reference: unicode-bidi (portable) or fribidi.
- **Phase 1 (MINIMUM VIABLE, "legible Arabic"):** codepoint→joining-type table (~200 Arabic-block entries), the joining state machine (~150–250 lines) setting init/medi/fina/isol flags, fed into the existing GSUB apply, plus `rlig` for lam-alef. Result: correctly *joined* Arabic on any standard Arabic font. **This is the 80/20 win; no GPOS needed.**
- **Phase 2 (fast-follow):** enable `ccmp`/`locl`/`calt` (more of the same GSUB apply).
- **Phase 3 (separate, larger milestone, "fully correct"):** GPOS mark positioning (`mark`/`mkmk`/`curs`). The engine has NO GPOS engine today; building anchor/mark-array support is comparable in size to the existing GSUB engine. This is what separates "legible" from "typographically correct for vocalized text."

## Recommendation
Split this issue: keep #42 for **Phase 0 + Phase 1** (legible joined Arabic) and open a separate GPOS milestone for Phase 3. Phase 1 depends on #41 (embed a `.ttc`/single-face Arabic font) and #43 (Apple-font checksum tolerance) to actually reach a font with the joining lookups.

Citations: harfbuzz `hb-ot-shape.cc:757-765, 264-275, 196, 636-643, 1171-1202`; typst `typst-layout/src/inline/shaping.rs:717-778, 959-1005`; pango `pango/shape.c:403-418, 512`; bidi `fribidi/lib/fribidi-bidi.c:517`, `unicode-bidi/src/prepare.rs:54`, `sile/packages/bidi/init.lua`. Arabic joining table/state machine/features are upstream harfbuzz `hb-ot-shaper-arabic*.{cc,hh}` (not in corpus).

### Mihaela, 2026-07-09T12:50:36+02:00

Phase 1 (the shaping core: joining algorithm + GSUB positional forms, oracle-verified against hb-shape) merged in #46. Arabic now joins correctly at the shaping level. This issue stays open until the render-path integration lands (routing + RTL + ToUnicode), which is what makes Arabic actually draw joined in a PDF. Remaining work split into: render integration (the blocking piece) and the contextual/GPOS typographic tiers. Joining data is byte-authoritative against Unicode ArabicShaping 17.0.0; implementation is clean-room per the PureTextResearch boundary (Unicode UCD + OpenType GSUB spec, hb-shape as oracle only).

### Mihaela, 2026-07-09T14:10:12+02:00

Render-path integration merged in #51: Arabic now draws joined and RTL-correct in a PDF with recoverable ToUnicode, verified against hb-shape (drawn CIDs == visual order) and confirmed byte-identical for Hebrew/Latin/mixed-bidi. The joining core (#46) plus this integration close the user-visible symptom of #42. Remaining Arabic refinements are separate: type-5/6 contextual + GPOS marks (#48), mixed Arabic+Latin (#50). Closing #42.
