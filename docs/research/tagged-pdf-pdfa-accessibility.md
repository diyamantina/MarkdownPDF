# Tagged PDF (PDF/UA) and PDF/A archival output

Date: 2026-06-02

Issue: #128

## Scope

This note researches how MarkdownPDF can emit two distinct conformance
profiles directly from its Swift writer: tagged, accessible PDF (the logical
structure tree, machine-checkable against PDF/UA-1) and PDF/A archival output
(self-contained, validator-checkable for long-term preservation). It covers the
governing standards, the concrete object mechanics MarkdownPDF must emit, the
validator, and an ordered work plan. It is portable research for macOS and
Linux, not implementation code, and not an iOS claim.

## Product boundary

The renderer stays pure Swift and Linux-buildable. It generates PDF bytes
directly. No PDFKit, CoreGraphics, CoreText, AppKit, UIKit, WebKit, browser
renderers, LaTeX, JavaScript, Python, shell renderers, or C PDF/Markdown
libraries in production. Apache PDFBox, pikepdf/qpdf, and Ghostscript are STUDY
references and test tooling only, never production dependencies. veraPDF is a CI
WITNESS tool, in the same category as the qpdf, Poppler, and MuPDF witnesses
already in the gate, never linked into the renderer.

Tagged output and PDF/A are independent toggles. The strongest single target is
PDF/UA-1 plus PDF/A-2a (the combination the Matterhorn Protocol document itself
ships as), because PDF/A-2a requires the same tag tree PDF/UA-1 needs.

## Standards and sources

PDF/UA-1 is layered on PDF 1.7 (ISO 32000-1); PDF 2.0 (ISO 32000-2) is the home
of WTPDF and PDF/UA-2.

- ISO 32000-1:2008 (PDF 1.7), Adobe's free, body-identical copy:
  https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf
  PDF Association landing: https://pdfa.org/resource/iso-32000-1/
- ISO 32000-2 (PDF 2.0) overview: https://pdfa.org/resource/iso-32000-2/
- ISO 14289-1:2014 (PDF/UA-1): https://pdfa.org/resource/iso-14289-pdfua/
  "PDF/UA-1 in a nutshell": https://pdfa.org/resource/pdfua-in-a-nutshell/
- ISO 19005 (PDF/A) family overview: https://pdfa.org/resource/iso-19005-pdfa/
  PDF/A-1 specifically: https://pdfa.org/resource/iso-19005-1-pdf-a-1/
- Matterhorn Protocol 1.1, the definitive list of 31 checkpoints / 136 failure
  conditions for PDF/UA-1: https://pdfa.org/download-area/publications/Matterhorn-Protocol-1-1.pdf
  Landing page: https://www.pdfa.org/resource/the-matterhorn-protocol-1-02/
- Tagged PDF Best Practice Guide: Syntax (developer-facing tag mechanics):
  https://pdfa.org/resource/tagged-pdf-best-practice-guide-syntax/
  Direct PDF: https://pdfa.org/wp-content/uploads/2019/06/TaggedPDFBestPracticeGuideSyntax.pdf
- Well-Tagged PDF (WTPDF) 1.0, the PDF 2.0 reuse+accessibility profile:
  https://pdfa.org/wtpdf  Direct PDF:
  https://pdfa.org/wp-content/uploads/2024/02/Well-Tagged-PDF-WTPDF-1.0.pdf
- W3C WCAG technique PDF9 (headings via tags, worked example):
  https://www.w3.org/WAI/WCAG22/Techniques/pdf/PDF9
- Adobe pdfmark logical-structure reference (BDC/EMC/BMC and MCID semantics):
  https://opensource.adobe.com/dc-acrobat-sdk-docs/library/pdfmark/pdfmark_Logical.html

## Tagged PDF structure model: what the writer must emit

The structure suite is a parallel logical tree that points back into page
content via marked-content identifiers. Five things must line up.

1. Catalog flags. Set `/MarkInfo << /Marked true >>` and a document
   `/Lang (en-US)` (BCP-47). Add `/StructTreeRoot N 0 R` and `/ViewerPreferences
   << /DisplayDocTitle true >>` (PDF/UA requires the title to display, and the
   document title in XMP must be set).

2. StructTreeRoot. A `/Type /StructTreeRoot` dictionary holding `/K` (the root
   structure element, normally a single `/Document`), `/ParentTree` (a number
   tree), `/ParentTreeNextKey`, and an optional `/RoleMap` mapping any custom
   element names to standard types.

