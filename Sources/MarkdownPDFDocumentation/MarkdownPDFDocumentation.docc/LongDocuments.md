# Long documents: merge, page numbers, and index

Render several Markdown files as one PDF, number its pages, and append a
back-of-book index.

## Overview

These features cover the shape of a book: many source files, a table of contents,
page numbers in the footer, and an index at the end. Each is opt-in, and a document
that uses none of them renders byte-for-byte as before.

## Merging sources

``MarkdownPDFRenderer/render(sources:startsEachSourceOnNewPage:)`` lays several
``MarkdownSource`` values out as one document. Every source carries its own
``MarkdownSource/assetsBaseURL``, so `![alt](../figures/a.png)` in two files names
two different images with no path rewriting.

- **Page breaks.** Each source after the first starts on a fresh page unless
  `startsEachSourceOnNewPage` is `false`. A source that would begin on an
  untouched page leaves no blank page.
- **Headings.** All headings share one destination namespace. A heading text that
  repeats across files gets the same `-2`, `-3` suffixes a repeated heading inside
  one file gets, so internal links and the outline stay unambiguous.
- **Footnotes.** Labels are scoped to their source: `[^1]` in two files are two
  footnotes. They are numbered consecutively in reference order and listed once,
  after the last source. A reference whose definition lives in another source stays
  literal text.
- **Title.** The PDF title is ``PDFOptions/title``.
- **One source.** `render(markdown:assetsBaseURL:)` is the one-source case of the
  same path, and its output is unchanged.

## Page numbers

``PDFOptions/PageNumbers`` draws a footer in the bottom margin of every page.

| Setting | Values |
|---|---|
| ``PDFOptions/PageNumbers/position`` | `.bottomCenter`, `.bottomOutside` (right on odd printed numbers, left on even), `.bottomRight` |
| ``PDFOptions/PageNumbers/format`` | `.plain` (`3`), `.ofTotal` (`Page 3 of 12`), `.romanLowercase` (`iii`) |
| ``PDFOptions/PageNumbers/firstPageNumber`` | printed number of page one, default `1` |
| ``PDFOptions/PageNumbers/skipsFirstPage`` | no footer on the first page; it still counts |

The footer uses `0.8 * baseFontSize` in the regular font role, so documents that
embed fonts (including the automatically selected DejaVu) draw it in the same face
as their body. It is centred vertically in the bottom margin and never enters the
body area; a bottom margin smaller than twice the footer size throws
``MarkdownPDFError/pageNumbersNeedBottomMargin(minimum:actual:)``. With tagged PDF or
a conformance profile it is written as an artifact.

In `.ofTotal`, `N` is the printed number of the last page, `firstPageNumber +
pageCount - 1`. Footers are drawn after layout, in the margin, so they cannot move
content: the page count they print is exact without an extra layout pass. The table
of contents and index print the same labels (plain decimal for `.ofTotal`), so a
custom first number or Roman front matter stays consistent everywhere. Internal links
always target the physical page.

## Index

``PDFOptions/Index`` appends an index after the last page of content. Entries come
from two sources and merge when their folded terms are equal.

**Markers.** `{{index: term}}` in the Markdown text records the term on the page the
marker lands on and draws nothing. `{{index: main > sub}}` makes a sub-entry (the
text is split at the first `>`). A marker with an empty term is ignored: it renders
nothing and records nothing. Markers are recognized only while the index is enabled;
otherwise the text is literal. Inside fenced code and inline code they are literal.
A paragraph made only of markers takes no space and attaches to the next line drawn,
so it lands on the page that line lands on.

**Term list.** ``PDFOptions/Index/terms`` are matched as whole words, ignoring case
and diacritics, in paragraphs, list items, table cells, block quotes, and headings.
Only letters and digits continue a word, so `layer` matches in `(layer)`, `layer's`
and `layer-tree` but not in `layers`. A multi-word term matches across any whitespace,
including a line break, and counts on the page of its first word. Code blocks, inline
code, math, link destinations, footnote reference numbers, the table of contents, and
the index itself are not searched. A term that wraps across a page break inside a
single table cell is not seen.

**Order.** The index never uses platform locale collation, which differs between
Apple platforms and Linux. A term is folded by canonical decomposition, default
Unicode lowercasing, dropping combining marks, folding the undecomposable Latin
letters (`ae`, `oe`, sharp s, o with stroke, l with stroke, d with stroke, eth, thorn,
h with stroke, t with stroke) to ASCII, and collapsing whitespace. Folded terms
compare by Unicode scalar value, so punctuation sorts before digits before letters,
and letters of one script sort in code point order. Entries that fold equal are one
entry; if their spellings differ the first one seen is shown. Ties between distinct
spellings are broken by scalar value, so the order never depends on input order.
The fold uses the Unicode data of the Swift toolchain in use.

**Layout.** Entries sit under letter headings (`#` for digits and symbols). Each page
reference is an internal link, printed with the document's page labels; runs of
consecutive pages collapse to a range with an ASCII hyphen (`12-14`), and a range
links to its first page. Sub-entries are indented. The heading is an ordinary
level-one heading named by ``PDFOptions/Index/title``, so it appears in the outline
and, when enabled, in the table of contents with its page number. When nothing was
found, no index is written.

## How the passes converge

The table of contents carries page numbers and occupies pages; the index records
which pages terms landed on and is appended after the body. The renderer lays the
document out, derives both again from the result, and repeats until a pass reproduces
its own input, at most six passes, then throws
``MarkdownPDFError/tableOfContentsDidNotConverge(maxPasses:)``. Decoded images are
cached for the duration of one render, so extra passes do not re-read figures.

## Conformance

PDF/UA-1 and PDF/A-2a output with page numbers validates in veraPDF. The generated
table of contents and index contain link annotations, which those profiles reject for
lack of `/Contents` and tagging; this is a property of the existing link output, not of
page numbers.
