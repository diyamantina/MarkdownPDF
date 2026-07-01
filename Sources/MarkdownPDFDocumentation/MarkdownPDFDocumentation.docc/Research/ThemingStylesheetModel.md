# Theming and stylesheet model

Date: 2026-06-02

Issue: #130

Scope: this note defines a portable theming / stylesheet model for the
Markdown-to-PDF engine. It covers per-element typography, color, and spacing, a
dark theme and a print theme, and a code-syntax theme surface that feeds the
#120 syntax-color work. It is portable macOS and Linux research. It is design
direction plus the #130 implementation record once Swift source and witnesses
exist.

## Product boundary

Production MarkdownPDF must stay Pure Swift, generate PDF bytes directly, and
build on macOS and Linux. The theming model must not introduce a CSS engine, a
browser, WebKit, JavaScript, Python, LaTeX, ConTeXt, shell renderers, C Markdown
or PDF libraries, or Apple-only APIs. Colors are DeviceRGB only, matching the
existing `PDFColor` (three `Double` channels). The systems cited below are design
STUDY references for vocabulary and structure, not dependencies and not runtime
inputs. iOS support is not implied.

Cited-system licenses (study only, nothing linked or vendored):

- Typst compiler: Apache-2.0.
- Pandoc: GPL-2.0-or-later. Docs studied; no code reused.
- LaTeX kernel / clsguide: LPPL. ConTeXt: GPL.
- W3C specs (Paged Media, Color 4, Fonts 4): W3C Document/Software License.
- W3C DTCG Design Tokens Format: W3C Community Contributor License.
- WCAG / WAI Understanding docs: W3C Document License. APCA/SAPC: Apache-2.0,
  with a separate patent/trademark notice; we study the concept, not the code.
- base16: MIT-style architecture spec. Pygments: BSD-2-Clause. highlight.js:
  BSD-3-Clause. TextMate/VS Code themes: data formats, not linked code.

## Standards and sources

