import Foundation

/// A `FontFile3` stream: the embedded font program for a CFF (PostScript) outline,
/// referenced from a `FontDescriptor`. Unlike `FontFile2` (which carries an sfnt and
/// a `/Length1`), a `FontFile3` carries the bare `CFF ` table and identifies it with
/// a `/Subtype`: `CIDFontType0C` for a CID-keyed CFF, `Type1C` for a name-keyed one
/// (PDF 32000-1, Table 126).
struct PDFFontFile3Stream {
    enum Subtype: String {
        case cidFontType0C = "CIDFontType0C"
        case type1C = "Type1C"
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
