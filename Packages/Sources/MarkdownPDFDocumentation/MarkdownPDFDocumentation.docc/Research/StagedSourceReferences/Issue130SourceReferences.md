# Issue 130 source references

Staged source and reference materials gathered for issue #130, vendored study-only under `researchcode/`.

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
