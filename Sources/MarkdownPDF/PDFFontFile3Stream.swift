import Foundation

/// A `FontFile3` stream: the embedded font program for a CFF (PostScript) outline,
/// referenced from a `FontDescriptor`. Unlike `FontFile2` (which carries an sfnt and
/// a `/Length1`), a `FontFile3` identifies its program with a `/Subtype`:
/// `CIDFontType0C` for a bare CID-keyed `CFF ` table, or `OpenType` for a whole sfnt
/// wrapping a name-keyed CFF used under a `CIDFontType0` descendant (PDF 32000-1,
/// Table 126). `Type1C` is deliberately absent: it is only valid for a simple
/// (`/Type1`) font, which this engine never emits, and stamping a name-keyed CFF
/// `Type1C` under a composite descendant fails PDF/A and PDF/UA validation.
struct PDFFontFile3Stream {
    enum Subtype: String {
        case cidFontType0C = "CIDFontType0C"
        case openType = "OpenType"
    }

    var fontProgram: Data
    var subtype: Subtype
    var streamCompression: PDFOptions.StreamCompression

    init(
        fontProgram: Data,
        subtype: Subtype,
        streamCompression: PDFOptions.StreamCompression = .disabled,
    ) {
        precondition(!fontProgram.isEmpty, "FontFile3 streams require a font program")
        self.fontProgram = fontProgram
        self.subtype = subtype
        self.streamCompression = streamCompression
    }

    var pdfStream: PDFSyntax.Stream {
        PDFStreamEncoder.stream(
            dictionary: PDFSyntax.Dictionary([
                .init("Subtype", .pdfName(subtype.rawValue)),
            ]),
            data: fontProgram,
            compression: streamCompression,
        )
    }
}