| Source | Observation | MarkdownPDF impact |
|---|---|---|
| Typst styling, set/show rules. <https://typst.app/docs/reference/styling/> | Two-layer model: `set` configures default properties of an element; `show` (and show-set) re-targets or rewrites an element's appearance via selectors. Rules are lexically scoped. | Model a theme as defaults per element (set) plus optional per-element overrides keyed by element role (show-set), resolved at build time. No rule language needed. |
| Pandoc templates and variables. <https://pandoc.org/MANUAL.html> | Output styling is driven by named metadata variables substituted into a template (fontsize, mainfont, geometry, colorlinks, linkcolor). | Confirms a flat, named-variable theme surface is enough for document-level knobs (page, base font, link color); keep ours typed, not string-templated. |
| LaTeX2e for class and package writers (clsguide). <https://mirror.gutenberg-asso.fr/tex.loria.fr/general/new/clsguide.html> | A document class fixes design (margins, sectional fonts, spacing) separately from content; classes either stand alone or extend a base. | Built-in themes (`default`, `dark`, `print`) are our "classes": each a complete design; user themes extend a base by overriding fields. |
| CSS Paged Media Module Level 3. <https://www.w3.org/TR/css-page-3/> | Defines the page box, margins, size/orientation, and running headers/footers as the print-formatting vocabulary. | Theme owns page-level geometry vocabulary (already in `PDFOptions.PageSize`/`Margins`); print theme can constrain these. Conceptual only. |
| CSS Color Module Level 4. <https://www.w3.org/TR/css-color-4/> | Canonical color vocabulary: sRGB/hex, named, plus wide-gamut spaces; defines interpolation and gamut mapping. | We deliberately restrict to sRGB/DeviceRGB. Use the spec as the naming/contrast reference, not for P3/Lab/Oklch. |
| CSS Fonts Module Level 4. <https://www.w3.org/TR/css-fonts-4/> | Font selection as family + weight + width + slope; family resolves to a face. | Theme typography fields map to our `StandardFont`/`FontSet` selection, not to a CSS font-matching algorithm. |
| W3C Design Tokens Format Module (stable 2025.10). <https://www.designtokens.org/tr/drafts/format/> | JSON tokens with `$type`/`$value`, groups, aliases/references, and theming for light/dark and accessibility variants. | Adopt the token CONCEPT (named, typed, referenceable values; one base, theme overrides) as the schema shape for a future serializable theme. Keep our in-memory model a Swift value type first. |
| DTCG group, first stable announcement. <https://www.w3.org/community/design-tokens/> | Vendor-neutral exchange format; multiple tools implement it. | If we ever serialize themes, target a DTCG-shaped JSON subset rather than inventing one. |
| WCAG 2.1 SC 1.4.3 Contrast (Minimum). <https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html> | Requires >=4.5:1 for body text, >=3:1 for large text (>=18pt, or >=14pt bold); AAA is 7:1 / 4.5:1. | Every built-in theme's text-on-background pairs must pass 4.5:1; assert it in tests. |
| WebAIM contrast reference. <https://webaim.org/articles/contrast/> | States the relative-luminance contrast formula `(L1+0.05)/(L2+0.05)` with the sRGB linearization. | Implement this exactly in a pure-Swift `contrastRatio` helper for witnesses. |
| APCA (SAPC-APCA). <https://github.com/Myndex/SAPC-APCA> and <https://git.apcacontrast.com/documentation/WhyAPCA.html> | Perceptually uniform, size/weight-aware, polarity-sensitive; targeted at WCAG 3, not yet a replacement. | Note as a future-facing alternative metric; keep WCAG 2.x as the gate for now. Record APCA as a planned secondary check. |
| Pygments token taxonomy. <https://pygments.org/docs/tokens/> and styles. <https://pygments.org/docs/styles/> | Hierarchical token kinds (Keyword, Name, String, Number, Comment, Operator...); a Style is a dict from token type to color/weight, subtypes inherit. | The code-syntax theme exposes closed color slots matching our #120 tokenizer kinds, with deterministic fallback through the renderer. |
| TextMate/VS Code theme model. <https://code.visualstudio.com/api/language-extensions/syntax-highlight-guide> and <https://code.visualstudio.com/api/extension-guides/color-theme> | `tokenColors`: rules of (scope selector -> foreground + fontStyle); most specific scope wins. | Confirms selector->style with specificity. We use a small closed enum of kinds instead of open dotted scopes, so resolution is total and deterministic. |
| base16 architecture and styling. <https://github.com/tinted-theming/home> and <https://github.com/Misterio77/base16/blob/main/styling.md> | 16 colors: base00-07 grayscale ramp (bg->fg), base08-0F accent hues for types/operators/names; dark vs light just reverses the ramp direction. | Adopt base16 as the canonical 16-slot palette shape. Dark theme = reverse the base00-07 ramp; accent slots map to syntax kinds. Lets one palette drive both UI and code colors. |
| highlight.js scope/theme reference. <https://highlightjs.readthedocs.io/en/latest/css-classes-reference.html> | A theme is a flat stylesheet over a fixed closed set of scope classes (keyword, string, comment...). | Validates a fixed, closed token-kind set as a stable theming surface (easier to make total than open scopes). |

## Model

A theme is a Swift value type resolved entirely at build time into the colors,
fonts, sizes, and spacing the existing renderer already consumes. No rule
interpreter, no string templating, no runtime CSS.

Three layers, mirroring Typst set/show and LaTeX class/extension:

1. Palette: a base16-shaped set of DeviceRGB colors (grayscale ramp + accents).
2. Element styles: per-element typography/color/spacing defaults (the "set"
   layer), keyed by a closed `ElementRole` enum.
3. Code-syntax styles: a closed set of token color slots matching the #120
   tokenizer kinds (the TextMate/Pygments/base16 "tokenColors" surface).

Resolution is total: every `ElementRole` and every code token slot has a
resolved style, falling back to the body style or palette so no element can be
unstyled.

## How to (Swift)

The current `PDFColor` is exactly DeviceRGB, so it is the palette primitive.
`PDFOptions` is the public, `Equatable`/`Sendable`, all-defaulted config struct,
so a `theme` field slots in without breaking callers.

