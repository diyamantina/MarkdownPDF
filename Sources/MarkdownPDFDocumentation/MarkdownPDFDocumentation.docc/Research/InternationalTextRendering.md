# International Text Rendering

How MarkdownPDF turns Unicode text into PDF glyphs across scripts: what works
today, the first-principles target, and the concrete blockers between the two.
Tracked by epic [#210](https://github.com/mihaelamj/MarkdownPDF/issues/210).

## First principles

A PDF renders character C only if some available font has a glyph for C and the
font's encoding maps a code to it. The principled pipeline is, per grapheme
cluster: segment, reorder for bidi, itemize by script, shape (GSUB/GPOS), map to
glyphs, position, emit. Route each cluster to the first font that covers it, and
when nothing does, preserve the codepoint and degrade visibly, never with a
silent `?`.

## What works today

- **ASCII** in every profile.
- **Western European (WinAnsi / CP1252)** in the default base-14 profile with no
  embedded font: accented Latin (`é ñ ü ç`), curly quotes, en/em dashes, NBSP,
  and common symbols (`€ £ ¢ © ® ™ ° ±`). Shipped 0.4.0. Glyph advances for the
  rarer punctuation are approximate pending exact Core14 AFM metrics.
- **Anything a supplied embedded font fully covers**, via
  `PDFOptions.EmbeddedFonts`: Central European Latin (Croatian/Serbian/Czech/
  Polish/Hungarian: `č ć đ ą ę ł ń ő ű`), Cyrillic, Greek, and CJK. Verified by
  rendering each with DejaVu / a CJK witness font.
- **Bidi ordering** (`BidiParagraphOrdering`) and **CJK line breaking** exist.
- **Math symbols** route per-glyph through a font-coverage check
  (`unicodeWhereCovered`).
- **Unresolvable images** degrade to a placeholder rather than failing the
  document (0.4.1, #211).

## Blockers between here and full coverage

Discovered while attempting CJK / Hebrew / Arabic with system fonts:

1. **No font-fallback chain.** The embedded-font path uses a single font and
   throws `missingGlyph` on any character it lacks. A script-only font (e.g.
   Hebrew-only) plus ordinary Latin/punctuation therefore fails. The fix is
   coverage-driven routing: script font, then base-14, then a placeholder.
2. **Variable fonts are rejected.** Apple system `SFHebrew` / `SFArabic` are
   variable fonts; embedding needs named-instance instancing (#184).
3. **TrueType Collections (`.ttc`) are not parsed.** macOS ships CJK only as
   `.ttc` (PingFang, Hiragino, STHeiti); embedding needs face selection (#183).
4. **No OpenType shaping (GSUB/GPOS).** Base Arabic maps through `cmap` to
   isolated, unjoined forms, which is incorrect Arabic; Arabic Supplement /
   Extended / presentation forms are refused with a typed error. Hebrew niqqud
   and Arabic harakat need GPOS mark positioning. This is a hand-written,
   pure-Swift shaping engine and the single largest piece of the epic.

## Phases (each complete and witnessed before the next)

1. **WinAnsi base-14** (done, 0.4.0): Western European with no embedded font.
2. **Coverage-driven font-fallback chain** (+ variable-font instancing, `.ttc`
   face selection): unlocks Central European, Hebrew, and CJK with embedded or
   system fonts without crashing on mixed content. The keystone phase.
3. **OpenType GPOS**: mark positioning, unlocking Hebrew niqqud and kerning.
4. **OpenType GSUB + Arabic joining**: contextual forms and ligatures for Arabic.
5. **Color emoji**: COLR/CPAL, sbix/CBDT, OpenType-SVG, plus grapheme clustering.

## Rendering these today

Supply a non-variable, single-face font that covers the document's scripts
through `PDFOptions.EmbeddedFonts`. Central European, Cyrillic, Greek, and CJK
render correctly this way now. Complex-script shaping (Arabic) and color emoji
remain pending per the phases above.
