import Foundation

struct PDFHeadingDestination: Equatable {
    var name: String
    var title: String
    var level: Int
    var x: Double
    var y: Double
    /// True for an outline entry that never becomes a parent: a later, deeper heading
    /// belongs to the previous real heading, not to this one. The cover uses it.
    var isOutlineLeaf = false
    /// False for a heading deeper than ``PDFOptions/outlineMaxHeadingLevel``: it stays a
    /// destination that links can target, but gets no outline entry.
    var inOutline = true

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
