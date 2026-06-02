# MarkdownPDF research handoff

Prepared research to be ingested into the repo by the loop (these files are NOT
committed by me). Each file is em-dash-free so it passes the repo forbidden-text
scan when copied into `docs/`.

For each: the GitHub issue carries a pointer comment; copy/append the file into
the named `docs/research/` target as part of doing that issue.

| File | Issue | Append into `docs/research/` |
| --- | --- | --- |
| 122-source-references.md | #122 CJK + diacritics | cjk-and-diacritics-rendering.md |
| 123-source-references.md | #123 RTL / bidi | rtl-manuscript-hardening.md |
| 126-source-references.md | #126 charts | native-chart-rendering.md |
| 127-source-references.md | #127 DEFLATE | pure-swift-deflate-compression.md |
| 128-source-references.md | #128 tagged PDF / PDF-A | tagged-pdf-pdfa-accessibility.md |
| 129-source-references.md | #129 footnotes / task lists | gfm-footnotes-and-task-lists.md |
| 130-source-references.md | #130 theming | theming-stylesheet-model.md |
| 131-source-references.md | #131 math | pure-swift-math-typesetting.md |
| apple-and-custom-fonts.md | #138 Apple/custom fonts | apple-and-custom-fonts.md (new) |

Related issues filed:
- #136: policy - always keep README + Mermaid roadmap current and color-coded (legend first, vertical only).
- #137: vendor canonical from-scratch references into researchcode (libdeflate, zlib, fribidi, unicode-bidi, unicode-linebreak).

Provenance: each file maps a capability to concrete `researchcode/<project>/<file>` symbols
(study-only, licenses noted) plus high-authority specs. Honest gaps recorded: no
vendored project implements DEFLATE from scratch (all wrap zlib); pango/sile/typst
delegate bidi to fribidi/ICU/unicode-bidi. Those are why #137 exists.
