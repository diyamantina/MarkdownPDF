# PDF validation tooling

Date: 2026-05-31

This note records the recommended open source validation stack for generated
MarkdownPDF files. It covers external validation tools only. The renderer remains
pure Swift and portable across Linux and macOS.

## Summary

There is no single open source tool that proves a PDF is correct in every useful
sense. The best approach is a layered gate that uses independent implementations:

1. Swift structural tests for writer invariants.
2. qpdf for syntax, xref, encryption, linearization, and stream encoding checks.
3. Poppler tools for reader metadata, text extraction, and optional raster output.
4. Ghostscript or MuPDF for rendering.
5. pdfcpu strict validation when installation is acceptable.
6. veraPDF only when MarkdownPDF claims PDF/A or PDF/UA conformance.

This is stronger than relying on screenshots alone. Screenshot or raster checks
prove that a page can render through one renderer. They do not prove that the
object graph, resources, text extraction, or xref table are correct.

## Current MarkdownPDF gate

The current committed gate is:

1. Swift structural inspection with `PDFInspector`.
2. qpdf syntax and xref validation.
3. Poppler metadata and text extraction through `pdfinfo`, `pdftotext`, and
   `pdftotext -tsv`.
4. MuPDF structured text extraction through `mutool draw -F stext`.
5. Poppler and MuPDF all-page raster comparison for the visual stress fixture.

This gate runs inside `swift test`, so both macOS and Linux CI exercise the same
Swift test logic. Linux installs `qpdf`, `poppler-utils`, and `mupdf-tools`.
macOS installs `qpdf`, `poppler`, `mupdf`, and the `font-urw-base35` cask. The
font cask matters because Homebrew Poppler on a fresh GitHub macOS runner can
extract PDF base-font text but fail to paint that text during rasterization until
URW Base35 fonts are available to fontconfig.

## Recommended CI gate

The portable CI gate should generate at least one minimal PDF, one article-grade
fixture PDF, and one multi-page visual stress PDF, then run:

```sh
qpdf --check "$pdf"
pdfinfo "$pdf"
pdftotext "$pdf" -
pdftotext -tsv "$pdf" -
pdftoppm -r 96 "$pdf" "$out/poppler/page"
mutool draw -q -F stext "$pdf"
mutool draw -q -F pnm -r 96 -o "$out/mupdf/page-%d.pnm" "$pdf"
```

For a basic smoke gate:

- `qpdf --check` must exit 0.
- `pdfinfo` must report the expected PDF version and page count.
- `pdftotext` must extract expected visible text.
- `pdftotext -tsv` must produce valid word and line boxes.
- MuPDF structured text must produce valid character quads.
- Poppler and MuPDF raster outputs must be nonblank and broadly agree on ink
  bounds across every generated page in the visual stress fixture.

Treat qpdf warnings as CI failures. qpdf documents distinct exit behavior for
`--check`: 0 for syntactic correctness, 2 for errors, and 3 for warnings. In a
PDF writer test suite, a repaired xref table or recovered stream length is not
acceptable even if a permissive viewer can open the file.

If `mupdf-tools` is available on the Linux runner, add:

```sh
mutool draw -q -r 144 -o "$out/mupdf-page-%d.png" "$pdf"
```

MuPDF is useful because it is an independent renderer. Comparing Ghostscript and
MuPDF output dimensions, page counts, and basic image statistics catches a
different class of rendering problems than qpdf.

If `pdfcpu` is available, add:

```sh
pdfcpu validate -mode strict "$pdf"
```

Use this as an additional gate only after confirming installation stability on
GitHub Actions Linux. qpdf and Poppler are easier to install from Ubuntu
packages.

## Tool roles

| Tool | Role | What it catches | What it does not prove |
|---|---|---|---|
| Swift `PDFInspector` | Writer invariant tests | Expected object graph, stream lengths, xref offsets, resource names | Interoperability with external readers |
| qpdf | Structural parser and checker | Syntax, xref, encryption, linearization status, stream encoding problems | Full PDF specification conformance or visual correctness |
| Poppler `pdfinfo` | Reader metadata inspection | Page count, page size, PDF version, metadata flags, encryption status | Complete syntax validation |
| Poppler `pdftotext` | Text extraction | Whether text is extractable by a real reader | Visual layout quality |
| Poppler `pdftoppm` | Rasterization | Whether Poppler can render pages | Full structural correctness |
| Ghostscript | Interpreter and renderer | Rendering failures, many malformed-file failures with `-dPDFSTOPONERROR` | Complete validation |
| MuPDF `mutool draw` | Independent renderer and extractor | Rendering failures, extraction failures, visual regression via checksums | Full validation |
| pdfcpu | PDF processor and validator | Strict or relaxed validation according to its parser | Visual correctness |
| veraPDF | PDF/A and PDF/UA validator | Formal profile conformance for PDF/A and machine-checkable PDF/UA | General PDF correctness if no profile is claimed |
| PDFBox Preflight | PDF/A-1 validation | PDF/A-1b validation and related syntax checks | General PDF correctness and modern PDF/A profiles |

