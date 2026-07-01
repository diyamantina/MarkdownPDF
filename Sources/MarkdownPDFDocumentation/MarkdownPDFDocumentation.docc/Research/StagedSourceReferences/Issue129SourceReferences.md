# Issue 129 source references

Staged source and reference materials gathered for issue #129, vendored study-only under `researchcode/`.

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