3. Structure elements (`/Type /StructElem`). Each carries `/S` (the type), `/P`
   (parent), `/K` (kids: child elements and/or integer MCIDs), and `/Pg` (the
   page it lives on). MarkdownPDF's element vocabulary maps cleanly:

   | Markdown construct | Structure type | Notes |
   |---|---|---|
   | Document root | `Document` | one per file, `/K` is the body |
   | `# .. ######` | `H1`..`H6` | no skipped levels; nest logically |
   | Paragraph | `P` | |
   | List | `L` with `/ListNumbering` | `Ordered`/`Unordered`/`Decimal` |
   | List item | `LI` -> `Lbl` (bullet/number) + `LBody` | bullet glyph lives in `Lbl` |
   | Table | `Table` -> `TR` -> `TH`/`TD` | header cells are `TH` |
   | Table header cell | `TH` with `/Scope (Row|Column)` | use `/Headers`+`/ID` for complex tables |
   | Image | `Figure` with `/Alt (...)` and `/BBox` | alt text mandatory under PDF/UA |
   | Link | `Link` + an `OBJR` to the link annotation | |
   | Code block | `Code` (or `P`/`Span` via RoleMap) | preserve as readable text |

4. Marked content. In each content stream, wrap drawing operators that belong to
   one structure element in `/Tag <</MCID n>> BDC ... EMC`. Artifacts (page
   numbers, decorative rules, repeated headers) must be wrapped in `/Artifact BMC
   ... EMC` so they are excluded from the reading order. The integer `n` is the
   MCID referenced from the structure element's `/K`.

5. ParentTree + StructParents. Every page that contains marked content gets a
   `/StructParents k` integer; the StructTreeRoot's `/ParentTree` number tree
   maps key `k` to the array of structure elements for that page's MCIDs (in MCID
   order). This is the back-pointer that lets a reader resolve any MCID to its
   element. Without a valid ParentTree only the simplest documents are possible.

Reading order is the depth-first order of the structure tree, NOT the order of
ink on the page. MarkdownPDF already knows the logical document order from the
Markdown AST, so the writer should build the structure tree from the AST and
assign MCIDs as it lays out each block, keeping a per-page MCID counter.

## PDF/A model: what archival output additionally requires

PDF/A constrains PDF to be self-contained and deterministic over time. The
required additions on top of a normal MarkdownPDF file:

- OutputIntent. The catalog needs `/OutputIntents [ << /Type /OutputIntent
  /S /GTS_PDFA1 /OutputConditionIdentifier (sRGB IEC61966-2.1)
  /DestOutputProfile M 0 R >> ]`, where `M` is an embedded ICC profile stream
  with `/N 3`. If more than one OutputIntent has a `DestOutputProfile`, they must
  all reference the same ICC object. An sRGB profile shipped as a CI fixture is
  the simplest choice (do not commit it to the renderer; embed bytes at build).
- Fonts. Every font actually used must be fully embedded with a complete glyph
  set for the characters drawn, plus a `/ToUnicode` CMap. No unembedded fonts,
  no font references. This aligns with MarkdownPDF's existing embedded-font and
  ToUnicode work.
- XMP metadata. A `/Metadata` stream (XMP packet) is mandatory and must declare
  `pdfaid:part` and `pdfaid:conformance` (e.g. part 2, conformance A). XMP and
  the legacy `/Info` dictionary must stay in sync (Title, etc.) or validation
  fails. PDF/A-2a/3a additionally require the tag tree from the section above.
- Prohibited features. No encryption, no JavaScript, no embedded multimedia or
  executable content, no external references (LZW is also disallowed; use
  Flate). PDF/A-1 forbids transparency and embedded files; PDF/A-2 allows
  transparency and JPEG2000; PDF/A-3 allows arbitrary embedded files. PDF/A-2 is
  the best default target for a Markdown renderer.

Conformance level suffix: `b` = visual reproduction only; `a` = `b` plus tagged
structure and Unicode mapping; `u` (PDF/A-2/3) = `b` plus Unicode mapping. To
get an accessible archival file, target `2a`, which subsumes the tag work above.

## veraPDF as the witness

veraPDF is the open-source reference validator for PDF/A and PDF/UA, maintained
by the PDF Association and the Open Preservation Foundation, and is the validator
referenced by the ISO working groups. It belongs in CI exactly like qpdf,
Poppler, and MuPDF, and only runs once MarkdownPDF intentionally claims a
profile.

