# Apple system fonts and custom font support

Date: 2026-06-02

Scope: this note covers two related questions for MarkdownPDF. First, what the
`FontSet.appleSystem` names can and cannot honestly promise, given Apple's font
license and the fact that San Francisco is not present on Linux. Second, which
custom font formats the engine should accept now, which are staged future work,
and what each one implies for the PDF font-emission path. It is a research and
planning note, not a description of current product behavior beyond what is
explicitly marked as baseline.

## Rule context

- The shared renderer stays pure Swift and Linux-buildable.
- PDF bytes are emitted directly by this package.
- No PDFKit, CoreText, CoreGraphics, WebKit, FreeType, HarfBuzz, or C font or C
  PDF libraries are allowed in the production path.
- The public repository commits no font binaries.
- macOS and Linux produce the same bytes for the same input font data.
- Vendored code under `researchcode/` is study-only. It is read for reference,
  not linked or ported wholesale.

## Current baseline

The default profile uses standard PDF base fonts and emits no `/FontFile*`,
`/ToUnicode`, Type 0, CID, or CMap objects. The opt-in embedded-font profile
accepts caller-supplied TrueType (`glyf`) data and emits a Type 0 parent with a
CIDFontType2 descendant, FontFile2, ToUnicode, and CIDToGIDMap, per
`portable-embedded-fonts-tounicode-plan.md`.

`FontSet.appleSystem` in `Packages/Sources/MarkdownPDF/PDFOptions.swift`
(`regular: "SFProText-Regular"`, `bold: "SFProText-Bold"`,
`italic: "SFProText-RegularItalic"`, `monospaced: "SFMono-Regular"`) emits those
strings as unembedded TrueType `/BaseFont` names. No font program is embedded. A
PDF reader must already have those fonts installed to render them.

## 1. Apple system fonts: licensing and the honest portable story

San Francisco (SF Pro, SF Compact, SF Mono) and New York are downloadable only
from Apple's developer fonts page and are governed by per-font Apple license
agreements, not an open license.

The license restricts use to Apple platforms and prohibits embedding:

- "The Apple Font is to be used solely for creating mock-ups of user interfaces
  to be used in software products running on Apple's iOS, OS X or tvOS operating
  systems."
- "You may not embed the Apple Font in any software programs or other products."
- "The grants set forth in this License do not permit you to ... install, use or
  run the Apple Font for the purpose of creating mock-ups of user interfaces to
  be used in software products running on any non-Apple operating system."

