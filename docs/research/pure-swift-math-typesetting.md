# Pure-Swift math typesetting (TeX-math subset)

Date: 2026-06-02. Issue #131.

Scope: this note defines how MarkdownPDF can render a TeX-math subset, inline
`$...$` and display `$$...$$`, as PDF text operators plus rule (line/box)
drawing, with no external math engine. It is portable macOS and Linux research.
It is not an implementation promise: source, fixtures, and witnesses must exist
before any support is claimed.

## Implementation status

The first portable product slice is implemented as an opt-in feature through
`PDFOptions.MathTypesetting`. The default remains disabled so CommonMark dollar
text stays literal. When enabled, MarkdownPDF parses inline `$...$` and display
`$$...$$` math with a Pure Swift scanner. Supported inline formulas render as
positioned PDF text, with fraction and radical constructs linearized when they
cannot be overlaid inside the current line wrapper. Supported display formulas
render as PDF text plus filled rule rectangles. Unsupported input renders its
original source visibly. The witnessed subset covers superscripts, subscripts,
fractions, radicals, big operators with display limits, Greek command names, and
common ASCII-safe symbols. Display math wraps the visual operators in PDF
ActualText so `pdftotext` can extract the deterministic linearized formula.

The internal TrueType parser can now read OpenType `MATH` table metadata when
that parsing is explicitly requested: math constants, per-glyph value records,
extended-shape coverage, math kerns, variants, glyph constructions, and glyph
assembly parts. The reader validates subtable offsets, coverage counts, and
glyph IDs with synthetic font fixtures so the public repo still commits no font
binaries. MATH parsing remains opt in because existing embedded-font rendering
can subset fonts before math metrics are needed. Display math now consumes MATH
constants from the styled embedded font role when they are present. The default
math mode still allows base-font fallback for compatibility, while
`PDFOptions.MathTypesetting.fontBacked` requires the styled math role to use an
embedded OpenType font with a `MATH` table. The renderer still does not assemble
stretchy glyph variants. Inline math still uses the text-run path and only
validates the font-backed profile, so full font-driven inline boxes remain a
future implementation gate. Current fallback rendering intentionally uses
ASCII-safe names for Greek commands so the base-font path remains extractable
and Linux-buildable.

The math layout engine now has an internal metrics bridge that can consume scaled
OpenType `MATH` constants when they are explicitly supplied. The default metrics
preserve the current base-font geometry. This remains a staging step toward
font-driven Appendix-G layout rather than a production math font claim.

Display math asks the embedded-font catalog to parse OpenType `MATH` tables only
when math typesetting is enabled, and only display layout consumes those
metrics. Inline math still uses text-run linearization, stretchy variants and
assembly are not used, and malformed optional `MATH` data is still ignored when
math parsing is disabled.

## Product boundary

Hard constraints, restated so they cannot drift:

- Pure Swift. Linux and macOS buildable. PDF bytes are generated directly.
- No LaTeX, no TeX binary, no MathJax, KaTeX, browser, JavaScript, Python,
  shell, HarfBuzz, or any C library in the production path. Cited engines are
  STUDY references only; their algorithms are reused as design vocabulary, not
  imported, linked, vendored, or shelled out to.
- Math glyphs come from an OpenType font with a `MATH` table, supplied through
  the existing opt-in embedded-font path. The repository commits no font
  binaries; tests use an env/CI-provided open math font (see Platform notes).
- Unsupported math input must throw a typed error or render visible fallback,
  never a silent quality claim.

What this profile does NOT claim: full LaTeX macro expansion, `\newcommand`,
amsmath environments (`align`, `cases`, `matrix` beyond a minimal subset),
arbitrary packages, color/style packages, or automatic line breaking of long
display equations. Those remain unsupported until separately witnessed.

## Standards and sources

The geometry of math layout is fully specified by two bodies of work: Knuth's
TeX rules (the algorithm) and the OpenType `MATH` table (the font data the
algorithm consumes). Both are needed.

Knuth, *The TeXbook*, Appendix G "Generating boxes from formulas" defines the
canonical positioning rules: the eight math styles (display, text, script,
scriptscript, each cramped/uncramped), script shift-up/down, fraction and
radical construction, big-operator limits, and the inter-atom spacing table by
math class (Ord, Op, Bin, Rel, Open, Close, Punct, Inner). Authoritative scan:

  https://visualmatheditor.equatheque.net/doc/texbook.pdf

Jackowski, "Appendix G Illuminated" (TUGboat) renders the Appendix G parameter
relations as diagrams; the most readable bridge from prose to implementation:

  https://www.tug.org/tugboat/tb27-1/jackowski.pdf

Vieth, "OpenType math illuminated" (TUGboat 30:1, 2009) maps the TeX
`\fontdimen` parameters used by Appendix G onto OpenType `MATH` constants. This is
the key that lets an Appendix-G algorithm read a modern font:

  https://www.tug.org/tugboat/tb30-1/tb94vieth.pdf

