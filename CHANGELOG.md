# Changelog

All notable changes to MarkdownPDF are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- A block quote's left rule now takes its origin from the first drawing inside the
  quote, not from the cursor when the quote opened. A first block that broke the
  page before drawing (a heading, a code fence, a figure, a table) left a rule on a
  page carrying no quote content
  ([#13](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/13)).
- Quoting a block no longer destroys its indentation. `stripBlockQuoteMarker` trimmed
  the content after the `>`, dedenting the whole quote to column zero, so a nested
  list, an indented code block, or a continuation line could not survive being
  quoted ([#17](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/17)). The
  marker is now up to three spaces, a `>`, and at most one space.
- A list marker inside a themed block quote now takes the quote's color, while
  keeping its own font face, so italicising a quote no longer leaves black bullets
  beside quote-colored text
  ([#12](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/12)). This covers
  bullets, ordered numbers, and task checkboxes, whose box and check stroke are
  drawn from the same `.listMarker` color. The built-in themes give `.blockQuote`
  and `.listMarker` the same `bodyColor`, so their output is unchanged.

### Added

- Nested lists. `parseUnorderedList` and `parseOrderedList` now take indentation
  seriously: a marker indented to the previous item's content column belongs to
  that item, and the item's lines are re-parsed as a document of their own. That
  brings nested lists at every depth, continuation lines indented to the content
  column, and block content inside items such as extra paragraphs and code fences
  ([#3](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/3)). Container
  nesting is bounded at `BlockParser.maximumNestingDepth`; beyond it an item's
  content is kept as prose rather than recursed into.
- A blank line between two siblings now yields one loose list instead of two
  lists, so an ordered list no longer restarts its numbering after a blank line.
- `MarkdownBlock.pageBreak`, written as `<!-- pagebreak -->`, starts a new page.
  An HTML comment keeps the directive invisible in other Markdown renderers.
  Trailing breaks are dropped by the parser and leading or consecutive breaks
  collapse in the renderer, so a break can never emit a blank page. Any other
  HTML comment keeps its existing visible-text rendering.
- Block quotes honor their `.blockQuote` theme role: `fontRole` and `color` style
  the quoted prose, and `borderColor` strokes a left rule down every page the
  quote occupies. Previously only the spacing multipliers had any effect
  ([#4](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/4)). No built-in
  theme sets `borderColor`, so default output is unchanged. `backgroundColor`
  remains unhonored for quotes
  ([#10](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/10)).

### Fixed

- Unordered list items now draw a bullet through the `.listMarker` theme role.
  Previously only ordered items and task checkboxes drew a marker, so bullet
  lists rendered as bare indented lines ([#2](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/2)).
- The marker is chosen per bound font: U+2022 where the font can draw it, an
  ASCII hyphen as fallback, and no marker at all when an embedded font can draw
  neither. A base-14 marker is also omitted under `PDFOptions.Conformance`,
  where an unembedded base-14 font would otherwise fail `validateConformance`
  and reject a document that rendered before.
- `renderList` now reserves the height of a list item's first block rather than
  a single text line, so an item whose body is a standalone image no longer
  strands its marker at the bottom of the previous page.
- Mermaid diagrams, native charts, and standalone images now separate themselves
  from the following block with the theme's paragraph spacing on top of the 12pt
  below the figure, which a following line's ascender consumed
  ([#7](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/7)). The trailing
  gap is applied to the cursor, not reserved, so a figure that fits on the page
  still fits.

## [0.6.0] - 2026-06-26

### Added

- Flowcharts that are wider than the page content area are now uniformly scaled
  down (smaller font and boxes) until they fit, instead of falling back to source.
  A wide left-to-right chain of nodes renders as a shrunk diagram rather than a
  code block. Diagrams that already fit are unchanged.

## [0.5.0] - 2026-06-25

### Added

- Native charts now truncate an over-wide series or category label with an
  ellipsis instead of failing the whole chart, so descriptive labels render in
  the PDF rather than dropping to visible source.
- Mermaid flowcharts now render dashed edges (`-.->`, both plain and labeled)
  as dashed lines.
- Mermaid flowcharts now lay out cyclic graphs by breaking back-edges, so a
  flowchart with a cycle renders instead of falling back to source.

### Changed

- License changed from MIT to AGPL-3.0. MarkdownPDF is now dual licensed:
  AGPL-3.0 for open-source use, with a commercial license available for
  closed-source or otherwise AGPL-incompatible use (see `COMMERCIAL.md`).
  Versions published before this change remain available under their original
  MIT terms.

## [0.4.2] - 2026-06-07

### Fixed

- Precomposed Unicode subscript and superscript characters (for example `x₁`,
  `H₂O`, `xᵢ`, `n²`) no longer abort `render(markdown:)` when the embedded font
  lacks those glyphs. TeX math fonts such as Latin Modern Math do not ship
  precomposed sub/superscript glyphs, so the renderer now folds those codepoints
  to their base character and renders the base glyph instead of throwing
  `missingGlyph`. Genuinely unmappable characters still reject. Fixes #221.

### Fixed

- A standalone image whose target cannot be resolved or decoded (a missing file,
  a site-absolute `/assets/...` path with no asset root, or an unsupported format
  such as SVG) no longer throws from `render(markdown:)` and fails the whole
  document. It now degrades to a visible `[Image: alt]` placeholder, the same way
  a remote image does, and the document still renders. Fixes #211.

## [0.4.0] - 2026-06-03

### Changed

- Render the full WinAnsi (Windows-1252) character set in the default base-14
  profile, with no embedded font. Accented Latin (`é`, `ñ`, `ü`, `ç`, ...), the
  CP1252 punctuation block (curly quotes, en/em dashes, NBSP, bullet), and
  common symbols (`€`, `£`, `¢`, `©`, `®`, `™`, `°`, `±`) now paint as their real
  glyphs instead of `?`. Previously only printable ASCII (`0x20-0x7E`) rendered
  and everything else was replaced with a question mark. Content-stream literal
  strings now emit high bytes as octal escapes, the font `/Widths` cover the full
  `32-255` range with AFM-derived advances, and the page `/ActualText` carries
  the original text. Characters beyond WinAnsi (CJK, complex scripts, color
  emoji) still fall back pending epic #210. First phase of #210.

## [0.3.0] - 2026-06-03

### Changed

- Restructure the repository as a pure, git-resolvable SwiftPM package, mirroring
  the MathTypeset layout: `Package.swift` at the repo root, `Sources/`, and
  `Tests/`. A consumer can now depend on it with
  `.package(url: ".../MarkdownPDF.git")`. One package, multiple `MarkdownPDF*`
  targets: the `MarkdownPDF` library, the `MarkdownPDFLinux` and `MarkdownPDFMac`
  renderer entry points, `MarkdownPDFResume`, and the engine documentation, with
  the full `MarkdownPDFTests` and `MarkdownPDFResumeTests` suites kept in the
  package (they `@testable`-import the engine, so they cannot live in a consumer).

### Removed

- The `markdownpdf` / `resumepdf` command-line executables and the `Apps/` and
  `Main.xcworkspace` developer shell move to the separate `MarkdownPDFCli` repo,
  which consumes this package plus MathTypeset. The engine repo is now library-only.

## [0.2.0] - 2026-06-03

### Added

- Draw math symbols (operators, relations, Greek, arrows: `\sum` -> ∑, `\pm` ->
  ±, `\sigma` -> σ, and so on) with their real Unicode glyphs when the active
  embedded font covers them, falling back to the ASCII transliteration per
  symbol only where the font has a gap. Previously every symbol used the ASCII
  transliteration. The portable base-14 profile still renders all-ASCII (it
  covers no math glyphs), so its output is unchanged; an embedded math-capable
  font now matches a web/SVG render of the same source. Consumes the
  `MathTypeset` 0.5.0 `unicodeWhereCovered` symbol style, with the embedded
  font's `cmap` answering coverage.
- Parse TeX horizontal spacing commands in math (`\quad`, `\qquad`, `\,`, `\:`,
  `\;`, `\!`, and `\ `) through MathTypeset 0.6.0. Previously any of these forced
  the whole formula to fall back to visible source; the math-handbook showcase
  rows that use `\qquad` now typeset.
- README gallery of real rendered PDF pages, a four-panel hero banner
  (multilingual text, native charts, a Mermaid diagram, and mathematics), and a
  dedicated Mathematics showcase cell drawn from the scientific-article fixture.

### Changed

- Tolerate a zero-height MuPDF line in the character-quad witness the same way
  the per-glyph check already does (#197): a line made only of legitimately tiny
  nested sub/superscript glyphs (`a_{i,j}^{n+1}`, `2^{2^{x}}`) can report a
  zero-height quad. Only a clearly negative (flipped) line height is a defect;
  zero or negative width still fails.
- Retire the completed child issues from the in-progress roadmap diagrams
  (Current Hardening and Math typesetting), keeping each diagram focused on the
  work that remains. Every epic stays visible as a node in the Epics overview.

## [0.1.0] - 2026-06-03

### Added

- Initial Pure Swift Markdown parser, PDF renderer, and `markdownpdf` CLI.
- Direct PDF serialization with Apple font names and no embedded fonts.
- Parser and renderer tests for tables, images, inline styles, and PDF structure.
- `MarkdownPDFLinux` and `MarkdownPDFMac` renderer entry products.
- MuPDF character-quad and cross-renderer raster validation for generated PDFs.
- Deterministic PDF metadata, named heading destinations, outline objects, and
  internal heading links.
- Portable Mermaid flowchart rendering for a documented Swift-only subset, with
  visible fallback for unsupported Mermaid syntax.
- Portable embedded-font and ToUnicode implementation plan for future Type 0
  and CIDFontType2 work.
- Internal Type 0, CIDFontType2, FontFile2, and ToUnicode object models for the
  portable embedded-font profile.
- Pure Swift TrueType metadata parser with table bounds, checksums, cmap
  discovery, horizontal metrics, names, and OS/2 embedding policy gates.
- Internal TrueType glyph mapping and width measurement for the portable
  embedded-font profile.
- Deterministic ToUnicode CMap generation with range compression, chunking, and
  glyph-mapping conflict detection.
- Opt-in CID text writing, TrueType subsetting, CIDToGIDMap streams, and public
  `PDFOptions.EmbeddedFonts` role mapping for caller-provided TrueType data.
- CI-safe embedded-font fixtures using generated Swift TrueType data and an
  installed DejaVu Sans smoke-test path instead of committed font binaries.
- Opt-in portable syntax coloring for supported fenced code block language
  hints, with extraction, geometry, and raster witnesses.
- Opt-in TeX-math parsing for inline `$...$`, display `$$...$$`, and fixed
  `\(...\)` and `\[...\]` delimiters, including nested forms, laid out by a Pure
  Swift box-and-glue subset with visible source fallback for unsupported
  commands.
- `PDFOptions.MathTypesetting.fontBacked` profile that requires an embedded
  OpenType `MATH` font for the styled math role and uses its constants for
  display-math layout.
- Diverse multilingual showcase corpus combining prose, TeX math, native charts,
  Mermaid diagrams, and mixed-script tables, including a large multi-chapter
  handbook, rendered with embedded fonts under the full visual witness battery
  and across popular page formats (US Letter, Legal, Tabloid, A3, A5).

### Fixed

- Scale embedded-font CID `/W` widths and FontDescriptor metrics (FontBBox,
  Ascent, Descent, CapHeight) from the font `unitsPerEm` space to PDF 1000-unit
  glyph space. Fonts with `unitsPerEm != 1000` (DejaVu and Liberation use 2048)
  previously rendered garbled in viewers: glyphs spread apart, adjacent words
  overlapped, and lines collided vertically, because viewers advance glyphs from
  `/W` and derive glyph heights from the descriptor.
- Run the full visual witness battery (Poppler `pdftotext -tsv` word-box
  geometry, MuPDF character quads, and a Poppler-vs-MuPDF raster comparison) on
  embedded-font fixtures so width and metric scaling regressions fail the build
  instead of passing extraction-only checks.
- Stop the MuPDF character-quad witness from flagging legitimately tiny math
  sub/superscripts (zero-height, positive-width slivers) as non-positive size;
  only a clearly negative (flipped) height is now a defect.

### Changed

- Consume the shared `MathTypeset` package (0.4.0) for the TeX-math engine
  (parser, layout, metrics, OpenType MATH reader) instead of in-tree copies. The
  renderer bridges the package's neutral `MathRun`/`MathColor` output to PDF text
  and rules through a thin adapter; the math witness corpus is unchanged. The
  engine is now shared with the Tiledown project.
- Draw the `\sqrt` radical sign as scaling vector strokes that grow with the
  radicand, instead of the literal word `sqrt`. Math symbols keep their ASCII
  transliteration in the portable profile, since the base-14 and open CI fonts
  do not cover the Unicode math block.
- Move the full study-only source snapshot corpus (33 third-party projects) out
  of `researchcode/` into the private companion repository `MarkdownPDFResearch`,
  keeping only a small high-signal subset (`pydyf`, `unicode-linebreak`,
  `unicode-bidi`, `libdeflate`, `zlib`) locally. This shrinks the public
  repository and keeps it classified as Swift.
- Model PDF object registration, xref tables, trailers, and file envelopes as
  typed Swift structures.
- Model the PDF catalog, flat page tree, and page dictionaries as typed Swift
  structures.
- Track page resource usage and resource dictionaries through typed Swift
  structures.
- Model image XObjects and reusable image resource references through typed
  Swift structures.
- Build page content streams from typed PDF operator structures.
- Measure table column widths from header and body content, preserve alignment,
  and repeat table headers across page breaks.
- Validate Mermaid edge-label placement during planning and fall back visibly
  when labels would collide with diagram nodes.
