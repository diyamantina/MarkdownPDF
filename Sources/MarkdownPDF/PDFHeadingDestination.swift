import Foundation

struct PDFHeadingDestination: Equatable {
    var name: String
    var title: String
    var level: Int
    var x: Double
    var y: Double

    func destinationArray(page: PDFSyntax.Reference) -> PDFSyntax.Array {
        PDFSyntax.Array([
            .reference(page),
            .pdfName("XYZ"),
            .number(x),
            .number(y),
            .null,
        ])
    }
}
