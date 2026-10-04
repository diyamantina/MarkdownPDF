@testable import MarkdownPDF
import Testing

/// Oracle: explicit expected orderings and folds, written out by hand from the
/// documented fold (decompose, lowercase, drop marks, ASCII-fold ligature letters,
/// collapse whitespace) so no platform collation is involved.
@Suite("Index collation")
struct IndexCollationTests {
    @Test(
        "Folds case, diacritics, ligatures and whitespace",
        arguments: [
            ("Layer", "layer"),
            ("Caf\u{E9}", "cafe"),
            ("Cafe\u{301}", "cafe"),
            ("Stra\u{DF}e", "strasse"),
            ("\u{C6}sir", "aesir"),
            ("\u{141}\u{F3}d\u{17A}", "lodz"),
            ("\u{110}uro", "duro"),
            ("  many   spaced \t words \n", "many spaced words"),
            ("\u{C5}ngstr\u{F6}m", "angstrom"),
            ("", ""),
        ],
    )
    func folds(input: String, expected: String) {
        #expect(IndexCollation.key(input) == expected)
    }

    @Test("Orders by folded scalars with a deterministic tie-break")
    func ordering() {
        let terms = ["zebra", "\u{C4}pfel", "apple", "Banana", "banana", "10 things", "#hash", "Caf\u{E9}", "cafe", "Cache"]
        let sorted = terms.sorted { IndexCollation.precedes($0, $1) }
        // Punctuation sorts before digits before letters; "apfel" before "apple";
        // folded-equal pairs fall back to scalar order (uppercase before lowercase).
        #expect(sorted == ["#hash", "10 things", "\u{C4}pfel", "apple", "Banana", "banana", "Cache", "Caf\u{E9}", "cafe", "zebra"])
        // The same set in any input order gives the same answer.
        let shuffled = terms.reversed().sorted { IndexCollation.precedes($0, $1) }
        #expect(shuffled == sorted)
    }

    @Test("Groups under an uppercase letter, symbols and digits under #")
    func groupHeadings() {
        #expect(IndexCollation.groupHeading(for: "apple") == "A")
        #expect(IndexCollation.groupHeading(for: "\u{C9}clair") == "E")
        #expect(IndexCollation.groupHeading(for: "10 things") == "#")
        #expect(IndexCollation.groupHeading(for: "#hash") == "#")
        #expect(IndexCollation.groupHeading(for: "") == "#")
    }

    @Test("Collapses consecutive pages to ranges and keeps gaps apart")
    func pageRanges() {
        func texts(_ pages: [Int], label: @escaping (Int) -> String = { String($0 + 1) }) -> [String] {
            PDFPageLabel.references(forPages: pages, label: label).map(\.text)
        }
        #expect(texts([]) == [])
        #expect(texts([0]) == ["1"])
        #expect(texts([11, 12, 13]) == ["12-14"])
        #expect(texts([0, 1]) == ["1-2"])
        #expect(texts([0, 2, 3, 4, 8]) == ["1", "3-5", "9"])
        #expect(texts([1, 2, 3], label: { PDFPageLabel.text($0 + 1, format: .romanLowercase) }) == ["ii-iv"])
        // The link target of a range is its first page.
        #expect(PDFPageLabel.references(forPages: [4, 5, 6]) { String($0) }.map(\.targetPage) == [4])
    }
}