- Project: https://verapdf.org/
- CLI validation docs: https://docs.verapdf.org/cli/validation/
- Install: https://docs.verapdf.org/install/
- Apps (GUI/CLI/installer) repo: https://github.com/veraPDF/veraPDF-apps

CLI shape: `verapdf [options] <file_or_directory>`.

```sh
# PDF/A-2a (tagged archival)
verapdf -f 2a --format text out.pdf
# PDF/UA-1 (accessibility)
verapdf -f ua1 --format text out.pdf
# WTPDF reusable / accessible (PDF 2.0)
verapdf -f wt1r out.pdf
verapdf -f wt1a out.pdf
```

`-f/--flavour` values: `0` (auto), `1a 1b 2a 2b 2u 3a 3b 3u 4 4e 4f ua1 ua2
wt1r wt1a`. `--format` values: `text raw xml html json`. Useful flags:
`--recurse`/`-r`, `--processes N`, `--maxfailures N`, `-p` custom profile. The
docs do not publish exit codes, so CI must parse the report (`--format json`)
for `isCompliant` rather than trusting only the process exit code. Treat any
non-compliant assertion as a hard failure, the same way the gate treats qpdf
warnings as failures.

## Reference implementations to study

Study for object layout only; none ship in production.

- Apache PDFBox (Java), Apache-2.0. Its struct-tree and Preflight (PDF/A-1b)
  code is the clearest readable model of `StructElem`/ParentTree assembly:
  https://pdfbox.apache.org/
- qpdf (C++), Apache-2.0, and pikepdf (Python binding), MPL-2.0. Best for
  low-level object/number-tree inspection while debugging the writer:
  https://github.com/pikepdf/pikepdf  qpdf license:
  https://qpdf.readthedocs.io/en/stable/license.html
- Ghostscript, AGPL or commercial dual license. Useful as an independent
  renderer/PDF/A converter to study output, but AGPL means it must never be a
  dependency: https://www.ghostscript.com/licensing/index.html
- LaTeX `tagpdf` package (LPPL) for worked tag-tree examples and a real-world
  ParentTree bug discussion: https://github.com/u-fischer/tagpdf

## Witness policy

Tagged/PDF-A output is a new behavior class and must not silently degrade.

- Keep the existing gate (Swift `PDFInspector`, qpdf `--check`, Poppler text/TSV,
  MuPDF stext, raster comparison) for every generated file.
- Add veraPDF only on fixtures that claim a profile: `verapdf -f 2a` and
  `verapdf -f ua1` must report compliant.
- Add Swift structural assertions specific to tagging: `/MarkInfo/Marked true`
  present; `/StructTreeRoot` resolves; every MCID in a content stream resolves
  through `/ParentTree` to exactly one `StructElem`; every `Figure` has non-empty
  `/Alt`; heading levels never skip; every page with content has `/StructParents`.
- Extraction is a separate fact from tagging: Poppler `pdftotext` order should
  follow logical reading order once tagged. Add a fixture asserting that.
- A document that cannot be correctly tagged (e.g. an image with no alt text
  supplied) must throw a typed error or emit a documented visible fallback, never
  a quietly non-conforming "tagged" file.

## Ordered work

1. Land this policy and pick default targets: PDF/UA-1 and PDF/A-2a, opt-in.
2. Build the structure tree from the Markdown AST (logical order) decoupled from
   layout; assign per-page MCID counters during layout.
3. Emit BDC/EMC around tagged runs and Artifact BMC around running heads, rules,
   and page numbers.
4. Write StructTreeRoot, StructElem tree, RoleMap, ParentTree, StructParents,
   `/MarkInfo`, `/Lang`, `/ViewerPreferences/DisplayDocTitle`.
5. Map tables (TR/TH/TD with `/Scope`), lists (L/LI/Lbl/LBody), figures
   (`/Alt`), and links (Link + OBJR).
6. Add PDF/A layer: embed sRGB ICC OutputIntent, XMP packet with `pdfaid:*`,
   Info/XMP sync, enforce full font embedding + ToUnicode, reject prohibited
   features.
7. Wire veraPDF (`-f ua1`, `-f 2a`, JSON parsed) into CI on profile fixtures;
   keep qpdf/Poppler/MuPDF witnesses for all files.
8. Add Matterhorn-derived Swift assertions for the software-checkable failure
   conditions; document the human-judgment conditions as out of automated scope.

## Current implementation status

The portable renderer now has two separate opt-in paths:

