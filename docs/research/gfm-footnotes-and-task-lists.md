# GFM footnotes and task-list checkboxes

Date: 2026-06-02. Issue: #129. Status: research only. No renderer code, no parser
tables, no public API added by this note.

Scope: this note defines how MarkdownPDF can add two GitHub Flavored Markdown
extensions, footnotes (`[^id]`) and task-list checkboxes (`- [ ]` / `- [x]`), as
a pure-Swift parse-and-render increment. It is portable macOS and Linux research.
It is not a macOS-only plan, not an iOS claim, and not an implementation promise
until source and witnesses exist.

## Product boundary

The shared renderer stays Swift-only and Linux-buildable and must generate PDF
bytes directly. This feature must not depend on CoreText, CoreGraphics, AppKit,
UIKit, PDFKit, WebKit, browser renderers, LaTeX, JavaScript, Python, shell, or
any C Markdown/PDF library. In particular cmark-gfm and swift-cmark are STUDY
references only, never linked or vendored. Cited reference projects and licenses:
CommonMark spec reference impls (BSD-2), cmark-gfm (BSD-2), comrak (BSD-2),
pulldown-cmark (MIT), markdown-it core + footnote/task-list plugins (MIT),
swift-markdown / swift-cmark by Apple (Apache-2.0, wraps cmark-gfm so out of
boundary as a dependency, in boundary as a model study). License notes matter
because any code we read must inform a clean-room Swift reimplementation, not a
copy.

## Standards and sources

CommonMark, current version 0.31.2 (2024-01-28), is the base grammar for blocks,
inlines, link reference definitions, and lists: https://spec.commonmark.org/0.31.2/
(index https://spec.commonmark.org/current/). Our existing parser already follows
it for the block/inline model.

GFM spec defines the GitHub superset and, importantly, includes the
task-list-items extension in the spec body but does NOT specify footnotes:
https://github.github.com/gfm/ . Task list items are the section "Task list items
(extension)" there.

Task lists, product docs and behavior: https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/about-tasklists .
Syntax: "Preface list items with a hyphen and space followed by `[ ]`"; completed
items use `[x]`. A task list item is an ordinary list item whose first inline
content is a `[ ]`, `[x]`, or `[X]` marker followed by whitespace; anything else
stays a normal list item.

Footnotes are a GitHub extension outside both specs, announced 2021-09-30:
https://github.blog/changelog/2021-09-30-footnotes-now-supported-in-markdown-fields/ .
Footnotes are "displayed as superscript links" and when clicked "jump to their
referenced information, displayed in a new section at the bottom of the document."
Syntax: an inline reference `[^1]` plus a definition line `[^1]: My reference.`
The colon is mandatory; identifiers are arbitrary labels, not required numeric.

Footnote rendering rules to mirror (from observed GitHub output): markers are
renumbered to a document-order sequence starting at 1, regardless of label text;
only referenced definitions are emitted; the bottom section lists definitions in
order of first reference; each definition ends with one back-reference arrow per
reference site, linking to the marker. Multiple references to one label produce
multiple back-links.

## Model

The repo block model is `MarkdownBlock` (`heading`, `paragraph`, `blockQuote`,
`unorderedList([ListItem])`, `orderedList(start:items:)`, `codeBlock`, `table`,
`thematicBreak`, `html`) with `ListItem` and a `Table`; inlines are
`MarkdownInline` (`text`, `softBreak`, `lineBreak`, `code`, `emphasis`, `strong`,
`strikethrough`, `link`, `image`). Proposed additive changes:

- Task items: add an optional checkbox state to `ListItem` rather than a new
  block. swift-markdown does exactly this: `ListItem` carries an optional
  `Checkbox` (`.checked` / `.unchecked`). pulldown-cmark emits a
  `TaskListMarker(bool)` as the first inline of the item. comrak sets list item
  metadata for tasklist. Recommended Swift: `ListItem.checkbox: Checkbox?` where
  `enum Checkbox { case checked, unchecked }`, populated only when the GFM marker
  is matched, otherwise `nil` (preserves CommonMark behavior).
- Footnotes: add inline `case footnoteReference(label: String)` and a block
  `case footnoteDefinition(label: String, children: [MarkdownBlock])`. This
  matches swift-markdown's `FootnoteReference`/`FootnoteDefinition`, comrak's
  `FootnoteReference`/`FootnoteDefinition`, and pulldown-cmark's
  `FootnoteReference` + `Tag::FootnoteDefinition`. Keep label text as authored;
  assign display numbers in a later resolution pass, not at parse time.
- A resolution pass between parse and render builds an ordered footnote table:
  walk the document in source order, collect first-reference order of labels that
  have a definition, assign 1..n, drop unreferenced definitions and dangling
  references (render dangling refs as literal text per GitHub leniency, or a
  typed warning per witness policy).

## How to render in PDF terms

The engine already has named destinations (`PDFNamedDestinations`,
`PDFHeadingDestination`), link annotations (`PDFLinkAnnotation` with `.uri` and
`.destination(name:fallbackURI:)` targets), and list layout. Reuse all three:

- Footnote marker: render the assigned number as a superscript inline run
  (smaller font, raised baseline via the existing `PDFTextRun` positioning),
  wrapped in a `PDFLinkAnnotation` targeting `.destination(name: "fn-<n>")`.
  Define a named destination `fn-<n>` at the matching definition row. Also
  register `fnref-<n>-<k>` destinations at each marker site for back-links.
- Footnote section: after the last body block, emit a thematic-break-style
  separator then a definition list. Each row: the number, the definition's
  rendered blocks, then one or more back-reference arrows. Each arrow is a glyph
  (U+21A9) wrapped in a `PDFLinkAnnotation` targeting
  `.destination(name: "fnref-<n>-<k>")`. Same destination+annotation machinery
  as heading links; no new PDF object types.
- Checkbox glyph: render in the list item's marker column instead of (or
  alongside) the bullet. Two portable options: (a) draw ballot glyphs from the
  embedded font (U+2610 unchecked, U+2611/U+2612 checked) when the subset
  contains them; (b) when the font lacks them, draw a vector square via the
  existing canvas path ops plus a check stroke for `.checked`, which avoids a
  glyph-coverage dependency and is the safer default for arbitrary embedded
  fonts. The checkbox is non-interactive (static ink), matching GitHub README
  rendering; do NOT emit an AcroForm widget unless a separate interactive-PDF
  issue asks for it.