## Local check result

On the current minimal PDF generated during this research:

```text
qpdf --check: PDF 1.4, not encrypted, not linearized, no syntax or stream encoding errors found
pdfinfo: 1 page, A4, PDF 1.4, 803 bytes
pdftotext: extracted "Hello from MarkdownPDF."
Ghostscript nullpage: exit 0 with -dPDFSTOPONERROR
Ghostscript png16m: produced 1191 x 1684 PNG at 144 dpi
ImageMagick identify: min=0, max=1, mean=0.999396
```

The `identify` result is a simple nonblank raster smoke check. A fully blank
white image would have min and max near 1. The current output has black pixels
from text and white background.

## Error behavior probe

The most useful validation tool for CI is the one that gives actionable exit
codes and messages. Local probes with deliberately damaged PDFs showed:

| Case | qpdf | Poppler `pdfinfo` | Ghostscript nullpage |
|---|---|---|---|
| valid minimal PDF | exit 0, no syntax or stream encoding errors | exit 0, page count and metadata | exit 0 |
| wrong `startxref` offset | exit 3, xref not found, reconstructing xref table | exit 0, still reports one page | exit 1, `/syntaxerror in --runpdf--` |
| wrong stream `/Length` | exit 3, expected `endstream`, recovered stream length | exit 0, still reports one page | exit 1, `/syntaxerror in --runpdf--` |
| truncated file | exit 2, cannot find pages while recovering | exit 1, trailer and xref read errors | exit 1 |

This makes qpdf the best first hard gate because its warnings identify exactly
the class of writer defect. Poppler is still useful, but mostly as an
interoperability check. Ghostscript with `-dPDFSTOPONERROR` is useful as a
renderer/interpreter gate, but its errors are less specific for writer debugging.

## Linux CI package plan

For GitHub Actions on Ubuntu:

```sh
sudo apt-get update
sudo apt-get install -y git mupdf-tools poppler-utils qpdf
```

Optional additions:

```sh
sudo apt-get install -y ghostscript imagemagick
```

`imagemagick` is only needed if CI checks PNG statistics. If the gate only checks
that a raster file exists, `file` is enough, but that is weaker.

`pdfcpu` may require downloading a release binary or installing through Go. It is
valuable, but it should not block the first validation gate unless installation is
stable and fast.

## macOS CI package plan

For GitHub Actions on macOS:

```sh
brew install mupdf poppler qpdf swiftformat swiftlint
brew install --cask font-urw-base35
fc-cache -f "$HOME/Library/Fonts" || true
```

The Base35 cask is validation infrastructure, not a runtime dependency of the
renderer and not a font file committed to the public repository.

## Best order for MarkdownPDF

1. Keep Swift structural tests as the first line of defense because they can
   assert exact writer invariants more clearly than external tools.
2. Make qpdf exit 0 mandatory. Treat exit 2 and exit 3 as failures.
3. Keep Poppler metadata, text extraction, TSV geometry, and raster witnesses in
   normal CI.
4. Keep MuPDF structured text and raster witnesses in normal CI.
5. Add pdfcpu strict validation after evaluating install speed and reliability.
6. Add veraPDF only when MarkdownPDF intentionally emits PDF/A or PDF/UA.

## Sources

- qpdf manual, `--check`: https://qpdf.readthedocs.io/en/stable/cli.html
- Poppler Debian manpages, `pdftoppm` and related tools:
  https://manpages.debian.org/bookworm/poppler-utils/pdftoppm.1.en.html
- Ghostscript FAQ and rendering documentation: https://ghostscript.com/faq
- MuPDF `mutool draw` documentation:
  https://mupdf.readthedocs.io/en/1.23.0/mutool-draw.html
- pdfcpu CLI usage and validation command:
  https://github.com/pdfcpu/pdfcpu/blob/master/cmd/pdfcpu/usage.go
- veraPDF project and CLI validation docs:
  https://verapdf.org/
  https://docs.verapdf.org/cli/validation/
- Apache PDFBox and Preflight:
  https://pdfbox.apache.org/
  https://svn.apache.org/repos/asf/pdfbox/site/publish/userguide/preflight.html?p=1507079
