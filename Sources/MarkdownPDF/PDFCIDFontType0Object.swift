/// The descendant CIDFont of a Type0 composite font whose embedded program is a CFF
/// (PostScript) outline, emitted as `FontFile3`. It mirrors ``PDFCIDFontType2Object``
/// but for CFF: the subtype is `CIDFontType0` and there is no `/CIDToGIDMap`.
///
/// A CIDFontType0 has no CIDToGIDMap because the CID-to-glyph mapping lives inside the
/// embedded CFF: for a CID-keyed CFF the viewer maps each CID to a glyph through the
/// CFF's own charset, and for a name-keyed CFF the CID is used directly as the glyph
/// index (PDF 32000-1 §9.7.4.2). The content stream therefore shows the CID the CFF
/// addresses each glyph by, which ``TrueTypeFontParser.Metadata/compositeCID(forGlyph:)``
/// resolves.
struct PDFCIDFontType0Object {
    var baseName: String
    var cidSystemInfo: PDFCIDSystemInfo
    var fontDescriptor: PDFSyntax.Reference
    var widths: PDFCIDFontWidths

    init(
        baseName: String,
        cidSystemInfo: PDFCIDSystemInfo = .identity,
        fontDescriptor: PDFSyntax.Reference,
        widths: PDFCIDFontWidths,
    ) {
        precondition(!baseName.isEmpty, "CIDFontType0 objects require a base font name")
        self.baseName = baseName
        self.cidSystemInfo = cidSystemInfo
        self.fontDescriptor = fontDescriptor
        self.widths = widths
    }

    var pdfDictionary: PDFSyntax.Dictionary {
        PDFSyntax.Dictionary([
            .init("Type", .pdfName("Font")),
            .init("Subtype", .pdfName("CIDFontType0")),
            .init("BaseFont", .pdfName(baseName)),
            .init("CIDSystemInfo", .dictionary(cidSystemInfo.pdfDictionary)),
            .init("FontDescriptor", .reference(fontDescriptor)),
            .init("W", widths.pdfValue),
        ])
    }
}
