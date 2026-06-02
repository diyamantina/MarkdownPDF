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