```swift
public struct PDFColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
}

extension PDFOptions {
    public struct Palette: Equatable, Sendable {
        public var base00, base01, base02, base03: PDFColor
        public var base04, base05, base06, base07: PDFColor
        public var base08, base09, base0A, base0B: PDFColor
        public var base0C, base0D, base0E, base0F: PDFColor
        public var foreground: PDFColor { base07 }
        public var background: PDFColor { base00 }
    }

    public enum ElementRole: CaseIterable, Hashable, Sendable {
        case body, paragraph
        case heading1, heading2, heading3, heading4, heading5, heading6
        case blockQuote, list, listMarker, link
        case inlineCode, codeBlock, tableHeader, tableCell
        case thematicBreak, footnote, html, imagePlaceholder
    }

    public enum FontRole: Equatable, Sendable {
        case regular, bold, italic, monospaced
    }

    public struct ElementStyle: Equatable, Sendable {
        public var fontRole: FontRole
        public var sizeMultiplier: Double
        public var lineHeightMultiplier: Double
        public var color: PDFColor
        public var backgroundColor: PDFColor?
        public var borderColor: PDFColor?
        public var underline: Bool
        public var spacingBeforeMultiplier: Double
        public var spacingAfterMultiplier: Double
    }
}

extension PDFOptions {
    public struct CodeSyntaxTheme: Equatable, Sendable {
        public var text: PDFColor
        public var keyword: PDFColor
        public var identifier: PDFColor
        public var string: PDFColor
        public var number: PDFColor
        public var comment: PDFColor
        public var operatorToken: PDFColor
        public var punctuation: PDFColor
        public var error: PDFColor
    }
}

extension PDFOptions {
    public struct Theme: Equatable, Sendable {
        public var palette: Palette
        public var pageBackground: PDFColor?
        public var elements: [ElementRole: ElementStyle]
        public var codeSyntax: CodeSyntaxTheme
        public func style(for role: ElementRole) -> ElementStyle {
            elements[role] ?? elements[.body]!
        }
    }
}
```

Built-ins resolve to concrete values:

```swift
extension PDFOptions.Theme {
    public static let `default` = Theme(/* current output, verbatim */)
    public static let dark = Theme(/* dark page background and base16 accents */)
    public static let print = Theme(/* grayscale-only palette */)
}
```

Wiring (one new defaulted field, source-compatible):

```swift
public struct PDFOptions {
    public var theme: Theme = .default
}
```

The renderer already builds `PDFTextRun(color:)` (default `.black`). Per-element
resolution replaces the literal `.black`/`.gray`/`.link` constants with
`theme.style(for: role).color`, and code runs use `theme.codeSyntax` colors.
Because `.default` reproduces today's `PDFColor.black/.gray/.link` and current
sizes, default output is byte-identical and the existing snapshot witnesses stay
green.

Backward compatibility contract: `Theme.default` MUST encode exactly the current
hard-coded values. In #130, explicit `.default` is byte-identical to the implicit
default renderer for a mixed document witness, and the minimal canonical PDF
witness remains unchanged.

Contrast helper (pure Swift, for witnesses), per the WebAIM formula:

```swift
func relativeLuminance(_ c: PDFColor) -> Double {
    func lin(_ v: Double) -> Double { v <= 0.03928 ? v/12.92 : pow((v+0.055)/1.055, 2.4) }
    return 0.2126*lin(c.red) + 0.7152*lin(c.green) + 0.0722*lin(c.blue)
}
func contrastRatio(_ a: PDFColor, _ b: PDFColor) -> Double {
    let (l1, l2) = (relativeLuminance(a), relativeLuminance(b))
    let (hi, lo) = (max(l1, l2), min(l1, l2))
    return (hi + 0.05) / (lo + 0.05)
}
```

## Reference implementations

- Typst (Apache-2.0): set/show two-layer styling, build-time resolution.
- LaTeX standard classes (LPPL): design-vs-content separation; class extension.
- base16 / tinted-theming: 16-slot palette shape, dark = reversed ramp.
- Pygments styles (BSD-2): token-kind -> style dict with subtype inheritance.
- VS Code/TextMate themes: selector -> (foreground, fontStyle), specificity.
- W3C DTCG format: future serialization target (typed tokens, aliases, themes).

## Witness policy

#130 proves:

- `PDFOptions.Theme.default` produces byte-identical PDFs to the implicit
  default renderer for a mixed document.
- `dark` and `print` produce valid PDFs under `qpdf --check`.
- `pdftotext` extraction is unchanged across `default`, `dark`, and `print`.
- Every built-in theme's element text and code token colors pass the WCAG 2.1
  4.5:1 contrast gate against their resolved backgrounds.
