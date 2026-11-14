import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: greedy line filling. A line ends only when the next word, measured
/// without the space that follows it, does not fit in what is left of the measure.
/// The space after the last word of a line takes no room: it hangs past the measure,
/// where nothing is drawn.
///
/// The widths come from the base font tables and the positions from the generated
/// content stream, not from the renderer's own state.
@Suite("Line wrapping ignores the space at the end of a line")
struct LineWrapTrailingSpaceTests {
    private static let font = StandardFont.helvetica
    private static let size = 11.0
    private static let margin = 54.0
    private static let tolerance = 0.001

    private static func width(_ text: String, font: StandardFont = font) -> Double {
        font.width(of: text, size: size, fontSet: .pdfBase)
    }

    /// Options whose text measure is exactly `measure` points wide.
    private static func options(measure: Double) -> PDFOptions {
        var options = PDFOptions()
        options.baseFontSize = size
        options.margins = PDFOptions.Margins(top: margin, right: margin, bottom: margin, left: margin)
        options.pageSize = PDFOptions.PageSize(width: measure + margin * 2, height: 800)
        return options
    }

    /// The drawn lines of the first page, top to bottom, each the fragments that
    /// share a baseline, left to right.
    private static func lines(_ markdown: String, options: PDFOptions) throws -> [[ContentStreamGeometry.Text]] {
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
        let page = try #require(ContentStreamGeometry(pdf: pdf).pages.first)
        let baselines = Set(page.texts.map(\.y)).sorted(by: >)
        return baselines.map { baseline in
            page.texts.filter { $0.y == baseline }.sorted { $0.x < $1.x }
        }
    }

    private static func text(_ line: [ContentStreamGeometry.Text]) -> String {
        line.map(\.string).joined().trimmingCharacters(in: .whitespaces)
    }

    @Test("Two words that fill the measure exactly stay on one line when a third follows")
    func wordsThatFitExactlyStayTogether() throws {
        let measure = Self.width("alpha beta") + Self.tolerance
        let lines = try Self.lines("alpha beta gamma", options: Self.options(measure: measure))

        #expect(lines.map(Self.text) == ["alpha beta", "gamma"])
    }

    @Test("A word is moved down only when it does not fit without its trailing space")
    func everyBreakIsForced() throws {
        // Deterministic words of mixed length, so line ends fall at many offsets.
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        let words = (0 ..< 600).map { _ in
            String((0 ..< Int(next() % 11) + 1).map { _ in letters[Int(next() % 26)] })
        }
        let measure = 380.0
        let lines = try Self.lines(words.joined(separator: " "), options: Self.options(measure: measure))
        try #require(lines.count > 30)

        let rightEdge = Self.margin + measure
        var early: [String] = []
        for (line, following) in zip(lines, lines.dropFirst()) {
            let last = try #require(line.last)
            let first = try #require(following.first)
            let word = first.string.trimmingCharacters(in: .whitespaces)
            // Where the next word would have started, had it stayed on this line.
            let start = last.x + Self.width(last.string)
            if start + Self.width(word) <= rightEdge - Self.tolerance {
                early.append("\"\(word)\" fits after \"\(Self.text(line).suffix(24))\"")
            }
            // And no line may run past the measure, the hanging space aside.
            let inkEnd = last.x + Self.width(last.string.trimmingCharacters(in: .whitespaces))
            #expect(inkEnd <= rightEdge + Self.tolerance, "line runs past the measure: \(Self.text(line))")
        }
        #expect(early.isEmpty, "\(early.count) of \(lines.count) lines broke early: \(early.prefix(3))")
    }

    @Test("Spaces alone never start a line")
    func spacesNeverStartALine() throws {
        // In a code block every space is kept, so a run of spaces can pass the measure,
        // whatever the block's own font size and padding are.
        let word = String(repeating: "x", count: 20)
        let gap = String(repeating: " ", count: 40)
        let code = "```\n\(word)\(gap)\(word)\(gap)\(word)\n```\n"
        let measure = Self.width(word, font: .courier) * 1.5
        let lines = try Self.lines(code, options: Self.options(measure: measure))

        try #require(lines.count == 3)
        for line in lines {
            #expect(line.first?.string.hasPrefix("x") == true, "line starts with a space: \(line.map(\.string))")
        }
    }

    @Test("A right aligned table cell that wraps ends each line at the cell's edge")
    func rightAlignedCellLinesEndAtTheEdge() throws {
        let words = Array(repeating: "lorem ipsum dolor", count: 12).joined(separator: " ")
        let markdown = "| a | b |\n|---|--:|\n| x | \(words) |\n"
        let lines = try Self.lines(markdown, options: Self.options(measure: 300))
        // The wrapped lines of the second column: every line of the body row but the
        // one that also carries the first column's "x".
        let wrapped = lines.filter { line in line.allSatisfy { $0.string != "a" && $0.string != "b" && $0.string != "x" } }
        try #require(wrapped.count >= 2)

        let ends = wrapped.map { line -> Double in
            let last = line[line.count - 1]
            // A table cell has its own font size, so the fragment's size is used.
            let ink = last.string.trimmingCharacters(in: .whitespaces)
            return last.x + Self.font.width(of: ink, size: last.size, fontSet: .pdfBase)
        }
        let edge = try #require(ends.max())
        for (end, line) in zip(ends, wrapped) {
            #expect(abs(end - edge) < Self.tolerance, "line ends \(edge - end) pt short of the edge: \(Self.text(line))")
        }
    }
}