(Quotes from the SF Pro / SF Mono license, surfaced from Apple's fonts page,
https://developer.apple.com/fonts/ . The related Apple Design Resources license
PDF is at
https://developer.apple.com/support/downloads/terms/apple-design-resources/Apple-Design-Resources-License-20230621-English.pdf .)

Consequences for the engine:

- The fonts cannot be embedded in output PDFs and cannot be committed to the
  public repo. This is a license constraint on top of any technical fsType bit.
- San Francisco is not installed on Linux. A reader on Linux will substitute
  some other font for the `SFProText-Regular` name, so layout and metrics are
  not guaranteed.
- Even on macOS, a `/BaseFont` name with no embedded program relies on reader
  substitution. PDF readers map unknown names to a near substitute, which is
  best-effort, not faithful.

Honest promise: `FontSet.appleSystem` is a naming convenience for macOS readers
that happen to have the system font. It must be documented as best-effort,
non-portable, and never described as font embedding. The portable, reproducible
story is the embedded-font path with a caller-supplied, embeddable, open font.

## 2. Custom font formats: accept, stage, or reject

Font outline format drives the PDF descendant-font type, so the engine must
detect the real format from the table directory, not the file extension. The
`.otf` extension can hold either TrueType or CFF outlines, so the extension is
not authoritative (Microsoft OpenType file structure,
https://learn.microsoft.com/en-us/typography/opentype/spec/otff ).

- TrueType outlines (`glyf` plus `loca`, with `cvt`, `fpgm`, `prep`): quadratic
  Bezier curves. This is the current accepted format. It maps to PDF
  CIDFontType2 + FontFile2. Accept now.
- OpenType / CFF (`CFF ` table, PostScript Type 2 charstrings, cubic Beziers):
  not a `glyf` font. It needs a different PDF path: a CIDFontType0 descendant
  with the program in FontFile3 (subtype CIDFontType0C / Type1C). Staged future.
  See the glyf vs CFF vs CFF2 comparison,
  https://learn.microsoft.com/en-us/typography/opentype/spec/glyphformatcomparison .
- CFF2 (`CFF2` table): the variable-capable successor to CFF, with `blend` and
  `vsindex` operators; not backward compatible
  (https://learn.microsoft.com/en-us/typography/opentype/spec/cff2 ). Reject for
  now; if ever supported, instance to a static CFF first.
- TrueType Collections (TTC): one file, multiple fonts sharing tables. Accept
  only by selecting one face and treating it as a standalone TrueType font;
  reject blind whole-collection embedding (mirrors pdfbox, which refuses full
  embedding of TTC, see below). Staged.
- WOFF / WOFF2: compressed web-font wrappers. WOFF2 requires Brotli
  decompression and table-specific transforms before you ever see `glyf`/`CFF`
  (W3C WOFF2, https://www.w3.org/TR/WOFF2/ ). PDF must never embed the WOFF
  wrapper. Reject until a pure Swift decompressor exists, then decompress to
  SFNT and route by outline type. Staged.
- Variable fonts (`fvar` plus named instances): a single program with
  interpolation axes. PDF has no native variable embedding for general readers.
  The correct approach is to instance to a static font at the chosen named
  instance, then embed that. Until a pure Swift instancer exists, reject.
  Staged.

## 3. OS/2 fsType embedding-permission bits

The OS/2 `fsType` field encodes the vendor's embedding license. A correct engine
must read it and gate embedding before emitting any FontFile stream. From the
OpenType OS/2 spec
(https://learn.microsoft.com/en-us/typography/opentype/spec/os2 ):

- Bits 0 to 3 (mask 0x000F) are the usage-permissions sub-field; at most one of
  bits 1, 2, 3 is set; bit 0 is permanently reserved and must be zero. Valid
  values are 0, 2, 4, 8.
- 0: Installable embedding. May be embedded and permanently installed.
- 2 (0x0002): Restricted License embedding. Must not be embedded without
  explicit owner permission. Gate: reject.
- 4 (0x0004): Preview and Print embedding. May be embedded for read-only view or
  print. Documents must open read-only.
- 8 (0x0008): Editable embedding. May be embedded; editing permitted.
- Bit 8 (0x0100): No subsetting. The font must not be subsetted before
  embedding. A subset-only engine must either full-embed or reject.
- Bit 9 (0x0200): Bitmap embedding only. No outline data may be embedded; for an
  outline engine this is effectively unembeddable. Gate: reject.

The spec also notes that if more than one permission bit is set, some
applications assume the least-restrictive permission, and that for Restricted
License embedding to take effect the sub-field value must be exactly 2. fsType is
metadata, not technical enforcement, so the engine treats it as a license
contract it must honor.

## 4. PDF side: CIDFontType2 vs CIDFontType0

A Type 0 (composite) font has exactly one descendant CIDFont, which must be
either CIDFontType0 (CFF / Adobe Type 1 outlines) or CIDFontType2 (TrueType
`glyf` outlines). This is ISO 32000 sections 9.6 and 9.7. References: Adobe
CMap and CIDFont specification (Tech Note 5014,
https://adobe-type-tools.github.io/font-tech-notes/pdfs/5014.CIDFont_Spec.pdf )
and the PdfPig font notes summarizing the descendant rules
(https://github.com/UglyToad/PdfPig/blob/master/font-notes.md ).

- TrueType `glyf` -> descendant `/Subtype /CIDFontType2`, program in
  `/FontFile2`, with `/CIDToGIDMap` Identity or a stream.
- CFF -> descendant `/Subtype /CIDFontType0`, program in `/FontFile3` with
  stream `/Subtype /CIDFontType0C` (or `/Type1C` for non-CID CFF). Bare CFF for
  PDF and OpenType wrapping have PDF version implications (PDF 1.3 vs 1.6).

The engine must select the descendant type from the detected outline format. You
cannot put a `glyf` font in CIDFontType0 or a CFF font in CIDFontType2.

## 5. Vendored source references (study-only)

These confirm the CFF vs TrueType split and the fsType gate in mature engines.

- Skia, `researchcode/skia/src/pdf/SkPDFFont.cpp`:
  - `SkPDFFont::FontType` (around line 331) forces a Type3 fallback for variable
    fonts, alt-data-format fonts (its comment names WOFF/WOFF2 explicitly),
    non-embeddable fonts, and `kCFF_Font`. Direct precedent for our staging.
  - The emit branch (around lines 467 to 510) writes `/FontFile2` and descendant
    `/Subtype /CIDFontType2` for `kTrueType_Font`, and `/FontFile3` with stream
    `/Subtype CIDFontType0C` plus descendant `/Subtype /CIDFontType0` for
    `kType1CID_Font`. `can_embed` and `can_subset` (around lines 249 to 254) gate
    on `kNotEmbeddable_FontFlag` and `kNotSubsettable_FontFlag`.
- Skia, `researchcode/skia/src/pdf/SkPDFType1Font.cpp`: parses PFB sections and
  documents the Type 1 program structure; reference for the CFF/Type1 path we do
  not yet implement.
- pdfbox, `researchcode/pdfbox/.../pdmodel/font/TrueTypeEmbedder.java`:
  `isEmbeddingPermitted` reads `os2.getFsType()`, masks `& 0x000F`, returns false
  on `FSTYPE_RESTRICTED` and on `FSTYPE_BITMAP_ONLY`. `isSubsettingPermitted`
  returns false on `FSTYPE_NO_SUBSETTING`. Full TTC embedding throws "not
  supported." The exact gate our parser should reproduce in Swift.
- pdfbox, `researchcode/pdfbox/.../pdmodel/font/PDCIDFontType0.java`: the CFF
  descendant path, reading `getFontFile3()` and parsing with `CFFParser`,
  `CFFCIDFont`, `CFFType1Font`. Counterpart `PDCIDFontType2.java` is the
  TrueType descendant.
- libharu, `researchcode/libharu/src/hpdf_font_cid.c`: `CIDFontType0_New`
  (Subtype `CIDFontType0`) and `CIDFontType2_New` (Subtype `CIDFontType2`,
  adds `FontFile2`) show the same two-path emission in C.
- harfbuzz subset usage is visible in
  `researchcode/skia/src/pdf/SkPDFSubsetFont.cpp` (`hb_subset_*`,
  `HB_SUBSET_FLAGS_RETAIN_GIDS`, `NOTDEF_OUTLINE`). We do not link HarfBuzz; this
  is reference for the subset contract our pure Swift subsetter must satisfy.

## Staged plan for the Swift engine

(a) Honest Apple-font story. Keep `FontSet.appleSystem` as names-only. Document
in the public API that it relies on reader substitution, is best-effort on macOS
only, is not portable to Linux, and is not font embedding. Never commit Apple
font binaries; never auto-embed system fonts.

(b) Custom-font acceptance matrix.

| Format | Outline | PDF path | Status |
| --- | --- | --- | --- |
| TrueType `glyf` | quadratic | CIDFontType2 + FontFile2 | Accept now |
| OpenType CFF | cubic (Type2) | CIDFontType0 + FontFile3 (CIDFontType0C) | Staged |
| CFF2 | cubic, variable | instance to CFF first | Reject for now |
| TTC | per face | select one face, treat as TrueType/CFF | Staged |
| WOFF / WOFF2 | wrapped | decompress to SFNT, then route | Staged, needs Swift decompressor |
| Variable (`fvar`) | interpolated | instance to named instance, then embed | Reject for now |

Detect format from the table directory; reject on unknown or unsupported with an
actionable typed error.

(c) fsType gating. The Swift TrueType/OpenType parser reads `OS/2` `fsType`,
masks `& 0x000F`, rejects value 2 (Restricted) and bit 9 (Bitmap only),
rejects bit 8 (No subsetting) in subset-only mode unless the engine full-embeds,
and records Preview-Print vs Editable for documentation. Apple system fonts fail
the license gate regardless of fsType.

(d) Witness requirements. Every stage needs structural assertions before visual
ones: the correct descendant subtype (CIDFontType2 vs CIDFontType0), the
matching FontFile2 vs FontFile3 stream, FontFile length and Length1 agreement,
and a referenced ToUnicode. External witnesses: `qpdf --check` accepts the PDF;
`pdftotext` extracts accented Latin exactly; `pdftotext -tsv` keeps word boxes
in bounds; `mutool draw -F stext` (MuPDF) reports positive, monotonic character
quads. Cross-platform fixtures use CI-installed open fonts via
`MARKDOWNPDF_OPEN_FONT_PATH`, with no committed font binaries.

## Decision summary

Apple system fonts are names-only and non-portable by license and by absence on
Linux. The faithful path is embedding a caller-supplied, embeddable, open font.
TrueType `glyf` is supported today as CIDFontType2 + FontFile2. CFF/OTF is the
next staged path and requires CIDFontType0 + FontFile3, a genuinely different
emission, not a tweak of the TrueType path. WOFF2, TTC, CFF2, and variable fonts
are staged behind pure Swift decompression and instancing. Every format passes
an fsType gate first, and every stage is proven by qpdf, pdftotext, and MuPDF
witnesses on both macOS and Linux.
