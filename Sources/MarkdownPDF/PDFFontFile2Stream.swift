import Foundation

struct PDFFontFile2Stream {
    var fontProgram: Data
    var streamCompression: PDFOptions.StreamCompression

    init(fontProgram: Data, streamCompression: PDFOptions.StreamCompression = .disabled) {
        precondition(!fontProgram.isEmpty, "FontFile2 streams require a font program")
        self.fontProgram = fontProgram
        self.streamCompression = streamCompression
    }

    var pdfStream: PDFSyntax.Stream {
        PDFStreamEncoder.stream(
            dictionary: PDFSyntax.Dictionary([
                .init("Length1", .int(fontProgram.count)),
            ]),
            data: fontProgram,
            compression: streamCompression,
        )
    }
}