- `PDFOptions.taggedPDF` emits the logical structure spine without claiming
  standards conformance.
- `PDFOptions.conformance == .pdfUA1` auto-enables tagged structure, requires a
  non-empty document title, rejects PDF base-font fallback, emits `pdfuaid`
  XMP identification, and is checked with `verapdf -f ua1 --format json`.

PDF/A remains unclaimed. The remaining archival work is the PDF/A layer:
validated sRGB ICC output intent, `pdfaid` XMP, document ID handling if needed
by the chosen profile, and validator fixtures for `verapdf -f 2a`.

## Platform notes

veraPDF ships as a cross-platform Java application and runs identically on
GitHub Actions Linux and macOS; install it as CI infrastructure (Greenfield
build, dual open-source license) alongside qpdf/poppler/mupdf, never as a
renderer dependency. The renderer itself emits all structure, XMP, and ICC bytes
in pure Swift, so tagged and PDF/A output build and run the same on Linux and
macOS. macOS-specific viewers (Preview) are not evidence; only the portable
veraPDF + qpdf/Poppler/MuPDF witnesses count as portable proof. iOS remains
unclaimed.


## Source-code references (vendored in `researchcode/`)

Richest model is Apache FOP (Java, Apache-2.0) - emits PDF objects directly, so it maps almost 1:1 to a pure-Swift writer. skia (C++, BSD-3) is the second, closest-architecture reference.

FOP:
- `researchcode/xmlgraphics-fop/fop-core/src/main/java/org/apache/fop/pdf/PDFStructElem.java` - the `/StructElem` builder (S/P/K/Pg/Lang/A, lazy object-number assignment, integer-vs-array `/K`, PDF/UA fixups in `output()`). Primary model for a Swift `StructElem`.
- `.../pdf/PDFParentTree.java` - `addToNums()` (50-entry number-tree buckets): canonical `/ParentTree` + `/StructParents` builder.
- `.../pdf/PDFProfile.java` - `verifyTaggedPDF()` requires `/MarkInfo /Marked true`, `/StructTreeRoot`, `/Lang` for PDF/A-level-A and PDF/UA. Single pre-write validation gate.
- `.../pdf/PDFMetadata.java` - `createXMPFromPDFDocument()` emits `pdfaid`/`pdfuaid` XMP + PDF/A extension schema. XMP template reference.
- `.../pdf/{PDFAMode,PDFUAMode,PDFRoot}.java` - conformance enums + catalog `/MarkInfo`/`/Lang`/`StructTreeRoot` wiring.

OpenPDF (Java, LGPL/MPL):
- `researchcode/openpdf/openpdf-core/src/main/java/org/openpdf/text/pdf/PdfStructureTreeRoot.java` - `mapRole()` (`/RoleMap`) + `getOrCreatePageKey()`/`buildTree()` page-keyed ParentTree. Use if supporting custom tag names.

WeasyPrint (Python, BSD-3):
- `researchcode/weasyprint/weasyprint/pdf/tags.py` - `add_tags()` + `_get_pdf_tag()`: clean end-to-end tagger + HTML->PDF-role table to adapt for Markdown->role; `pdfa.py`/`pdfua.py`/`metadata.py` for variant flags + XMP namespaces.

skia (C++, BSD-3):
- `researchcode/skia/src/pdf/SkPDFTag.cpp` - `SkPDFStructElem` (~L53), `SkPDFStructTree::createMarkForElemId` (~L336, MCID allocator), `emitStructElem` (~L434, three-way `/K` merge), `emitStructTreeRoot` (~L652, ParentTree Nums + IDTree).
- `researchcode/skia/src/pdf/SkPDFDevice.cpp` - `MarkedContentManager::beginMark` (~L120): BDC/EMC + `/Artifact` emission; `/Span<</ActualText>>BDC` fallback (~L1059).
- `researchcode/skia/src/pdf/SkPDFMetadata.cpp` - `MakeXMPObject` (~L235, `pdfaid:part/conformance`, uncompressed `/Metadata`), `CreateUUID` (~L86), `MakePdfId` (~L117, trailer `/ID`); `SkPDFDocument.cpp:535` `make_srgb_output_intents` (`/OutputIntents` + ICCBased sRGB).

Spec anchors: ISO 32000-1/-2 (14.7-14.8), ISO 14289 (PDF/UA), ISO 19005 (PDF/A), Matterhorn Protocol, veraPDF (CI validator: `verapdf -f ua1|2a --format json`).
