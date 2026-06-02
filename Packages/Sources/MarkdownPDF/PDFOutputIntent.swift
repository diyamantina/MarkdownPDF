import Foundation

struct PDFOutputIntent {
    var destinationOutputProfile: PDFSyntax.Reference
    var outputConditionIdentifier: String

    var pdfDictionary: PDFSyntax.Dictionary {
        PDFSyntax.Dictionary([
            .init("Type", .pdfName("OutputIntent")),
            .init("S", .pdfName("GTS_PDFA1")),
            .init("OutputCondition", .pdfString(outputConditionIdentifier)),
            .init("OutputConditionIdentifier", .pdfString(outputConditionIdentifier)),
            .init("RegistryName", .pdfString("http://www.color.org")),
            .init("Info", .pdfString(outputConditionIdentifier)),
            .init("DestOutputProfile", .reference(destinationOutputProfile)),
        ])
    }
}