- The minimal canonical PDF witness remains unchanged, proving `.default` does
  not add an explicit background or new resources.

## Ordered work

1. Done in #130: land the `PDFOptions.Theme`/`Palette`/`ElementStyle` value
   types.
2. Done in #130: route renderer constants through `Theme.default` and prove
   explicit default byte identity.
3. Done in #130: add a pure-Swift WCAG contrast witness for built-ins.
4. Done in #130: ship `dark` and `print` built-ins with qpdf and extraction
   witnesses.
5. Done in #130: expose `codeSyntax: CodeSyntaxTheme` and wire it to the #120
   tokenizer colors.
6. Future: DTCG-shaped JSON load/save; add APCA as a secondary advisory metric.

## Platform notes

- Portable macOS/Linux: the entire model is plain Swift value types and
  arithmetic; it lives in the shared renderer.
- macOS-only: nothing here requires macOS APIs; do not reach for AppKit color
  types.
- Linux-only: raster/desaturation tolerances for the print witness belong in the
  existing witness tolerance layer, not in production PDF bytes.
- iOS: not claimed; needs its own target and witnesses before any support claim.


## Reference implementations (vendored in `researchcode/`)

Study-only; map to a pure-Swift `Theme` value type (per-element `ElementRole` styles + base16-style palette + DeviceRGB, resolved at build time, default theme == current output).

Typst (Rust, Apache-2.0) - cleanest build-time style resolution, closest match:
- `researchcode/typst/crates/typst-layout/src/rules.rs` - `ShowFn<HeadingElem>` / `rules.register(Paged, HEADING_RULE)` plus reads like `styles.get(ParElem::leading)`, `styles.resolve(...)`, `Smart<T>` (Auto vs Custom) fields: one function per element role resolving typography/spacing from a style chain. Model `Theme.style(for: role)` on this; defaults fall through, matching "default theme == current output".
- `researchcode/typst/crates/typst-layout/src/document.rs` - `PageElem::fill: Smart<Option<Paint>>` + `fill_or_white()`: page background defaults to white (light theme), dark/print override.
- `researchcode/typst/crates/typst-pdf/src/paint.rs` - `convert_rgb` -> `color.to_space(Srgb).to_vec4_u8()`: exact "palette hex -> DeviceRGB at build time" step for a base16 palette.

WeasyPrint (Python, BSD-3) - the full CSS cascade -> computed values (spec-faithful inheritance):
- `researchcode/weasyprint/weasyprint/css/properties.py` - `INHERITED` set + `INITIAL_VALUES` dict (~L12, L308): which Theme fields inherit (color, font_*, line_height) vs reset per element (margins/padding).
- `researchcode/weasyprint/weasyprint/css/__init__.py` - `declaration_precedence` (~L545) + `computed_from_cascaded`/`ComputedStyle` (~L1010-1260): cascade-order precedence (default < user < per-doc) and lazy inherited-vs-initial computation; `computed_values.py` `COMPUTER_FUNCTIONS` for `currentColor`/`color-scheme` (dark mode).

Scribus (C++, GPL+exception) - partial; `scribus/styles/` not vendored:
- `researchcode/scribus/scribus/text/storytext.h` - `ParagraphStyle`/`CharStyle` + `defaultStyle()`/`parentStyle()` (refs only): confirms the paragraph-vs-character style split with a parent chain; full definitions are upstream-only.

SILE (Lua, MIT) - settings stack idea:
- `researchcode/sile/core/settings.lua` - `settings:declare{...}` defaults + `pushState`/`popState` scoped overrides: a precedent for "immutable default theme + scoped overrides" (but global mutable; prefer Typst's chain model for the Swift value-type design).

Code-syntax theme surface (for #120 token kinds): model on the closed-token-set theme formats - Pygments styles (token-kind -> color/weight with subtype inheritance) and VS Code/highlight.js (selector -> foreground/fontStyle).

Spec anchors: Typst styling docs, CSS Color 4 / Fonts 4 / Paged Media 3 (W3C), W3C Design Tokens Format, WCAG 1.4.3 + WebAIM contrast formula, base16, Pygments.