Knuth & Plass, "Breaking paragraphs into lines" (Software: Practice and
Experience 11:11, 1981) defines the box/glue/penalty model and the optimal-fit
dynamic program. We reuse its box-and-glue vocabulary for inline math runs and
for the surrounding paragraph; full formula breaking is out of scope for v1.

  http://www.eprg.org/G53DOC/pdfs/knuth-plass-breaking.pdf
  https://onlinelibrary.wiley.com/doi/abs/10.1002/spe.4380111102

OpenType `MATH` table specification (Microsoft Typography, OpenType 1.9.1): the
production source of math constants, italic correction, math kerning, glyph
variants, and glyph assembly. This is the table we parse from the embedded font:

  https://learn.microsoft.com/en-us/typography/opentype/spec/math

MathML Core (W3C Candidate Recommendation) is the structural model: a clean tree
of `mrow`, `msub`, `msup`, `mfrac`, `msqrt`, `mroot`, `mo`, `mi`, `mn`, `munder`,
`mover`, `munderover`. We use it as the shape of our internal box tree and as a
cross-check vocabulary, not as a parsed input format:

  https://www.w3.org/TR/mathml-core/

## The model: box-and-glue from an Appendix G subset reading the MATH table

Math layout is recursive over a tree, exactly as the `MATH` overview and MathML
describe: child boxes are laid out first, then composed into the parent. The
internal representation is a box tree with three node kinds borrowed from
Knuth-Plass: glyph boxes (width/height/depth + glyph id), rule boxes (filled
rectangles: fraction bars, radical rules, overlines), and glue (math spacing).
Composition rules come from Appendix G; the numeric parameters come from the
`MATH` table.

Concrete parameter mapping (Appendix G `\fontdimen` -> OpenType `MATH`), per
Vieth and the MS spec:

- Math axis: `axisHeight`. Fraction bars, big operators, and minus signs sit on
  the axis, not the baseline.
- Script scaling: `scriptPercentScaleDown` (80%) and
  `scriptScriptPercentScaleDown` (60%) select the size for each math style.
- Superscript/subscript: `superscriptShiftUp`, `superscriptShiftUpCramped`,
  `subscriptShiftDown`, `subSuperscriptGapMin`, `superscriptBottomMin`,
  `subscriptTopMax`, plus per-glyph `MathItalicsCorrection` and `MathKern`
  (top-right/bottom-right corners) for horizontal placement.
- Fractions: `fractionNumeratorShiftUp` / `fractionDenominatorShiftDown` (with
  display-style variants), `fractionNumeratorGapMin`, `fractionDenominatorGapMin`,
  `fractionRuleThickness`.
- Radicals: `radicalVerticalGap` (and display variant), `radicalRuleThickness`,
  `radicalExtraAscender`, `radicalKernBeforeDegree`, `radicalKernAfterDegree`,
  `radicalDegreeBottomRaisePercent`.
- Big operators with limits: `displayOperatorMinHeight` selects the large glyph
  variant; `upperLimitGapMin`, `lowerLimitGapMin`, `upperLimitBaselineRiseMin`,
  `lowerLimitBaselineDropMin` position limits in display style; inline uses
  sub/superscript placement instead.
- Stretchy delimiters and radical signs: `MathVariants` provides ready-made size
  variants (`MathGlyphVariantRecord`) and, when none is tall enough,
  `GlyphAssembly` parts with `minConnectorOverlap` for piecewise construction.
- Inter-atom spacing: Appendix G's class-pair table (thin/medium/thick mu-glue,
  suppressed in script styles) drives the glue inserted between Ord/Op/Bin/Rel/
  Open/Close/Punct/Inner atoms.

Rule thickness, where the font has no explicit value, falls back to a minus-sign
or `OS/2.yStrikeoutSize`-like value, as the spec recommends.

## How-to: parse, lay out, emit

1. Tokenize the math substring: identifiers, numbers, operators, `^`, `_`, `{}`,
   `\frac`, `\sqrt`, `\sum`/`\int`/`\prod`, `\left`/`\right`, and a Greek +
   symbol table mapping control words (`\alpha`, `\leq`, `\rightarrow`, ...) to
   Unicode scalars (the Math Alphanumeric and math-operator blocks).
2. Parse to a box tree shaped like MathML Core nodes. Assign each atom a math
   class for spacing. Reject unknown control words with a typed error.
3. Resolve glyphs through the embedded font's `cmap`; apply `ssty` for
   script-style alternates and `dtls` for dotless i/j under accents where the
   font provides them (optional, feature-flagged).
4. Lay out recursively per the parameter mapping above, producing absolute x/y
   offsets, advances, and a list of rule rectangles. Track height/depth so the
   inline result can be a single box with correct metrics for the paragraph.
5. Emit PDF: glyphs via existing Type0/CIDFontType2 text operators (`Tf`, `Td`,
   `Tj`) at the computed positions; rules via `re`/`f` filled rectangles in the
   content stream. Reuse the existing embedded-font subsetter and `ToUnicode`
   machinery so math glyphs round-trip on extraction.
6. Linearize for text extraction: emit a readable plain-text form alongside the
   visual glyphs (e.g. `x^2 + sqrt(a)` or a Unicode-math approximation) via the
   `ToUnicode` map and the text-extraction layer, so `pdftotext` yields sensible
   output rather than scrambled glyph soup.

