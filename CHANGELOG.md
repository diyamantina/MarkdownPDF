# Changelog

All notable changes to MarkdownPDF are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Hebrew shaping: composition and niqqud positioning. Pointed Hebrew now composes its
  presentation forms (shin dot, sin dot, letter+dagesh) and places the vowel points on
  their letters, instead of drawing the marks at nominal positions. A new Hebrew shaper
  reorders the letter-modifying marks (dagesh, shin/sin dot) next to their consonant,
  composes them with GSUB `ccmp` (reusing the shared GSUB applier the Arabic path uses),
  and attaches the remaining niqqud with the `hebr`-script GPOS mark lookups (reusing the
  shared mark positioner); a pointed run is shaped whole and drawn right-to-left with
  `/ToUnicode` preserved, while an unpointed run stays on the ordinary path unchanged.
  Verified against `hb-shape`: every one of 999 letter-and-mark combinations (each
  consonant with each niqqud, and each vowel stacked with meteg or dagesh) matches glyph
  and offset exactly. A composed base+mark glyph drawn right-to-left in visual order would
  make a text extractor place the point before its letter (the composed glyph's
  multi-scalar `/ToUnicode` is reversed with the run); such a run now carries an
  `/ActualText` override so `pdftotext` and `mutool` recover the letter before its point.
  The override text is stored in visual (reversed) order on purpose: every extractor that
  honors `/ActualText` re-applies bidi to the replacement text, so logical order would
  extract fully reversed. Two caveats follow from this. A reader that consumes
  `/ActualText` verbatim without re-ordering (a strictly spec-conforming consumer, and
  possibly assistive technology) would read a composed run reversed; this trades a
  guaranteed-wrong extraction in the common tools for a possible-wrong extraction in a
  strict one. And `mutool`/PyMuPDF, which do not re-bidi a lone base+mark pair, place the
  mark before the letter for a single composed cluster on its own (e.g. a bare בּ), and
  occasionally add a duplicated word or a mid-word space around a composed cluster; both
  words remain present and searchable after Unicode normalization
  ([#53](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/53)).
- GPOS type-8 chained-context positioning, closing the last Hebrew placement gaps. The
  mark positioner now runs the `mark` feature's chained-context (type 8) lookups in
  feature order after base attachment, matching each on the glyphs before, at, and after a
  position and applying the nested lookup it selects: a type-1 single adjustment (holam
  after a bare consonant is nudged 25 units, so holam haser matches the reference instead
  of sitting 25 units off), a type-4 re-anchor (a vowel and meteg under one letter split
  apart instead of stacking at one anchor), or a type-2 pair adjustment. The reader gained
  single (type 1), pair (type 2), and chained-context (type 3 subtable) parsing with a
  value-record decoder. A font whose mark feature has no type-8 lookup (Noto Naskh Arabic
  has none) finds nothing to run, so Arabic positioning is byte-identical; verified with a
  999-combination `hb-shape` sweep at zero divergences
  ([#53](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/53)).
- Canonical ordering of the core Arabic harakat before shaping. When the short vowels,
  tanwin, shadda, or sukun (U+064B..U+0652) are typed out of order (e.g. shadda before a
  vowel), they are reordered by combining class before shaping so they stack the way the
  reference shaper stacks them. A generated table carries the combining class for every
  non-zero-class scalar (Unicode 17.0.0); the ordering is a stable per-mark-run sort that
  never crosses a starter and performs no decomposition. Only runs made up entirely of the
  core harakat are reordered: HarfBuzz orders other marks (hamza, the Quranic annotation
  marks, subscript alef) by UTR #53 rather than raw combining class, so a run containing
  one is left in typed order to match the reference exactly. Extraction recovers the
  reordered (canonically-equivalent) mark order. Verified against `hb-shape` over an
  816-case sweep (harakat, modifier, and Quranic marks in both orders on several bases):
  24 placements fixed, zero regressions versus the prior behavior
  ([#48](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/48)).
- Arabic `ccmp` mark composition and GSUB `IgnoreMarks`. Two refinements that bring
  vocalized Arabic closer to the reference shaper. The contextual matcher now honors the
  `IgnoreMarks` lookup flag, skipping harakat when matching, so a vocalized lam-alef
  (لَا) gets the same contextual refinement as the unvocalized form. And the `ccmp`
  feature is now applied, so a font that provides one glyph for a mark combination (e.g.
  shadda + vowel) composes it instead of drawing two marks; the composed glyph is then
  placed by GPOS. Verified against `hb-shape` across a 253-word sweep (every harakat on
  23 base letters, plus shadda + vowel combinations) with zero divergences, and مُحَمَّد
  (which previously diverged) now composes and positions correctly. Input that needs
  canonical combining-class reordering first still diverges and is a tracked follow-up
  ([#48](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/48)).
- Arabic GPOS mark positioning: combining marks now sit precisely on their letters.
  Before, harakat (Arabic vowel marks) and niqqud were drawn at the pen with no
  attachment, so vocalized text was legible but not typographically placed. A new GPOS
  reader parses the `mark` (mark-to-base) and `mkmk` (mark-to-mark) format-1 lookups
  into anchor tables; the shaper attaches each mark to its base (and stacks a mark on a
  preceding mark) at the offset `targetAnchor - markAnchor`, and the render path draws
  each positioned glyph with a text-line move off the baseline. A run with no mark
  offsets is still shown in a single operator, byte-identical to before. Verified
  against `hb-shape`: the shaped offsets match glyph for glyph across vocalized words
  (single harakat, a six-mark word, and a genuine two-superscript-alef stack exercising
  `mkmk`), and vocalized Arabic renders with marks on their bases while `/ToUnicode`
  still recovers the vowels. One caveat: because a positioned run shows each glyph in
  its own operator, Poppler's `pdftotext` inserts spurious spaces inside it (its word
  segmentation keys off the per-glyph moves); extractors that honor `/ToUnicode` (mutool,
  Preview, Acrobat) recover the text intact
  ([#48](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/48)).
- Arabic contextual (GSUB type 5/6) lam-alef refinement. Before, lam-alef collapsed to
  the canonical single presentation ligature (uniFEFB/uniFEFC); a font like Noto Naskh
  refines it with a coverage-based contextual `rlig` lookup into its own two-glyph pair.
  The shaper now runs the `rlig` feature's lookups in LookupList order (the type-5
  contextual refinement, then the type-4 ligature) over the shaped buffer, so lam-alef
  (لا لأ لإ لآ) and words like سلام match `hb-shape` glyph for glyph, both in the shaping
  core and end to end through the renderer, with each output glyph keeping its own source
  scalar for `/ToUnicode`. A new GDEF glyph-class reader and shared OpenType ClassDef
  reader back the contextual matcher. Scope: coverage-based (format 3) lookups with
  nested single substitutions; mark skipping (IgnoreMarks) and contextual formats 1/2
  (glyph- and class-based, including `ccmp` mark composition) are deferred, so a
  contextual match across an interposed mark is conservatively missed rather than
  mis-made ([#48](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/48)).
- Arabic (cursive) shaping core: the joining algorithm plus GSUB positional forms.
  Before, Arabic rendered in disconnected isolated letters. The shaper resolves each
  letter's positional form (isolated/initial/medial/final) from the Unicode joining
  algorithm (authoritative `DerivedJoiningType` data for every cursive script), then
  applies the font's `isol`/`init`/`medi`/`fina` single substitutions and `rlig`
  ligatures (lam-alef) through a new general GSUB reader (lookup types 1 and 4,
  script `arab`). The glyph ids match HarfBuzz exactly within that scope, verified by
  a differential test against `hb-shape`. Contextual shaping (GSUB type 5/6, e.g.
  Noto's stylistic lam-alef) and GPOS mark positioning are deferred, as is wiring the
  shaper into the render path with RTL ordering; today this is the
  independently-tested shaping core
  ([#42](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/42)).
- Embedding a face from a TrueType/OpenType Collection (`.ttc`/`.otc`). A collection
  was rejected outright, which blocked embedding the system fonts that cover CJK,
  Arabic, and Hebrew (they ship as collections). The parser now reads the `ttcf`
  header and follows the selected face's directory offset; because table records
  carry absolute file offsets, glyph mapping and subsetting are unchanged.
  `PDFOptions.EmbeddedFontSource` gains a `faceIndex` (default 0) to pick the face,
  and an out-of-range index reports a typed error. Algorithm grounded in the
  reference-engine corpus (reportlab, openpdf, libharu, hexapdf)
  ([#41](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/41)).
- Embedding OpenType fonts with PostScript (CFF, Adobe Type 2) outlines (`OTTO`),
  which most CJK system fonts use instead of `glyf`. Such a font was rejected outright;
  it now embeds and renders. A new `CFF ` table reader parses the header, Name and Top
  DICT INDEXes, the CharStrings INDEX (glyph count), and the charset, and detects
  CID-keyed fonts from the `ROS` operator, exposing each glyph id's CID. A CID-keyed
  CFF (the CJK shape) is embedded whole as a `CIDFontType0` descendant font with a
  `CIDFontType0C` `FontFile3`, and the content stream addresses each glyph by the CID
  its charset assigns, which the viewer maps back through the embedded CFF's own
  charset (so there is no `CIDToGIDMap`). A name-keyed (non-CID) CFF embeds as a
  `CIDFontType0` with an `OpenType` `FontFile3`: a single-face source is embedded whole,
  and a face inside a collection is first reconstructed into a standalone single-face
  sfnt. It is never emitted as a bare `Type1C` program, which under a `CIDFontType0`
  descendant is a composite/simple mismatch that fails PDF/A and PDF/UA validation.
  Widths (`/W`) and `/ToUnicode` are emitted as on the `glyf` path. Every CFF read is
  bounds-checked and malformed input throws a typed error rather than trapping. Verified
  end to end against a system CJK font and a system name-keyed CFF: `qpdf --check` and
  `mutool clean` pass, `pdftotext` recovers the characters, a Poppler-vs-MuPDF raster
  witness confirms real glyphs with correct widths, and veraPDF reports the
  collection-face path compliant with PDF/A-2a and PDF/UA-1. Whole-font only for now:
  charstring subsetting (to shrink the embedded program) and de-duplicating an identical
  font program shared across roles (a heading and body role currently embed one copy
  each) are tracked optimizations. The `glyf` embedding path is byte-for-byte unchanged.
  Grounded in the Adobe CFF and Type 2 Charstring specs and PDF 32000-1 §9.7.4
  ([#49](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/49)).

### Fixed
- Embedding a font with non-spec table checksums no longer fails. Apple system
  fonts routinely ship incorrect `head`/table checksums, so strict validation
  rejected them (`invalidTableChecksum`) even though they are structurally valid
  and the embedder subsets and rebuilds the font anyway. Table-checksum validation
  is now opt-in (`parse(validateChecksums:)`, default off, matching reference
  engines); the structural bounds checks and per-table parsers still reject
  genuinely corrupt fonts. Combined with the collection support, real macOS system
  fonts (e.g. Apple Symbols, and the Armenian Mshtakan collection) now embed
  ([#43](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/43)).
- Heading anchor slugs are stable across Unicode normalization forms, so an
  internal link resolves whether the heading or the link was authored precomposed
  or decomposed. The slug generator kept the ASCII base of a decomposed accent
  (`e` + U+0301 → `cafe`) but dropped a precomposed one wholesale (`é` → nothing),
  so `# Café` slugged to `caf-du-monde` or `cafe-du-monde` depending on the source
  bytes. It now decomposes and drops the combining marks, folding an accented
  letter to its ASCII base for both forms (`café` → `cafe`, `naïve` → `naive`,
  `čokolada` → `cokolada`), with an explicit fold for the Latin letters that carry
  no canonical decomposition (`đ` → `d`, `ø` → `o`, `ł` → `l`, `æ` → `ae`,
  `ß` → `ss`), and applies the same folding to link targets. Because folding maps
  more headings onto the same base, generated destination names are now checked for
  uniqueness against the names already issued rather than a per-base counter, so a
  later heading whose slug equals an earlier disambiguation (`Cafe 2` after
  `Café`/`Cafe`) no longer emits a duplicate `/Dests` key. Note that folding two
  visually distinct headings (`Café` and `Cafe`) to the same base makes a bare
  `#cafe` link resolve to the first; the second is reachable only via its
  disambiguated `#cafe-2`
  ([#39](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/39)).
- Decomposed (NFD) diacritics no longer render their combining mark as `?` on the
  base-14 path. `WinAnsiEncoding` has the precomposed accented letters but no
  combining marks, so a sequence like `e` + U+0301 (the form macOS and many web
  sources produce) drew the base letter and then `?`. NFC normalization now folds
  the sequence to the single precomposed WinAnsi byte at the two base-14
  chokepoints: `PDFSyntax.LiteralString.serialized` for every emitted WinAnsi text
  string (page content and `/ActualText`, and also the outline and Info `/Title`,
  named destinations, and tagged `Alt`, which bypass the run path) and
  `PDFTextEncoding.portableScalars` for the matching measured width. So the glyphs,
  the width, the copied text, and the bookmarks all agree, and the NFD forms of
  `š`, `ž`, `à`, `ü`, and the like now render too. The embedded path reads
  `run.text` directly and is unaffected, so its shaper keeps attaching marks.
  Characters with no WinAnsi form even when precomposed (Croatian `č`, `ć`, `đ`)
  still need an embedded font; a decomposed one now folds to that single
  unrepresentable scalar and prints one `?` (matching the precomposed form) instead
  of leaving the base letter visible
  ([#37](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/37)).
- A font that resolves a real character to glyph 0 (`.notdef`) no longer slips a
  `.notdef` reference into content. In `cmap` format 4 the `idRangeOffset == 0`
  branch returned `code + idDelta` without a zero check (and the glyph-array branch
  checked only the pre-`idDelta` value), and format 12 returned a group's computed
  id without checking for 0; separately, a GSUB ligature substitution whose output
  glyph is 0 was applied instead of dropped. Either way a character mapped to
  `.notdef` made `covers(_:font:)` report it covered while it rendered `.notdef`,
  and under a conformance profile shipped a document referencing `.notdef` in
  content while claiming PDF/UA-1 or PDF/A-2a. Both format-4 branches and the
  format-12 path now report a resolved glyph 0 as absent, and a ligature rule whose
  output is `.notdef` is dropped so the cluster renders un-ligated, so the
  missing-glyph policy and the coverage probe handle every route correctly
  ([#35](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/35)).
- A visible scalar the embedded font's cmap lacks (an emoji, a CJK glyph the
  subset omits, a stray combining mark) no longer aborts the whole document. The
  glyph mapper's default `.reject` policy threw `missingGlyph` and dropped every
  page; in a plain PDF the render path now maps that one scalar to the font's
  `.notdef` glyph while the strict `.reject` probe stays in `covers(_:font:)` so
  math-symbol transliteration is unchanged. Because every `.notdef` occurrence
  shares PDF character code 0, distinct missing scalars would collide in the
  `/ToUnicode` CMap, so a `.notdef` glyph contributes no mapping (the unrenderable
  scalar drops from text extraction while the rest of the page is preserved), and
  a font resource that draws nothing but `.notdef` omits `/ToUnicode` entirely
  rather than trapping on the empty-CMap precondition. Under a PDF/UA-1 or
  PDF/A-2a profile the fallback is disabled and a missing glyph still refuses,
  because those profiles forbid referencing `.notdef` in content, so the notdef
  fallback would ship spec-violating output under a conformance claim
  ([#33](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/33)).
- Invisible default-ignorable format controls no longer abort an embedded-font
  render or paint `?` on the base-14 path. A zero-width space, joiner, non-joiner,
  word joiner, soft hyphen, variation selector, Hangul filler, or tag character
  whose glyph the embedded font's cmap omits made `TrueTypeGlyphMapper` throw
  `missingGlyph` and drop the whole document. Per Unicode these render invisibly,
  so they are stripped from page-text runs before either font path measures or
  encodes them, generalizing the BOM strip from #27. The strip is deliberately
  narrow: the explicit bidi controls stay with `BidiParagraphOrdering` (which
  refuses text it cannot order rather than reorder it wrongly), and the
  line/paragraph and interlinear-annotation separators stay in place because
  deleting them would fuse the words or annotations they delimit. The
  outline/document `/Title` encoding is a separate path and still substitutes `?`
  there ([#29](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/29),
  [#33](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/33)).
- Base-14 advance widths now match the Adobe Core-14 AFM metrics for the whole
  WinAnsi set. Any non-ASCII WinAnsi scalar that was neither hand-listed nor
  ASCII-decomposable (Æ, ß, ½, Ø, the superscripts, the ordinals) measured at the
  width of ? (556), so a line of them overran the page and, on the embedded path,
  wrote wrong values into /Widths and overlapped. The tables are generated from the
  AFM files through the WinAnsi encoding vector, per face (bold differs from
  regular at 31 code points), and the ASCII quote and grave advances are corrected
  to their true metrics ([#30](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/30)).
- A chart or pie slice value large enough to overflow the geometry no longer
  crashes the renderer. `2 * pi * value` overflowed to Inf and `Inf / total` gave
  NaN, which trapped in `Int(NaN)` (arc segment count) and `Int(value.rounded())`
  (legend formatter). A finiteness guard at PDF number serialization also stops any non-finite coordinate
  from reaching the content stream as an unparseable nan/inf token ([#22](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/23)).
- Deeply nested lists and block quotes no longer explode the page count. Each list
  level added 24pt and each quote 14pt of indent unclamped; past the page width the content column went negative and every
  token landed on its own near-empty page, so a few KB of markdown produced
  hundreds of pages. The indent is capped so a usable column always remains
  ([#24](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/25)). Shallow lists
  are unchanged.

- A link or image whose destination ends in a stray `"` (`[a](")`,
  `[site](https://example.com")`) no longer crashes the renderer. The trailing
  quote was mistaken for a title close, building an inverted string range. A title
  is now taken only from a distinct opening quote before the closing one; otherwise
  the quote belongs to the destination
  ([#19](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/19)).

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

- Block quotes honor `backgroundColor` from their `.blockQuote` theme role. The
  fill is inserted just above the page background rather than appended, because a
  quote's height is unknown until its blocks have rendered and its text is already
  in the content stream by then
  ([#10](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/10)). Nested quotes
  stack, page-spanning quotes get one fill per page, and the fill is a tagged
  artifact so PDF/UA-1 still passes.

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
- A byte-order mark (U+FEFF) in text no longer aborts the render. The embedded-font
  path classified it as an Arabic presentation form and threw
  `unsupportedComplexScriptScalar`; the base-14 path drew it as `?`. It is invisible
  formatting and is stripped, at the scalar level, from drawn page text on both
  paths (document metadata such as outline titles is a separate encoding path)
  ([#27](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/27)).

- A run of unmatched inline openers (`[[[…`, `![![…`, `<<<…`, `[a]([a](…`) no longer
  parses in O(n^2) time. Each failed opener scanned to the end of the source while
  the loop advanced one character, so a few KB of one byte wedged the parser for
  seconds. A memo of "this close character is absent from here on" makes it linear;
  a 40 KB run now parses in milliseconds. Output is unchanged.
- A link or image whose destination ends in a stray `"` (`[a](")`,
  `[site](https://example.com")`) no longer crashes the renderer. The trailing
  quote was mistaken for a title close, building an inverted string range. A title
  is now taken only from a distinct opening quote before the closing one; otherwise
  the quote belongs to the destination
  ([#19](https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/19)).

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
