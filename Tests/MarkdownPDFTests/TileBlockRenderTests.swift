import Foundation
@testable import MarkdownPDF
import Testing

/// The board tiles in a generated PDF, read back by ``PDFDocumentReader``: the words of each tile, in the order of the page, the state always as a word,
/// and the geometry of what is drawn (the content stream of the page holds the exact rectangles of the bar).
@Suite("Tile blocks: the PDF")
struct TileBlockRenderTests {
    private func pdf(_ markdown: String) throws -> Data {
        try MarkdownPDFRenderer().render(markdown: markdown)
    }

    private func printed(_ markdown: String) throws -> [String] {
        try PDFDocumentReader(data: pdf(markdown)).pages.flatMap { $0.words.map(\.text) }
    }

    private static func fence(_ type: String, _ body: String) -> String {
        "```tile \(type)\n\(body)\n```\n"
    }

    @Test("a pill prints its label and its state as words")
    func pill() throws {
        let words = try printed(Self.fence("pill", "status: blocked\nlabel: Nightly build"))
        #expect(words == ["Nightly", "build", "blocked"], Comment(rawValue: "\(words)"))
    }

    @Test("a pill without a label prints the state, for each of the five states", arguments: ["running", "waiting", "blocked", "done", "failed"])
    func pillStates(status: String) throws {
        #expect(try printed(Self.fence("pill", "status: \(status)")) == [status])
    }

    @Test("the label of a pill and its state are apart: the state starts after the label ends, with room for a space")
    func pillGap() throws {
        let reader = try PDFDocumentReader(data: pdf(Self.fence("pill", "status: running\nlabel: Release 0.14.1")))
        let words = reader.pages.flatMap(\.words)
        let label = try #require(words.first { $0.text == "0.14.1" })
        let state = try #require(words.first { $0.text == "running" })
        #expect(state.x - (label.x + label.width) >= 3, Comment(rawValue: "gap \(state.x - (label.x + label.width))"))
    }

    @Test("a progress bar prints its label and the count as the page writes it")
    func progress() throws {
        let words = try printed(Self.fence("progress", "value: 37\nmax: 120\nlabel: Pages written\nstatus: running"))
        #expect(words == ["Pages", "written", "37", "of", "120", "(30%)"], Comment(rawValue: "\(words)"))
    }

    @Test("the fill of the bar is the exact fraction of the track: 1 of 3 is 33.33 percent, never more")
    func barGeometry() throws {
        let data = try pdf(Self.fence("progress", "value: 1\nmax: 3"))
        let stream = try #require(String(data: data, encoding: .isoLatin1))
        let contentWidth = 595.28 - 2 * MarkdownPDFRenderer().options.margins.left
        let expected = contentWidth * 3333 / 10000
        // the stream writes rectangles as `x y w h re`; the fill is the second one drawn
        let widths = stream.components(separatedBy: " re").dropLast().compactMap { part -> Double? in
            part.split(separator: " ").dropLast(0).suffix(4).dropFirst(2).first.flatMap { Double($0) }
        }
        #expect(widths.contains { abs($0 - expected) < 0.01 }, Comment(rawValue: "expected \(expected) in \(widths)"))
        #expect(!widths.contains { $0 > contentWidth * 3333 / 10000 + 0.01 && $0 < contentWidth - 0.01 })
    }

    @Test("a KPI row prints each card's label, value, the word of the change and its text, and the note, in order")
    func kpi() throws {
        let words = try printed(Self.fence("kpi", "kpi: Open issues\nvalue: 42\ndelta: +3\nnote: since Monday\nkpi: Failures\nvalue: 5\ndelta: +1\ntone: bad"))
        #expect(words == ["Open", "issues", "42", "up", "+3", "since", "Monday", "Failures", "5", "up", "+1"], Comment(rawValue: "\(words)"))
    }

    @Test("a down and a flat change print their words")
    func kpiWords() throws {
        let words = try printed(Self.fence("kpi", "kpi: A\nvalue: 1\ndelta: -2\nkpi: B\nvalue: 2\ndelta: 0"))
        #expect(words.contains("down") && words.contains("flat"), Comment(rawValue: "\(words)"))
    }

    @Test("a tile the engine refuses is a code block that says why, with its body, not a lost block")
    func refused() throws {
        let words = try printed(Self.fence("pill", "status: ok"))
        #expect(words.contains("Unsupported") && words.contains("tile:") && words.contains("ok"), Comment(rawValue: "\(words)"))
        #expect(try printed(Self.fence("gauge", "value: 1")).contains("gauge"))
    }

    @Test("no tile text runs outside the page or onto its neighbour, and the prose around a tile stays in order")
    func inContext() throws {
        let markdown = "Before.\n\n" + Self.fence("pill", "status: done\nlabel: Docs") + "\n"
            + Self.fence("progress", "value: 10\nmax: 11") + "\nAfter.\n"
        let reader = try PDFDocumentReader(data: pdf(markdown))
        let all = reader.pages.flatMap(\.words)
        #expect(all.map(\.text) == ["Before.", "Docs", "done", "10", "of", "11", "(90%)", "After."], Comment(rawValue: "\(all.map(\.text))"))
        #expect(all.allSatisfy { $0.width > 0 && $0.x >= 0 && $0.x + $0.width <= 595.28 })
        let ys = all.map(\.y)
        #expect(ys == ys.sorted(by: >), "each block is below the one before it")
    }

    @Test("twelve cards wrap into rows and never leave the page")
    func manyCards() throws {
        let body = (1 ... 12).map { "kpi: K\($0)\nvalue: \($0)" }.joined(separator: "\n")
        let reader = try PDFDocumentReader(data: pdf(Self.fence("kpi", body)))
        let all = reader.pages.flatMap(\.words)
        #expect(all.map(\.text).filter { $0.hasPrefix("K") }.count == 12)
        #expect(all.allSatisfy { $0.x >= 0 && $0.x + $0.width <= 595.28 })
    }
}
