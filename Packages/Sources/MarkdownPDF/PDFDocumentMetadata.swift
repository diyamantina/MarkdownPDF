import Foundation

struct PDFDocumentMetadata {
    var title: String?
    var conformance: PDFOptions.Conformance = .none

    var isEmpty: Bool {
        cleanTitle == nil && !conformance.isEnabled
    }

    var infoDictionary: PDFSyntax.Dictionary {
        PDFSyntax.Dictionary(infoEntries)
    }

    var xmpDictionary: PDFSyntax.Dictionary {
        PDFSyntax.Dictionary([
            .init("Type", .pdfName("Metadata")),
            .init("Subtype", .pdfName("XML")),
        ])
    }

    var xmpData: Data {
        Data(xmpText.utf8)
    }

    private var infoEntries: [PDFSyntax.Dictionary.Entry] {
        var entries = [
            PDFSyntax.Dictionary.Entry("Producer", .pdfString(Self.producer)),
        ]
        if let cleanTitle {
            entries.insert(.init("Title", .pdfString(cleanTitle)), at: 0)
        }
        return entries
    }

    private var xmpText: String {
        let titleXML = cleanTitle.map { title in
            """
            <dc:title><rdf:Alt><rdf:li xml:lang="x-default">\(title.xmlEscaped)</rdf:li></rdf:Alt></dc:title>
            """
        } ?? ""
        let pdfUAAttributes = conformance.isPDFUA1Enabled
            ? " xmlns:pdfuaid=\"http://www.aiim.org/pdfua/ns/id/\""
            : ""
        let pdfUAIdentifier = conformance.isPDFUA1Enabled
            ? "<pdfuaid:part>1</pdfuaid:part>"
            : ""

        return """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:pdf="http://ns.adobe.com/pdf/1.3/"\(pdfUAAttributes)>
        \(titleXML)
        <pdf:Producer>\(Self.producer.xmlEscaped)</pdf:Producer>
        \(pdfUAIdentifier)
        </rdf:Description>
        </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }

    private var cleanTitle: String? {
        title?.trimmingCharacters(in: .whitespacesAndNewlines).emptyAsNil
    }

    private static let producer = "MarkdownPDF"
}

private extension String {
    var emptyAsNil: String? {
        isEmpty ? nil : self
    }

    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
