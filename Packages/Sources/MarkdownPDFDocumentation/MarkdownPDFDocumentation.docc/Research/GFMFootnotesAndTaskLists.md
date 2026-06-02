# GFM footnotes and task-list checkboxes

Date: 2026-06-02. Issue: #129. Status: implementation guidance and source
references. The #129 implementation uses document-end footnotes and static
vector task-list checkboxes in the portable Swift renderer.

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
order of first reference. MarkdownPDF v1 links each definition number back to
the first reference site, which satisfies issue #129. Multiple back-links for
repeated references remain a compatible extension point.

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
  `case footnoteDefinition(label: String, blocks: [MarkdownBlock])`. This
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
  register `fnref-<n>` at the first marker site for the definition backlink.
- Footnote section: after the last body block, emit a thematic-break-style
  separator then a definition list. Each row starts with the number linked back
  to `.destination(name: "fnref-<n>")`, the first marker site. Same
  destination+annotation machinery as heading links; no new PDF object types.
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
- Swift structural checks: every `fn-<n>` and `fnref-<n>` destination
  resolves to a real page object; every footnote/back-link annotation target name
  exists; no dangling `/Dest`.
- Poppler `pdftotext`: footnote markers extract as their numbers; definition text
  extracts in the bottom section; checkbox rows extract their item text (the box
  itself is decoration).
- Poppler `pdftotext -tsv`: superscript marker geometry sits above baseline;
  checkbox glyph aligns in the marker column.
- MuPDF structured text: marker and arrow quads do not overlap surrounding text.
- macOS and Linux both run the same suite.

Fixtures must cover: single ref, repeated refs to one label with first-reference
backlink, out-of-order definitions, unreferenced definition (dropped),
dangling reference (literal fallback), nested task items, mixed
checked/unchecked, and a non-task `[ ]` that must stay literal. No font binaries
committed; the box-as-vector fallback path must have its own fixture.

## Ordered work

1. #129 (this note) research and boundary.
2. Parser: task-list marker recognition into `ListItem.checkbox`, CommonMark
   behavior otherwise.
3. Parser: footnote reference inline + definition block, no numbering yet.
4. Resolution pass: order, renumber, drop unreferenced, classify dangling.
5. Renderer: superscript marker + destination/link reuse; document-end section
   with a backlink to the first marker.
6. Renderer: checkbox marker column with vector square plus check stroke.
7. Witness fixtures and macOS+Linux suite per witness policy.

## Platform notes

All of the above is pure Swift over the existing portable PDF writer; nothing
needs a platform text engine. A macOS adapter could compare superscript metrics
or glyph coverage as research only; macOS results do not imply Linux behavior and
do not imply iOS support. iOS stays unclaimed until an explicit target and
witness suite exist.


## Reference implementations (vendored in `researchcode/`)

Three engines implement real page-bottom footnote layout; the algorithm to port is SILE's "insertions" model. (Scribus has no footnote layout: `pageitem_textframe.cpp` is absent of it.) Task-list checkboxes are a trivial list-marker swap; reuse the existing list-marker drawing.

SILE (Lua, MIT) - the model to translate:
- `researchcode/sile/packages/insertions/init.lua` - `processInsertion()` (~L314-440): the core fits/split/migrate decision; `setShrinkage`/`commitShrinkage` (~L243-276) + `increaseInsertionFrame` (~L278-291): body-text frame shrinks from the bottom, footnote frame grows from the top; `nextInterInsertionSkip` (~L179-193): first note gets the separator/topBox, later notes get the inter-insertion skip.
- `researchcode/sile/packages/footnotes/init.lua` - `footnotemark` + `footnote:counter` + `self.class:insert`: single monotonic counter, superscript mark, `N.`-prefixed entry.

Typst (Rust, Apache-2.0) - corroborating reflow/spill:
- `researchcode/typst/crates/typst-layout/src/flow/compose.rs` - `Composer::footnote()` / `footnotes()` / `layout_footnote()` (~L356-540): spill+queue+migrate reflow; `loc.variant(1)` derived-id links the mark to the entry without a query (directly relevant to the link-annotation step). `is_ref()` handles multi-reference.
- `researchcode/typst/crates/typst-layout/src/rules.rs` - `FOOTNOTE_RULE` / `FOOTNOTE_ENTRY_RULE` (~L385-403): mark = superscript link, entry = indent + number + gap + body.

WeasyPrint (Python, BSD-3) - CSS `@footnote`:
- `researchcode/weasyprint/weasyprint/layout/page.py` (~L602-706): bottom-anchored `FootnoteAreaBox`, replays deferred `reported_footnotes` first.
- `researchcode/weasyprint/weasyprint/layout/__init__.py` `_update_footnote_area` (~L381-420): pushes `page_bottom` up by the area height (analog of SILE shrink/grow); `block.py` honors `footnote-policy: line|block` to avoid orphaning a reference from its note.
- `researchcode/weasyprint/weasyprint/css/html5_ua.css` (~L144-191): declarative numbering/marker spec (`::footnote-call`, `::footnote-marker`, `@footnote{margin-top:1em}`).

Translating to the pure-Swift engine (which already has `PDFNamedDestinations`, `PDFLinkAnnotation`, `PDFHeadingDestination`, list layout): reserve a bottom band per page and shrink body height into it; one monotonic counter; superscript mark with a GoTo link to a named dest at the entry, plus a back-arrow (U+21A9) link from the entry to the mark; on overflow split the note or migrate the reference line (the footnote invariant); separator + skips before/between notes. Checkbox: swap the list bullet for U+2610/U+2611 or a vector square+check.

Spec anchors: CommonMark 0.31.2, GFM spec (task-list extension), GitHub footnote docs (footnotes are a GitHub renderer extension).
