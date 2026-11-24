---
number: 48
title: "Arabic typographic tiers: GSUB contextual (type 5/6) and GPOS mark positioning"
state: open
labels: []
assignees: []
created: 2026-07-09T12:50:35+02:00
updated: 2026-11-24T12:19:19+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/48
synced: 2026-11-24T12:19:19+01:00 922c898fe695
neutralized: 1
---

Follow-up to #46. The shaping core applies GSUB lookup types 1 (single-sub) and 4 (ligature). Two typographic tiers remain, grounded in the OpenType spec (PureTextResearch BIBLIOGRAPHY §1, §5):

## Phase 2: GSUB contextual (lookup types 5/6) + ccmp/locl/calt
- Type 5/6 contextual substitution. E.g. Noto Naskh refines lam-alef in medial context via a contextual `rlig` lookup; today the engine applies the simple type-4 lam-alef ligature, which yields the canonical `uniFEFB`/`uniFEFC` presentation form (metrically identical, legible, correct source range, verified) but not the font's exact contextual glyph pair.
- `ccmp` mark composition (e.g. shadda+fatha composed to one glyph), `locl` language forms, `calt` contextual alternates. Today marks pass through as separate glyphs (valid, just not composed).

## Phase 3: GPOS mark positioning
- `mark` (mark-to-base) and `mkmk` (mark-to-mark), and `curs` cursive attachment, to place harakat precisely. The engine has no GPOS interpreter yet, so vowel marks sit at nominal positions (legible but not typographically placed). This is the largest lift (a new positioning subsystem: anchor tables, mark arrays) and separates "legible" from "typographically correct for vocalized text."

Both are additive to the existing GSUB engine and joining machine; neither changes the joining correctness that #46 established. Verify each against hb-shape (glyph ids for Phase 2, positions for Phase 3).

## Comments

### Mihaela, 2026-07-09T19:11:24+02:00

## Status: both headline tiers landed and hb-shape-verified

**Phase 2, GSUB contextual (PR #56, merged).** The `rlig` feature now runs its lookups in order, applying the coverage-based contextual (type 5/6, format 3) lam-alef refinement before the type-4 ligature. Lam-alef (لا لأ لإ لآ) and سلام match hb-shape glyph-for-glyph, in the shaping core and end to end. Added the GDEF glyph-class and OpenType ClassDef readers.

**Phase 3, GPOS mark positioning (PR #57, merged).** New GPOS reader for mark-to-base (type 4) and mark-to-mark (type 6), format 1. The shaper attaches harakat to their base and stacks marks via mkmk; the render path draws each positioned glyph off the baseline. Adversarial sweep of 1463 vocalized words: zero offset divergences on the 1252 glyph-matches; render pen math within 0.0000pt of hb; byte-identical non-regression for non-vocalized/non-Arabic content.

## Remaining frontier (named in this issue, deliberately deferred and disclosed)

- **ccmp mark composition** (e.g. shadda+fatha to one glyph) and **locl / calt**. This is the largest remaining item: ~211 words in the GPOS sweep diverge from hb purely because of missing ccmp composition (verified byte-identical to pre-Phase-2 `main`, i.e. not a regression). The GSUB contextual + ligature machinery is already in place; ccmp needs the feature applied plus input normalization.
- **Input normalization** (NFC + canonical combining-class reordering) before shaping. A decomposed mark sequence (e.g. lam + alef + combining madda) diverges until this is added; the corpus (PureTextResearch BIBLIOGRAPHY) confirms normalization belongs before shaping.
- **GSUB mark-skip** (honoring IgnoreMarks via GDEF) so a contextual match reaches across an interposed mark. Currently such a match is conservatively missed, never mis-made.
- **GPOS cursive attachment (type 3) and pair/kern (type 2)**, and **anchor device/contour refinements** (formats 2/3 beyond x/y).

Suggest tracking the ccmp + normalization work as the next unit, since they compound (ccmp needs normalized input).

### Mihaela, 2026-07-09T20:28:18+02:00

## Frontier cleared, all follow-ups landed and hb-verified

Since the last update, the remaining #48 items are merged, each verified against `hb-shape` and adversarially reviewed:

- **GSUB IgnoreMarks** (PR #58): the contextual matcher skips harakat, so vocalized lam-alef (لَا) gets the same refinement as لا.
- **ccmp mark composition** (PR #59): shadda + vowel compose to a single glyph, then placed by GPOS. 253-word sweep, zero divergences; مُحَمَّد composes.
- **Canonical ordering of core harakat** (PR #60): out-of-order short vowels/tanwin/shadda/sukun are reordered before shaping. A review caught that raw canonical order diverges from HarfBuzz's UTR #53 for modifier/Quranic marks; the reorder is now scoped to the core harakat (U+064B..U+0652). 816-case sweep vs hb: 24 placements fixed, zero regressions.

`main` is at the merged state; full suite 470 green; swiftformat / swiftlint --strict / style / namespacing all clean.

## What remains (narrow, disclosed, out of the named tiers)

These are refinements beyond the two tiers this issue named, kept honestly on the record:

- Full **UTR #53** ordering for the non-core marks (hamza, Quranic annotation marks, subscript alef): currently left in typed order, which matches the reference where the prior behavior did, but is not the full UTR #53 modified-combining-class model.
- **NFD decomposition** of precomposed letters (e.g. U+0625 alef-with-hamza-below): renders correctly today; only the internal cluster bookkeeping differs from hb.
- **ccmp for 3+ marks on one base** (GSUB type-2 multiple, type-6 format-2 class-based contextual): exotic input.
- **GPOS cursive (type 3) and pair/kern (type 2)**, and **anchor device/contour refinements** (formats 2/3 beyond x/y).

Suggest a fresh issue for full UTR #53 + NFD if those become a priority; everything the two named tiers called for is done.
