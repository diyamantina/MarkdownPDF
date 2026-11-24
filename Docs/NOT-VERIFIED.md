# Not verified

The test suite checks rendered PDFs with code that lives in this package and
nothing else: `PDFDocumentReader` (in `Sources/MarkdownPDF`) and the byte
inspectors of the test target (`PDFInspector`, `ContentStreamGeometry`,
`PDFImageObjects`). No program outside the package is run by a test, a script, a
hook or a workflow to produce, read, measure, render or convert a PDF or an image.

Some properties cannot be checked that way yet. A test for such a property is
kept, carries a `.disabled("not verified: ...")` trait that names this file, and
calls `PDFValidation.notVerified`, which records an issue. It does not run. If
the trait is removed before the missing capability exists, the test fails; it
cannot pass without checking anything.

Find them all with:

```sh
grep -rn 'not verified:' Tests
```

This file is the list. Keep it in step with the code: a row goes when its test is
enabled and really checks the property, and a row is added when a test is demoted.

## Not verified: needs a rasterizer inside MarkdownPDF

The package writes PDF and reads its own PDF back. It cannot turn a page into
pixels. These tests need pixels.

What would restore them: a rasterizer in the package that draws a page of the
engine's output to a bitmap: path fills and strokes, images with soft masks, and
glyph outlines from the embedded TrueType and CFF programs and from metrics-only
base fonts. With one rasterizer, "ink on the page" and "the composited colour of a
pixel" become checkable. The comparisons of two rasterizers would still need a
second, independent one, or would be restated as a comparison of the raster with
the geometry the reader reports.

| Suite | Test | What it checked, with which tool | Cases |
|---|---|---|---|
| `PDFVisualLayoutValidationTests` | Every page of a witness PDF rasterizes to comparable ink | `pdftoppm` (Poppler) and `mutool draw` (MuPDF) drew every page. Both images had to have the same size, each had to hold at least 1000 pixels of ink, and the ink bounds of the two had to overlap by 85%. This was the last step of 16 witness tests and the whole of the former test "Poppler and MuPDF render comparable ink bounds". | 17: `visual-layout`, `syntax-coloring-manuscript`, `rtl-manuscript`, `article-grade-stress`, `hard-markdown-corpus`, `crazy-markdown-torture`, `a4-manuscript`, `text-encoding-profile`, `embedded-cid-text`, `cjk-diacritics-manuscript`, `embedded-font-public-api`, `oversized-blocks`, `measured-tables`, `native-charts`, `diagram-policy`, `source-code-spacing`, `screenshot-source-code-regressions` |
| `ShowcaseFixtureTests` | Every page of a showcase fixture rasterizes to comparable ink | The same comparison of `pdftoppm` and `mutool draw`, as the last step of the embedded-font witness on each showcase fixture. | 8: every file in `Fixtures/showcase` |
| `CFFRenderIntegrationTests` | The glyphs of an embedded CFF font rasterize to comparable ink | The same comparison. It was the only check that the glyph outlines of an embedded CFF program can be drawn at all. | 3: `cff-cid-keyed-cjk`, `cff-name-keyed-latin`, `cff-name-keyed-collection` |
| `MarkdownPDFRendererTests` | Pages of the renderer witnesses rasterize | For `open-font-fixture` and `multilingual-corpus`, the same comparison of two rasterizers. For `png-image`, `pdftoppm -png` drew the first page and the image had to have a size. | 3 |
| `FixtureTests` | The first page of a fixture rasterizes to an image | `pdftoppm -png` drew the first page of each fixture and the PNG had to have a width and a height. | 4 groups: the article-grade fixtures, the WWDC large stress fixture, the external fixtures (US patent, WWDC ray tracing), the manuscript fixtures (Formidabble, App Intents) |
| `PDFReadBackValidationTests` | A rasterizer renders the minimal PDF page | `pdftoppm -png` drew the one page of a minimal document and the PNG had to have a size. Formerly "pdftoppm renders minimal PDF page" in `PDFToolValidationTests`. | 1 |
| `PNGImageRenderTests` | A rasterizer composites the soft mask over white | `pdftoppm` and `mutool draw` drew an RGBA image; the centre pixel of each quadrant had to be the colour blended with white by the alpha, within 3 levels. Formerly "Poppler and MuPDF composite the soft mask over white". | 1 |
| `CoverPageTests` | Rasters composite an RGBA cover over white | The same blend, for a cover image with alpha 128, from both rasterizers. | 1 |
| `CoverPageTests` | Two rasterizers leave ink on every page of a cover document | `pdftoppm` and `mutool draw` drew every page at 36 dpi; no page could be blank and the ink of the cover had to start at the top left pixel. Formerly "Poppler and MuPDF agree on every page of a cover document". | 1 |