## Reference implementations (study only; note license each)

- KaTeX (MIT) - synchronous TeX->box layout, explicitly modeled on Appendix G;
  its `buildHTML`/`buildCommon` box construction and `fontMetrics` tables are the
  clearest readable map of the rules. https://github.com/KaTeX/KaTeX
- MathJax (Apache-2.0) - TeX input is converted to an internal MathML tree, then
  laid out; useful as a MathML-Core-aligned structural reference.
  https://docs.mathjax.org/en/latest/input/tex/index.html
- Typst math (Apache-2.0) - a modern engine that reads OpenType `MATH` directly
  (italic correction, `MathKern`, accents, variants/assembly); the closest match
  to our font-data approach. https://github.com/typst/typst
- LuaTeX / XeTeX - LuaTeX implements full OpenType math; XeTeX uses a subset of
  `MATH` parameters. Background on the param mapping in Vieth (above).
- blahtexml (BSD-style, see repo) - TeX-subset -> MathML converter; a useful
  reference for a conservative, well-scoped grammar.
  https://github.com/gvanas/blahtexml
- iosMath (MIT) and SwiftMath (MIT) - existing Swift/ObjC TeX-math layout. They
  implement Appendix-G-style positioning but render via CoreText/CoreGraphics on
  Apple platforms, so the LAYOUT logic is reusable as a study reference while the
  rendering backend is not portable. https://github.com/kostub/iosMath and
  https://github.com/mgriebling/SwiftMath

## Math fonts that ship OpenType MATH (open licenses)

The embedded font is caller/CI supplied; none are committed. Candidates:

- STIX Two Math - SIL Open Font License 1.1. Broad coverage, reference-quality
  `MATH` table. https://github.com/stipub/stixfonts
- Latin Modern Math - GUST Font License (free, legally equivalent to LPPL
  1.3c). Computer Modern look. https://www.gust.org.pl/projects/e-foundry/lm-math
- XITS / STIX - SIL OFL 1.1. https://github.com/aliftype/xits
- Asana Math - first free OpenType math font; OFL. https://ctan.org/pkg/asana-math
- TeX Gyre math fonts (Pagella, Termes, Bonum, Schola, ...) - GUST Font License
  (LPPL-equivalent). https://www.gust.org.pl/projects/e-foundry/tg-math

License note: OFL and GUST/LPPL both permit redistribution and embedding; CI may
install any of them. Record the chosen font's license alongside the fixture.

## Witness policy

Each claimed math feature needs evidence matching the claim, consistent with the
repo's existing bar:

- qpdf structural validation, no warnings, on every generated math PDF.
- Swift structural checks: content stream operators well-formed, font/resource
  invariants, rule rectangles inside page box.
- Poppler `pdftotext` for the linearized text form (source-faithful extraction).
- Poppler `pdftotext -tsv` and MuPDF structured text for glyph/box geometry:
  no overlapping quads, fraction bar between numerator and denominator, radical
  rule above its radicand, limits above/below operators in display style.
- Poppler and MuPDF raster comparison against a checked-in expected image for a
  small fixture set (e.g. `x^2`, `\frac{a}{b}`, `\sqrt{x+1}`, `\sum_{i=1}^n i`).
- Both macOS and Linux must pass for any shared-renderer claim.

Features that cannot meet this bar stay unsupported and visible.

## Ordered work

1. #131a Doc and grammar boundary: define the exact supported subset, math-class
   table, and symbol/Greek mapping. No renderer code.
2. #131b OpenType `MATH` table reader (constants, italic correction, math kern,
   variants, assembly) with synthetic font unit tests. This internal parser
   slice is implemented; renderer consumption of the metrics remains separate.
3. #131c Box tree + Appendix G subset layout (styles, scripts, fractions,
   radicals) producing geometry, no PDF yet. The internal MATH-constant metrics
   bridge for fractions, scripts, radicals, and display limits is implemented,
   and display math now consumes those metrics from embedded fonts when math
   typesetting is enabled. The strict font-backed profile now rejects math
   rendering without an embedded OpenType `MATH` table. Full font-driven inline
   box construction remains separate.
4. #131d Big operators with limits, stretchy delimiters via variants/assembly.
5. #131e PDF emission (text + rule rectangles) reusing the embedded-font path.
6. #131f Text linearization + `ToUnicode` for extraction.
7. #131g Witness suite (qpdf, Poppler, MuPDF, raster) on macOS and Linux.

## Platform notes

The layout core is pure Swift and Linux-buildable: it depends only on the
embedded font bytes and on the existing portable PDF writer. It must not depend
on CoreText, CoreGraphics, PDFKit, WebKit, or any C math/PDF library. A future
macOS adapter could compare measurements against CoreText for confidence, but
that is outside the shared renderer and macOS results never imply Linux behavior.
The math font is provided via env var / CI install (mirroring the existing
embedded-font fixture policy); the repo commits no font binaries, and each
fixture records the font name and license used.


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
