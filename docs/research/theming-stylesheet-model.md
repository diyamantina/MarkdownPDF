# Theming and stylesheet model

Date: 2026-06-02

Issue: #130

Scope: this note defines a portable theming / stylesheet model for the
Markdown-to-PDF engine. It covers per-element typography, color, and spacing, a
dark theme and a print theme, and a code-syntax theme surface that feeds the
#120 syntax-color work. It is portable macOS and Linux research. It is design
direction, not product behavior until Swift source and witnesses exist.

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
| Pygments token taxonomy. <https://pygments.org/docs/tokens/> and styles. <https://pygments.org/docs/styles/> | Hierarchical token kinds (Keyword, Name, String, Number, Comment, Operator...); a Style is a dict from token type to color/weight, subtypes inherit. | The code-syntax theme is a map from our `SourceCodeTokenKind` (#120) to color+style, with inheritance from a base entry. |
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
3. Code-syntax styles: a map from the #120 `SourceCodeTokenKind` to color+style
   (the TextMate/Pygments/base16 "tokenColors" surface).

Resolution is total: every `ElementRole` and every `SourceCodeTokenKind` has a
resolved style, falling back to the palette so no element can be unstyled.

## How to (Swift)

The current `PDFColor` is exactly DeviceRGB, so it is the palette primitive.
`PDFOptions` is the public, `Equatable`/`Sendable`, all-defaulted config struct,
so a `theme` field slots in without breaking callers.

```swift
public struct Palette: Equatable, Sendable {
    // base16-style ramp: index 0 = background ... 7 = foreground.
    public var ramp: [PDFColor]            // 8 grayscale-leaning steps
    public var accents: [PDFColor]         // base08...base0F, 8 hues
    public var foreground: PDFColor { ramp[7] }
    public var background: PDFColor { ramp[0] }
}

public enum ElementRole: Hashable, Sendable {
    case body, heading(level: Int), blockquote, link
    case codeInline, codeBlock, listMarker, tableHeader, rule, footnote
}

public struct ElementStyle: Equatable, Sendable {
    public var font: StandardFont
    public var size: Double
    public var color: PDFColor
    public var bold: Bool, italic: Bool, underline: Bool
    public var spacingBefore: Double, spacingAfter: Double
}

public struct CodeSyntaxTheme: Equatable, Sendable {
    public var base: PDFColor                                   // default token
    public var byKind: [SourceCodeTokenKind: PDFColor]         // #120 surface
    public func color(for k: SourceCodeTokenKind) -> PDFColor { byKind[k] ?? base }
}

public struct Theme: Equatable, Sendable {
    public var palette: Palette
    public var elements: [ElementRole: ElementStyle]
    public var code: CodeSyntaxTheme
    public func style(for role: ElementRole) -> ElementStyle { elements[role] ?? .body(palette) }
}
```

Built-ins resolve to concrete values:

```swift
extension Theme {
    public static let `default` = Theme(/* current output, verbatim */)
    public static let dark      = Theme(/* base00-07 ramp reversed */)
    public static let print     = Theme(/* grayscale-only, no hue accents */)
}
```

Wiring (one new defaulted field, source-compatible):

```swift
public struct PDFOptions {
    public var theme: Theme = .default   // append to the initializer with a default
}
```

The renderer already builds `PDFTextRun(color:)` (default `.black`). Per-element
resolution replaces the literal `.black`/`.gray`/`.link` constants with
`theme.style(for: role).color`, and code runs use `theme.code.color(for: kind)`.
Because `.default` reproduces today's `PDFColor.black/.gray/.link` and current
sizes, default output is byte-identical and the existing snapshot witnesses stay
green.

Backward compatibility contract: `Theme.default` MUST encode exactly the current
hard-coded values. The first PR is a pure refactor (introduce `Theme`, route the
existing constants through `.default`) with zero pixel diff, proven by the
current raster and extraction witnesses before any new theme ships.

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

Any theming PR must prove:

- `Theme.default` produces byte-identical PDFs to pre-theme output (raster +
  `pdftotext` extraction unchanged) for the existing fixture corpus.
- Each built-in theme's body-text-on-background pair passes WCAG 2.1 4.5:1, and
  large-heading pairs pass 3:1, via the pure-Swift `contrastRatio` helper.
- The `print` theme is grayscale-safe: rasterizing then desaturating keeps all
  text/background pairs above 4.5:1, so it survives black-and-white printing.
- Resolution is total: a property test over all `ElementRole` and
  `SourceCodeTokenKind` cases returns a concrete style with no fallback gap.
- Code-syntax colors leave `pdftotext` extraction identical to uncolored code
  and keep Poppler/MuPDF token boxes non-overlapping (inherits #120 policy).
- qpdf validates structure with no warnings for every built-in theme.
- macOS and Linux produce equivalent results within existing raster tolerance.

## Ordered work

1. #130 Land this model doc and the `Theme`/`Palette`/`ElementStyle` value types.
2. Refactor renderer to route current constants through `Theme.default`; prove
   zero pixel diff.
3. Add `contrastRatio` helper + WCAG witness; gate built-ins on 4.5:1.
4. Ship `dark` and `print` built-ins behind the contrast/grayscale witnesses.
5. Expose `code: CodeSyntaxTheme` and wire it to the #120 token kinds (opt-in).
6. Future: DTCG-shaped JSON load/save; add APCA as a secondary advisory metric.

## Platform notes

- Portable macOS/Linux: the entire model is plain Swift value types and
  arithmetic; it lives in the shared renderer.
- macOS-only: nothing here requires macOS APIs; do not reach for AppKit color
  types.
- Linux-only: raster/desaturation tolerances for the print witness belong in the
  existing witness tolerance layer, not in production PDF bytes.
- iOS: not claimed; needs its own target and witnesses before any support claim.