## Not verified: needs a PDF/A and PDF/UA validator inside MarkdownPDF

These tests ran veraPDF over the whole file and required `"compliant" : true` for
the flavour `2a` (PDF/A-2a), `ua1` (PDF/UA-1), or both.

What would restore them: a validator in the package that implements the rules of
ISO 19005-2 level A and ISO 14289-1 against the object graph the reader already
walks: fonts (program, widths, CIDSet, encodings, ToUnicode), colour (device
spaces against the output intent, the ICC profile), metadata (XMP schemas and
their agreement with the Info dictionary), the structure tree (standard types,
role mapping, the parent tree against the marked content of every page, artifacts),
annotations, transparency, and the file trailer.

| Suite | Test | What it checked | Cases |
|---|---|---|---|
| `BundledFontsTests` | Automatic DejaVu preserves PDF/UA-1 and PDF/A-2a conformance | veraPDF `2a` and `ua1` on a document whose symbols select the bundled faces. | 1 |
| `PageNumberTests` | PDF/UA-1 and PDF/A-2a output with page numbers validates | veraPDF `ua1` and `2a` on five pages with "Page N of M" footers. | 1 |
| `VerticalTextBlockTests` | A tagged vertical block is PDF/UA-1 and PDF/A-2a conformant | veraPDF `ua1` and `2a` on a tagged vertical text block. | 1 |
| `CoverPageTests` | PDF/UA-1 and PDF/A-2a validate with a cover, page numbers and an author | veraPDF `ua1` and `2a` on a document with a cover image. | 1 |
| `PDFTaggedContentTests` | A conformance profile render passes a full validation of the profile | The veraPDF step of four tests: "Renderer writes a PDF/UA-1 profile when requested" (`ua1`), "Renderer writes a PDF/A-2a profile when requested" (`2a` and `ua1`), "Tagged RTL profile preserves logical reading order" (`ua1`), "Tagged CJK profile preserves logical reading order" (`2a` and `ua1`). | 6 |

What is still checked for each of these documents, exactly, from the file
(`PDFValidation.conformancePrerequisiteIssues`): the XMP packet declares the
profile (`pdfaid:part` 2 with `pdfaid:conformance` A, `pdfuaid:part` 1); for
PDF/A an output intent `GTS_PDFA1` with an identifier and an embedded profile of 3
components; every font the pages use is embedded; the catalog marks the document
as tagged and the structure tree is one `Document` element with page content
under it; for PDF/UA a title, the request to show it, a language, and an alternate
description on every `Figure`. This says which required fact is missing. It does
not say a file conforms. The check itself is held to a plain render, which it
must reject with each missing fact named.

## A defect the migration found

`ShowcaseFixtureTests`, fixture `05-charts-dashboard.md`: the line chart "Temps de
rendu (ms)" has x values 1 to 16, and its x axis draws the tick labels 0, 5, 10,
15 and 20. The label "20" is placed at x 639 on a page 612 points wide, and the
label "0" lands left of the y axis labels. The reader reports the word box
outside the page. The extractor used before drops text outside the page, so the
old test never saw it. The test recorded this as a known issue
(`withKnownIssue`) scoped to that fixture and that word.

