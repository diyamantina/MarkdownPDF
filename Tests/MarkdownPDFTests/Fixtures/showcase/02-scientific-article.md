# On the Box-and-Glue Typesetting of Multilingual Scientific Prose

**Authors:** A. Müller, Б. Иванова, Γ. Παπαδόπουλος

## Abstract

We present a pure-Swift pipeline that typesets multilingual scientific prose with
embedded fonts, inline and display mathematics, and native vector charts. The
system avoids browser engines and C libraries, serializing PDF bytes by hand. We
evaluate fidelity with independent witnesses (Poppler and MuPDF) and report
zero glyph collisions across Latin-diacritic, Cyrillic, and Greek samples.

## 1. Introduction

Scientific documents routinely mix scripts: an author named Dvořák may cite
Œuvres complètes, a Привет-greeting dataset, or the Καλημέρα corpus. Rendering
such text faithfully requires real glyphs, not substitution. The mass-energy
relation $E = mc^2$ stays inline, while the normal density is set as a display
equation:

$$f(x) = \frac{1}{\sigma \sqrt{2\pi}} e^{-\frac{(x-\mu)^2}{2\sigma^2}}$$

## 2. Method

Display equations are typeset by a box-and-glue engine:

$$\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$$

$$\sqrt{a^2 + b^2} = c$$

$$\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$

### 2.1 Measured coverage

```chart
type: bar
title: Glyph coverage by script
x-label: Script
y-label: Glyphs covered
categories: Latin, Cyrillic, Greek
series: DejaVu = 220, 96, 84
series: Liberation = 210, 92, 80
```

## 3. Results

| Script | Sample | Collisions | Coverage |
| :--- | :---: | ---: | ---: |
| Latin | café résumé déjà | 0 | 100% |
| Cyrillic | Привет мир, код | 0 | 100% |
| Greek | Καλημέρα, Ωμέγα | 0 | 100% |

No glyph collisions were detected.[^witness]

[^witness]: Verified with `pdftotext -tsv` word boxes and MuPDF character quads.

## 4. Conclusion

A pure-Swift renderer can typeset multilingual scientific prose with embedded
glyphs and mathematics at article grade.

## References

1. Knuth, D. *The TeXbook*. Addison-Wesley, 1984.
2. Bringhurst, R. *The Elements of Typographic Style*.
