## Reference implementations (vendored in `researchcode/`)

Two complete, complementary math engines are vendored. SILE (Lua, MIT) is authoritative for the TeXbook Appendix-G atom-spacing logic and ships a pure-Lua OpenType MATH table reader; Typst (Rust, Apache-2.0) is authoritative for MATH-constant-driven box positioning. Both map onto a pure-Swift box-and-glue layout reading an embedded OpenType MATH font.

SILE - `researchcode/sile/packages/math/`:
- `base-elements.lua` - `spacingRules` (~L316): the COMPLETE TeXbook p.170 inter-atom spacing matrix `[leftAtom][rightAtom] -> {thin|med|thick, notScript}`, with the bin->ord demotion (p.133); `getStandardLength()` (~L1014): thin=3mu, med=4mu plus 2mu minus 4mu, thick=5mu plus 5mu; `mu` = 1/18 em. Port this matrix verbatim.
- `atoms.lua` - `atomType` (the 8 TeXbook atom classes + accents); pair with `unicode-symbols.lua` `operatorDict` for per-symbol atom classification.
- box classes in `base-elements.lua`: `subscript` (~L575, reads `subscriptShiftDown`, `superscriptShiftUp{Cramped}`, `subSuperscriptGapMin`, ...), `underOver` (~L723, big-op limits + stretchy), `fraction` (~L1311, `axisHeight`, `fractionRuleThickness`, gap-mins).
- `researchcode/sile/core/opentype-parser.lua` - `parseMath`/`parseMathVariants`/`parseMathKern` (~L590+): a COMPLETE pure-Lua OpenType MATH table reader (MathConstants, MathValueRecord value+deviceOffset, GlyphAssembly). Closest analog for the Swift MATH reader over the embedded font.
- `texlike.lua` - `mathGrammar` (~L15, epnf/lpeg PEG) + `registerCommand`/`isMoveableLimitsOrAlwaysStacked`: the TeX-subset parser mapping `\frac`, `^`, `_`, `'`->`\prime` into the element tree.

Typst - `researchcode/typst/crates/typst-layout/src/math/`:
- `fragment/glyph.rs` - `assemble()` (~L572) + `ttf_parser::math` lookups (`italics_correction` ~L472, `kern_at_height` ~L505, `glyph_construction` ~L555): stretchy delimiter/radical construction from `GlyphAssembly` parts with `min_connector_overlap`.
- `scripts.rs` - `compute_script_shifts` (~L308) + `compute_limit_shifts` (~L290): MATH-constant-driven sub/superscript and big-op limit positioning.
- `fraction.rs` (`layout_fraction` ~L13) and `radical.rs` (`layout_radical` ~L20): exact gap/shift/rule-thickness formulas from MATH constants (display vs text).
- Note: the vendored typst ships only `typst-layout`/`typst-pdf`; the math IR + the precomputed `font.math()` constants struct live in the un-vendored `typst-library`, so typst's spacing-resolution table is absent. SILE is the authoritative vendored source for Appendix-G spacing; typst for MATH-constant box positioning.

Swift mapping: MATH reader modeled on SILE `parseMath`; inter-atom spacing from SILE's `spacingRules` + glue model; vertical positioning (fractions, radicals, scripts, stretchy assembly) from typst's formulas; atom classification from SILE `atoms.lua` + `operatorDict`; parser a small PEG mirroring `texlike.lua`.

Spec anchors: TeXbook Appendix G (+ p.170 spacing, p.130/p.133 rules), Vieth "OpenType math illuminated", OpenType MATH table spec, MathML Core, Knuth-Plass.