## Reference implementations

- cmark-gfm (BSD-2, https://github.com/github/cmark-gfm): canonical GFM extension
  behavior for tasklists and footnotes; study its `extensions/` parsing and HTML
  output for edge cases. Study only, never linked.
- swift-markdown / swift-cmark (Apache-2.0, https://github.com/swiftlang/swift-markdown):
  closest Swift AST shape; `ListItem.checkbox`, `FootnoteReference`,
  `FootnoteDefinition`. It is "powered by cmark-gfm," so model reference, not an
  allowed dependency.
- comrak (BSD-2, https://github.com/kivikakk/comrak): pure-Rust GFM;
  `footnotes`, `inline-footnotes`, `tasklist` options; clean parse/render split.
- pulldown-cmark (MIT, https://github.com/raphlinus/pulldown-cmark): pure-Rust
  pull parser; `TaskListMarker(bool)`, `FootnoteReference`,
  `Tag::FootnoteDefinition` event model, a good fit for flat inline/block output.
- markdown-it + plugins (MIT): markdown-it-footnote
  (https://www.npmjs.com/package/markdown-it-footnote) and markdown-it-task-lists
  (https://www.npmjs.com/package/markdown-it-task-lists) for plugin behavior.

## Witness policy

Follow the existing witness stack (see `complex-script-fixture-witness-policy.md`).
Per fixture that changes PDF bytes:

- `qpdf` structural validation, no warnings.
- Swift structural checks: every `fn-<n>` and `fnref-<n>-<k>` destination
  resolves to a real page object; every footnote/back-link annotation target name
  exists; no dangling `/Dest`.
- Poppler `pdftotext`: footnote markers extract as their numbers; definition text
  extracts in the bottom section; checkbox rows extract their item text (the box
  itself is decoration).
- Poppler `pdftotext -tsv`: superscript marker geometry sits above baseline;
  checkbox glyph aligns in the marker column.
- MuPDF structured text: marker and arrow quads do not overlap surrounding text.
- macOS and Linux both run the same suite.

Fixtures must cover: single ref, repeated refs to one label (multiple
back-arrows), out-of-order definitions, unreferenced definition (dropped),
dangling reference (literal fallback), nested task items, mixed
checked/unchecked, and a non-task `[ ]` that must stay literal. No font binaries
committed; the box-as-vector fallback path must have its own fixture.

## Ordered work

1. #129 (this note) research and boundary.
2. Parser: task-list marker recognition into `ListItem.checkbox`, CommonMark
   behavior otherwise.
3. Parser: footnote reference inline + definition block, no numbering yet.
4. Resolution pass: order, renumber, drop unreferenced, classify dangling.
5. Renderer: superscript marker + destination/link reuse; bottom section with
   back-arrows.
6. Renderer: checkbox marker column with glyph and vector fallback.
7. Witness fixtures and macOS+Linux suite per witness policy.

## Platform notes

All of the above is pure Swift over the existing portable PDF writer; nothing
needs a platform text engine. A macOS adapter could compare superscript metrics
or glyph coverage as research only; macOS results do not imply Linux behavior and
do not imply iOS support. iOS stays unclaimed until an explicit target and
witness suite exist.
