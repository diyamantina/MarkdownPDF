# Long documents: merge, cover, page numbers, and index

Render several Markdown files as one PDF, put a cover in front, number its pages,
and append a back-of-book index.

## Overview

These features cover the shape of a book: many source files, a cover, a table of
contents, page numbers in the footer, and an index at the end. Each is opt-in, and a document
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

## Cover

``PDFOptions/Cover`` makes a full-page picture physical page 1, ahead of the table
of contents. The picture is a PNG or JPEG, supplied as
``PDFOptions/Cover/ImageSource/data(_:)`` (the bytes) or
``PDFOptions/Cover/ImageSource/file(_:relativeTo:)`` (a path resolved against a base
URL you pass in, or the working directory). Both are values; the renderer reads
nothing you did not hand it. It is decoded by the same code as body images, so an RGBA
PNG is composited over white through its soft mask.

**Fit rule.** The image is scaled by `min(pageWidth / imageWidth, pageHeight /
imageHeight)`, so the whole picture shows with its aspect ratio kept, and is centred.
It scales up as well as down, and the margins and ``PDFOptions/imageMaxHeightFraction``
do not apply. When the aspect ratios differ by at most 0.1%, as for an image cut to the
page's proportions (1 : 1.4142 on A4), the image is stretched by that imperceptible
amount to fill the page exactly, so no hairline of paper shows. Otherwise the bars
show the theme's page background, or white.

**Numbering.** The cover has no page number and no footer:

- The first page after the cover is printed page 1, or
  ``PDFOptions/PageNumbers/firstPageNumber``.
- `Page N of M` counts the pages after the cover. ``PDFOptions/PageNumbers/skipsFirstPage``
  refers to the first page after the cover.
- The table of contents and index print those printed numbers when page numbers are
  enabled, and physical numbers (the cover is page 1) when they are not.
- Links, named destinations and the outline address physical pages. The cover is the
  first outline item, titled "Cover", and is not a table of contents entry.

**Tagging.** With tagged PDF or a conformance profile, the cover is a Figure whose
alternate text is "Cover of Title by Author", leaving out whichever of the two is
missing. A missing or undecodable image throws
``MarkdownPDFError/coverImageUnreadable(_:)`` or
``MarkdownPDFError/coverImageUnsupported(_:)``; a cover is never dropped silently.

``PDFOptions/author`` is document metadata written beside the title: `/Author` in the
Info dictionary and `dc:creator` in the XMP packet.

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
