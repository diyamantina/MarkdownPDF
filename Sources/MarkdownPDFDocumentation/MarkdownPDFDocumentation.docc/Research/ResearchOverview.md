# Research notes

This directory is the map for MarkdownPDF research records. Research notes are
inputs to implementation work, not product behavior until the behavior exists in
Swift source and tests.

## First-principles map

Organize research by the invariant it changes, not by issue number.

1. Product and PDF byte contract. What MarkdownPDF may claim, which PDF objects
   it emits, and which object model is allowed in source.
2. Evidence contract. How a PDF behavior is proven with structural checks,
   extraction, geometry, raster witnesses, and CI.
3. Text, font, and extraction contract. How source scalars become glyphs, how
   glyphs map back through ToUnicode, which font programs may be embedded, and
   which Unicode behaviors are portable.
4. Layout and content contract. How Markdown blocks, generated diagrams, source
   code, charts, math, footnotes, and themes become page geometry and PDF ink.
5. Conformance and stream contract. How optional profiles such as compression,
   tagging, accessibility, and archival output change the PDF byte stream.
6. Source-study archive. External implementations are evidence only. They inform
   clean Swift implementations but do not become package dependencies.

## Read order

1. Start with the product and PDF byte contract.
2. Read the evidence contract before changing behavior or tests.
3. Choose the text/font or layout/content group that owns the feature.
4. For compression, tagging, PDF/A, or PDF/UA, also read the conformance and
   stream contract.
5. Use source-study files only after the local contract is clear.
6. Use macOS-specific research only for macOS targets. It is not a Linux or iOS
   implementation plan.

## Boundaries

- The core renderer must remain Pure Swift and Linux-buildable.
- Research can describe external libraries, papers, tools, and operating system
  APIs, but implementation in this repo must generate PDF bytes directly.
- macOS-specific findings must say macOS-specific. They do not imply iOS support.
- Useful research results belong in this directory.
- Source snapshots, when present, are research evidence and not package
  dependencies. See `source-snapshot-policy.md`.

## Product and PDF byte contract

| File | Purpose |
|---|---|
| `markdownpdf-output-profile.md` | The current portable output profile MarkdownPDF emits and validates. |
| `canonical-pdf-document-structure.md` | Canonical PDF object structure, xref, trailer, pages, resources, streams, outlines, and validation expectations. |
| `pdf-type-modeling-policy.md` | Policy for adding internal typed PDF model structures. |
| `existing-pdf-writer-alignment.md` | Alignment notes between existing writer behavior and research findings. |

## Evidence contract

| File | Purpose |
|---|---|
| `pdf-validation-tooling.md` | Open source validation tools and the current CI validation strategy. |
| `pdf-visual-layout-validation.md` | Visual layout validation strategy using text and render extraction tools. |
| `complex-script-fixture-witness-policy.md` | Fixture and witness policy for future complex-script, bidi, ligature, combining-mark, no-space line-break, failure, and platform-boundary claims. |
| `../rules/pdf-witness-gate.md` | Required witness policy for any layout-affecting PDF feature. |

## Text, font, and extraction contract

| File | Purpose |
|---|---|
| `portable-embedded-fonts-tounicode-plan.md` | Portable embedded-font and ToUnicode implementation plan and current policy, including Type 0, CIDFontType2, public font input, CI font fixture handling, and staged issues. |
| `complex-script-shaping-bidi-roadmap.md` | Follow-up epic roadmap for Unicode line breaking, bidi ordering, shaped text clusters, pure Swift shaping increments, and ToUnicode cluster witnesses. |
| `cjk-and-diacritics-rendering.md` | CJK, kanji, and combining-diacritics rendering plan and source-reference research. |
| `rtl-manuscript-hardening.md` | RTL manuscript-scale layout, bidi, mirroring, extraction, and witness plan. |
| `apple-and-custom-fonts.md` | Apple system font naming limits, custom font acceptance matrix, and font embedding gate plan. |

## Layout and content contract

| File | Purpose |
|---|---|
| `portable-mermaid-flowcharts.md` | Portable Mermaid flowchart subset, unsupported fallback behavior, and validation expectations. |
| `source-code-typesetting-literature.md` | Literature and standards research for source-code block formatting, wrapping, extraction, and witness policy. |
| `source-code-renderer-analysis.md` | Comparison between source-code research and the current MarkdownPDF parser, renderer, PDF writer, and witness stack. |
| `source-code-formatting-model.md` | Portable internal model for source-code block layout, inline-code policy, tab expansion, page breaks, spacing, and witnesses. |
| `portable-syntax-coloring.md` | Portable syntax-coloring recommendation, dependency boundary, implemented token model, color policy, and witness requirements. |
| `native-chart-rendering.md` | Pure-Swift chart rendering research for pie, bar, line, and scatter charts. |
| `gfm-footnotes-and-task-lists.md` | GFM footnotes and task-list checkbox parser, renderer, and witness plan. |
| `theming-stylesheet-model.md` | Theming, stylesheet, palette, and syntax-theme model for future renderer options. |
| `pure-swift-math-typesetting.md` | TeX-math subset, OpenType MATH table, and PDF math-emission research. |

## Conformance and stream contract

| File | Purpose |
|---|---|
| `pure-swift-deflate-compression.md` | Pure-Swift DEFLATE and PDF `/FlateDecode` stream wiring plan. |
| `tagged-pdf-pdfa-accessibility.md` | Tagged PDF, PDF/UA, and PDF/A archival output research and validator plan. |

## Source-study archive

| File | Purpose |
|---|---|
| `source-snapshot-policy.md` | Policy for source snapshots as research evidence, not package dependencies. |
| `deep-portable-pdf-source-study.md` | Deeper study of portable PDF implementations and architecture patterns. |
| `existing-pdf-products-source-study.md` | Survey of existing products and libraries that produce PDFs. |
| `open-source-pdf-library-porting.md` | Notes on which open source ideas can be translated into Swift without taking dependencies. |
| `pdf-rendering-literature-review.md` | Scientific and technical literature relevant to PDF rendering, layout, and validation. |
| `mac-pdf-renderer-research.md` | macOS PDF rendering research. macOS only unless explicitly stated otherwise. |
| `staged-source-references/` | Exact committed handoff documents for staged source-reference files and the handoff index. |

## Updating this directory

When adding a research note:

- Add the new file to the file map.
- State whether the finding is portable macOS/Linux, macOS-only, or not suitable
  for implementation.
- Prefer source links and reproducible observations over summaries.
- Keep implementation recommendations separate from research evidence.
- Do not cite private absolute paths or machine-specific paths.
