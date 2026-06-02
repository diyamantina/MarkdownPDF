# Math display ActualText and MuPDF zero-size quads

Why the math formula corpus surfaces MuPDF `non-positive size` glyph quads, and
why this is an extraction artifact of display-math ActualText rather than a
layout or rendering defect (#172).

## Symptom

The math formula corpus witness (`mathFormulaCorpusRendersSubsetAndFallback`)
surfaced many MuPDF glyph quads with zero width or zero height. The controlled
`rendersOptInTeXMathSubset` test passes the identical `characterQuadIssues()`
gate, so the corpus test was written to defer per-glyph geometry to the
controlled test pending this investigation.

## Method

Render the corpus with math enabled, run `qpdf --check` and
`mutool draw -F stext`, then parse every `<char>` quad (eight corner
coordinates), classify each glyph by width and height, and correlate the
degenerate glyphs to their text lines.

## Evidence

- `qpdf --check`: no syntax or stream-encoding errors.
- 1938 glyphs total; 524 have zero width or height.
- Of those 524, 263 are spaces. The gate already ignores whitespace, so they are
  not failures.
- The remaining ~261 degenerate glyphs are non-space and fall on 46 lines; all 63
  other lines (prose and clean math) have no degenerate non-space glyph.
- The 46 affected lines extract to the per-formula linearization text itself, for
  example `x^{2}`, `{i}^{2`, `,j}^{n+1}`, `e^{x^{2}`. Those `^`, `{`, `}`, `(`
  characters come from the readable linearization written as ActualText, not from
  drawn glyphs.

## Conclusion

Display math wraps each formula in a single `ActualText` marked-content span
carrying the readable linearization (so `pdftotext` extracts, for example,
`frac(x^{2}, sqrt(y+1))`). The linearization has more characters than the formula
has drawn glyph boxes. MuPDF distributes the ActualText characters across the
drawn glyph positions and emits the surplus characters with degenerate quads
(zero width for mid-run continuations, zero height for others).

This is an extraction-tooling artifact of ActualText, not a visual defect: the
drawn glyphs and rules are positioned correctly, qpdf is valid, and extraction
yields the intended readable linearization. Per-glyph quad geometry is therefore
witnessed on controlled formulas (where the ActualText length tracks the drawn
glyph count) in `rendersOptInTeXMathSubset`, while the corpus witnesses breadth:
validity, extraction, fallback, rules, and nonblank output.

A future option, if per-glyph geometry on the full corpus is wanted, is to emit
ActualText per atom rather than once per formula, so each marked-content span's
character count tracks its drawn glyphs. That is a renderer change, not a fix for
a defect, and is not pursued here.
