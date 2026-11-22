import Foundation
@testable import MarkdownPDF
import Testing

/// A closing mark that does not fit on the line hangs a little past the measure (typographic hanging punctuation): `CATransform3D.` in a narrow table
/// cell stays whole, the dot standing in the cell's padding, and an identifier that fits the cell ALONE is never cut by character. The cell is the real
/// one of the swiftui-3d-is-flat table; the right margin is swept so the dot meets the end of the line at every position, and the margins where the
/// bare identifier fits are MEASURED by the same sweep without the mark.
@Suite("A closing mark hangs, and an identifier that fits alone is never cut")
struct ClosingPunctuationHangTests {
    private static let cellText = "Per-view projection, initializable from `CATransform3D`"
    private static let rightMargins = Array(stride(from: 54.0, to: 330.0, by: 1.0))

    private func words(_ markdown: String, rightMargin: Double) throws -> [PDFDocumentReader.Word] {
        var options = PDFOptions(embeddedFonts: .dejaVu)
        options.margins = PDFOptions.Margins(top: 54, right: rightMargin, bottom: 54, left: 54)
        let data = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
        return try PDFDocumentReader(data: data).pages.flatMap(\.words)
    }

    private func table(_ cell: String) -> String {
        "| Claim | Status | Evidence |\n|---|---|---|\n| `CALayer.transform` | `rotation3DEffect` | \(cell) |\n"
    }

    @Test("MEASURED by the same sweep without the mark: the margins where the bare identifier is whole are the oracle's domain")
    func domainIsNotEmpty() throws {
        let whole = try Self.rightMargins.filter { margin in
            try words(table(Self.cellText), rightMargin: margin).contains { $0.text == "CATransform3D" }
        }
        #expect(whole.count > 100, Comment(rawValue: "only \(whole.count) margins keep the bare identifier whole"))
    }

    @Test("the identifier with its full stop is one whole word at every margin where the bare identifier is whole", arguments: [".", ",", ";"])
    func identifierWithMarkIsWhole(mark: String) throws {
        var broken: [Double] = []
        for margin in Self.rightMargins {
            let bare = try words(table(Self.cellText), rightMargin: margin).contains { $0.text == "CATransform3D" }
            guard bare else { continue }
            let found = try words(table(Self.cellText + mark), rightMargin: margin)
            if !found.contains(where: { $0.text == "CATransform3D" + mark }) {
                broken.append(margin)
            }
        }
        #expect(broken.isEmpty, Comment(rawValue: "`CATransform3D\(mark)` is not one whole word at the right margins \(broken)"))
    }

    @Test("a hanging mark never crosses the border of its cell: the table's right edge")
    func hangStaysInsideTheBorder() throws {
        let edgeOf = { (margin: Double) in PDFOptions.PageSize.a4.width - margin }
        var crossed: [Double] = []
        for margin in Self.rightMargins {
            let found = try words(table(Self.cellText + "."), rightMargin: margin)
            if found.contains(where: { $0.x + $0.width > edgeOf(margin) }) {
                crossed.append(margin)
            }
        }
        #expect(crossed.isEmpty, Comment(rawValue: "a word crosses the table's right edge at the right margins \(crossed)"))
    }

    @Test("a body paragraph: the mark that does not fit starts no line alone and the whole word stays whole")
    func paragraph() throws {
        var alone: [Double] = []
        for margin in Self.rightMargins {
            let found = try words("Per-view projection, initializable from `CATransform3D`. Then more.\n", rightMargin: margin)
            if found.contains(where: { $0.text == "." }) {
                alone.append(margin)
            }
        }
        #expect(alone.isEmpty, Comment(rawValue: "`.` stands alone at the right margins \(alone)"))
    }
}
