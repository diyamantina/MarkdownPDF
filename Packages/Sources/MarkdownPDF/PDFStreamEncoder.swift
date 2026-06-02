import Foundation

enum PDFStreamEncoder {
    static func stream(
        dictionary: PDFSyntax.Dictionary,
        data: Data,
        compression: PDFOptions.StreamCompression,
    ) -> PDFSyntax.Stream {
        guard compression.isEnabled, !dictionary.hasFilter else {
            return PDFSyntax.Stream(dictionary: dictionary, data: data)
        }

        let compressed = PDFDeflate.zlibCompressed(data)
        guard compressed.count < data.count else {
            return PDFSyntax.Stream(dictionary: dictionary, data: data)
        }

        var entries = dictionary.entries
        entries.append(.init("Filter", .pdfName("FlateDecode")))
        return PDFSyntax.Stream(dictionary: PDFSyntax.Dictionary(entries), data: compressed)
    }
}

private extension PDFSyntax.Dictionary {
    var hasFilter: Bool {
        entries.contains { entry in
            entry.key.rawValue == "Filter"
        }
    }
}
