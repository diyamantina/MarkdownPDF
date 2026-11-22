import Foundation
@testable import MarkdownPDF
import Testing

/// A word is not broken inside itself in a table cell. The column floors give each column the width of its widest word, cut down to one common level
/// when the widest words of all the columns together are wider than the page (see ``TableColumnFloors``), so only the widest words are broken at all;
/// and a word that has to be broken is cut where it reads best (after a `.`, `/`, `_`, `-` or `:`, or between a lower-case letter or digit and a
/// capital), never inside a part of it. Only a word with no such place in the part that fits is cut by character.
@Suite("Table cells do not break a word inside itself")
struct TableWordBreakTests {
    /// The whole table of "SwiftUI 3D is flat", cell text as written: five columns, an identifier in several of them. The widest words of all the columns
    /// together are wider than the page (525 pt of words in a 487 pt page). The columns that ended up narrow broke `CALayer.anchorPoint` into
    /// `CALayer.anchorPo` and `int`, `CALayer.transform` into `CALayer.transfor` and `m`, `ProjectionTransform` into `ProjectionTransfor` and `m`.
    private static let table = """
    | Core Animation input | SwiftUI output | Preserved | Collapsed or rejected | Consequence for the cube |
    |---|---|---|---|---|
    | `CALayer.anchorPoint` | `anchor: UnitPoint` | The normalized 2D pivot. | The persistent layer field is gone. The anchor is an argument to one transform or layout operation. | You can pivot one view effect. You cannot rebase an enduring subtree. |
    | `CALayer.anchorPointZ` | `anchorZ` on `rotation3DEffect` | A Z pivot for one 3D rotation. | Scoped to the modifier, not stored as layer geometry. | `anchorZ: -side / 2` can hinge one face. It cannot create shared depth. |
    | `CALayer.transform` | `rotation3DEffect`, `projectionEffect`, `GeometryEffect` returning `ProjectionTransform` | Per-view projection, initializable from `CATransform3D`. | Retained `CATransform3D` layer state is collapsed into a projection of rendered output. | One card flip can be correct. Six projected cards are still six siblings. |
    | `CALayer.sublayerTransform` | Nothing on iOS/macOS | Nothing at parent-view level. | Rejected: no parent camera matrix over child views. | No single perspective shared by all faces, and no shared vanishing point. |
    | `CATransformLayer` | Nothing on iOS/macOS | Nothing. | Rejected: no non-flattening child container. | This is the missing primitive. Without it, a cube is only a pose. |
    | `zPosition` | `zIndex` | A draw-order priority. | Geometric depth collapsed into painter's order. | The order can be chosen. It is never recomputed from camera depth. |
    | `CALayer.doubleSided` | Nothing direct | Nothing direct. | Back-face culling is not exposed as a view-compositor rule. | A two-sided card swaps content manually, per-face simulation, not compositor culling. |
    """

    private static let identifiers = [
        "CALayer.anchorPoint", "CALayer.anchorPointZ", "CALayer.transform", "CALayer.sublayerTransform", "CALayer.doubleSided",
        "CATransformLayer", "CATransform3D", "rotation3DEffect", "projectionEffect", "GeometryEffect", "ProjectionTransform", "UnitPoint",
    ]

    private func words(_ markdown: String) throws -> [String] {
        let renderer = MarkdownPDFRenderer(options: PDFOptions(embeddedFonts: .dejaVu))
        return try PDFDocumentReader(data: renderer.render(markdown: markdown)).pages.flatMap(\.words).map(\.text)
    }

    /// The offsets in `identifier` after which a cut reads well: after a separator, or between a lower-case letter or digit and a capital.
    private func softBreakOffsets(of identifier: String) -> Set<Int> {
        let characters = Array(identifier)
        var offsets = Set<Int>()
        for index in 1 ..< characters.count {
            let before = characters[index - 1]
            let after = characters[index]
            if ".,/_-:".contains(before) || ((before.isLowercase || before.isNumber) && after.isUppercase) {
                offsets.insert(index)
            }
        }
        return offsets
    }

    /// Every run of consecutive printed words that, joined, spells `identifier`: the lengths of its pieces.
    private func occurrences(of identifier: String, in printed: [String]) -> [[Int]] {
        var found: [[Int]] = []
        for start in printed.indices {
            var joined = ""
            var lengths: [Int] = []
            for word in printed[start...] {
                joined += word
                lengths.append(word.count)
                // A trailing comma or full stop of the sentence belongs to the last piece, not to the identifier.
                let trimmed = joined.trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
                if trimmed == identifier {
                    found.append(lengths)
                    break
                }
                if !identifier.hasPrefix(trimmed) {
                    break
                }
            }
        }
        return found
    }

    @Test("every identifier of the table is printed, and each place where it is cut is a soft break point of it")
    func cutsAreAtSoftBreakPoints() throws {
        let printed = try words(Self.table)
        for identifier in Self.identifiers {
            let runs = occurrences(of: identifier, in: printed)
            #expect(!runs.isEmpty, Comment(rawValue: "\(identifier) is not printed in pieces that join back to it: \(printed)"))
            let allowed = softBreakOffsets(of: identifier)
            for lengths in runs {
                var offset = 0
                for length in lengths.dropLast() {
                    offset += length
                    #expect(allowed.contains(offset), Comment(rawValue: "\(identifier) is cut after \(offset) characters, not at a break point; pieces \(lengths)"))
                }
            }
        }
    }

    @Test("a table whose words fit is not changed: the identifiers stay whole")
    func fittingTableKeepsWords() throws {
        let printed = try words("| API | Note |\n|---|---|\n| `CALayer.anchorPoint` | Short. |\n| `rotation3DEffect` | Also short. |\n")
        #expect(printed.contains("CALayer.anchorPoint") && printed.contains("rotation3DEffect"), Comment(rawValue: "\(printed)"))
    }

    @Test("a word wider than the whole page is the last resort: broken by character, with every character kept")
    func lastResort() throws {
        let long = String(repeating: "x", count: 200)
        let joined = try words("| a | b |\n|---|---|\n| \(long) | y |\n").joined(separator: "")
        #expect(joined.contains(long), "the 200 characters are all printed, in pieces")
    }

    @Test("the soft break offsets are the closed form: after a separator, and before a capital that follows a lower-case letter or digit")
    func offsets() {
        // a . b C: after the dot (2) and between b and C (3).
        #expect(softBreakOffsets(of: "a.bC") == [2, 3])
        #expect(softBreakOffsets(of: "rotation3DEffect") == [9])
        #expect(softBreakOffsets(of: "plain") == [])
    }
}