Fixed since (issue 64): the axis of a line chart draws only the ticks inside its
range, here 5, 10 and 15, and no tick label of a chart leaves the chart's frame.
The known issue marker is removed and the test holds every chart label of the
showcase inside its chart's frame. `ChartTickLabelTests` compares the drawn
labels with an answer key over enumerated and seeded charts.

## What was migrated

| Was checked with | Is checked with |
|---|---|
| `qpdf --check` (structural validity) | `PDFDocumentReader.structureIssues(in:)`: every object the cross-reference table lists is read where the table says it is, carries its number, parses, ends with `endobj`; every stream ends where `/Length` says and decodes; every reference names an object in the file; each page tree node counts its pages and each child names its parent; `/Size` covers every object; the file ends with `%%EOF`; the whole document reads. Beside it, `PDFInspector` checks the cross-reference offsets and the stream lengths on the raw bytes with code that shares nothing with the reader. Negative cases: a file typed out by hand with one fault at a time, a truncated render, a render whose objects were moved by one byte. |
| `pdfinfo` (pages, page size, version, title, author, encrypted) | `PDFDocumentReader`: `pageCount`, `pages[n].size`, `version`, `title`, `author`, `producer`. An encrypted file is refused by the reader, so a file that reads is not encrypted. |
| `pdftotext`, `pdftotext -raw` (text) | `PDFDocumentReader.text` and `pages[n].text`: the text in the order of the content stream, which is the logical order the writer emits, `/ActualText` standing in for what a span draws. |
| `pdftotext -tsv` (word boxes) | `PDFDocumentReader.Page.words`, through `ReaderTextLayout` in the test target: no word without a size, no word outside its page, no two words of a line overlapping, no two words of different lines colliding. |
| `mutool draw -F stext` (character quads, per-page text) | The same word boxes and `ReaderTextLayout.visibleCharacterCount`. In `IndexVariantTests` the second, independent reader of page text is now `ContentStreamGeometry`, which matches the text operators of the raw stream with a pattern. |
| `pdftoppm`, `mutool draw` where the property is geometric | The content stream and the image objects: the box the cover image is drawn into, the samples of the image and of its soft mask, the white fill of the cover page and its extent, the box of a body image at the top left corner. |
| veraPDF | The prerequisites above; the full runs are not verified. |

Differences that follow from reading the file instead of asking another program:

- One reader stands where two or three independent programs stood. A mistake
  shared by the writer and the reader, which have one author, is no longer caught
  by a program that implements the PDF specification on its own. The reader is
  first held to files typed out by hand to narrow that gap; it does not close it.
- The reader reads what this engine writes and refuses the rest. It does not
  establish that a file is valid for viewers in general.
- A word box is one em tall (three quarters of the font size above the baseline,
  one quarter below), the line box of the renderer, not the ascent and descent of
  the font. Vertical gaps between words are therefore measured between em boxes.
- The reader keeps the characters the file holds: a no-break space stays a
  no-break space, and two spaces stay two spaces. Two expectations were adjusted
  for that, each with a comment in the test.
- Text outside the page is reported, not dropped.

Removed, with the helper they tested, because nothing produces their input any
more: the test "Raster comparison rejects divergent ink bounds" and the raster
assertion of "Screenshot source-code regression witness rejects mutated failures"
(both exercised the comparison of two raster images), and the copy half of the
artifact directory test. The tests of the outside tools' output parsers ("Visual
layout validator normalizes offset Poppler page rows", the three "MuPDF character
quad validator" tests) were replaced by tests of the same failures on the
package's own layout check, three of them through files typed out by hand.

## Outside programs still in the tests

`ArabicShaperTests`, `ArabicMarkPositioningTests` and `HebrewShaperTests` compare
shaping with `hb-shape` (HarfBuzz) when it is on the `PATH`, and are skipped when
it is not. It shapes text and does not touch a PDF or an image, so it was outside
this change. It is listed here so that it is not overlooked.
