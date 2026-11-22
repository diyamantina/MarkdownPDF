import Foundation
@testable import MarkdownPDF
import Testing

/// A word is not broken inside itself in a table cell. The column widths give each column at least the width of the widest piece of its words that
/// has no break point inside it (a `.` in an identifier, a camelCase boundary, a hyphen, a slash are break points) before the free width is shared, so
/// `CALayer.anchorPoint` is read whole or breaks at its dot. A piece that cannot fit even in the widest column the page allows is the last case, broken
/// by character.
@Suite("Table cells do not break a word inside itself")
struct TableWordBreakTests {
    /// Two rows of the table of "SwiftUI 3D is flat": five columns of prose after an identifier column. The columns that ended up narrow broke
    /// `CALayer.anchorPoint` into `CALayer.anchorPo` and `int`.
    private static let table = """
    | Core Animation input | SwiftUI output | Preserved | Collapsed or rejected | Consequence for the cube |
    |---|---|---|---|---|
    | `CALayer.anchorPoint` | `anchor: UnitPoint` | The normalized 2D pivot. | The persistent layer field is gone. The anchor is an argument to one transform or layout operation. | You can pivot one view effect. You cannot rebase an enduring subtree. |
    | `CALayer.anchorPointZ` | `anchorZ` on `rotation3DEffect` | A Z pivot for one 3D rotation. | Scoped to the modifier, not stored as layer geometry. | `anchorZ: -side / 2` can hinge one face. It cannot create shared depth. |
    """

    private static let identifiers = ["CALayer.anchorPoint", "CALayer.anchorPointZ", "rotation3DEffect", "UnitPoint"]

    private func words(_ markdown: String) throws -> [String] {
        let renderer = MarkdownPDFRenderer(options: PDFOptions(embeddedFonts: .dejaVu))
        return try PDFDocumentReader(data: renderer.render(markdown: markdown)).pages.flatMap(\.words).map(\.text)
    }

    /// The substrings of `identifier` that start and end at a break point: the start, the end, after a `.`, and where a capital follows a lower-case letter.
    private func allowedPieces(of identifier: String) -> Set<String> {
        let characters = Array(identifier)
        var boundaries = [0, characters.count]
        for index in 1 ..< characters.count {
            let after = characters[index - 1] == "."
            let camel = characters[index].isUppercase && characters[index - 1].isLowercase
            if after || camel {
                boundaries.append(index)
            }
        }
        boundaries.sort()
        var pieces = Set<String>()
        for start in boundaries {
            for end in boundaries where end > start {
                pieces.insert(String(characters[start ..< end]))
            }
        }
        return pieces
    }

    @Test("every printed piece of an identifier starts and ends at a break point of it")
    func piecesStartAndEndAtBreakPoints() throws {
        let printed = try words(Self.table)
        for identifier in Self.identifiers {
            let allowed = allowedPieces(of: identifier)
            for word in printed where word.count >= 3 && word != identifier && identifier.contains(word) {
                #expect(allowed.contains(word), Comment(rawValue: "\(identifier) is broken inside a word: `\(word)` is not cut at a break point; words: \(printed)"))
            }
        }
    }

    @Test("the identifiers are printed, each whole or in pieces that join back to it")
    func identifiersArePrinted() throws {
        let joined = try words(Self.table).joined(separator: "")
        for identifier in Self.identifiers {
            #expect(joined.contains(identifier), Comment(rawValue: "\(identifier) is not in the printed words"))
        }
    }

    @Test("a word wider than the whole page is the last resort: broken by character, with every character kept")
    func lastResort() throws {
        let long = String(repeating: "x", count: 200)
        let joined = try words("| a | b |\n|---|---|\n| \(long) | y |\n").joined(separator: "")
        #expect(joined.contains(long), "the 200 characters are all printed, in pieces")
    }

    @Test("the allowed pieces are the closed form: start, after a dot, at a capital after a lower-case letter, end")
    func pieces() {
        // a . b C: boundaries 0, 2 (after the dot), 3 (the capital C after b), 4.
        #expect(allowedPieces(of: "a.bC") == ["a.", "a.b", "a.bC", "b", "bC", "C"])
    }
}
