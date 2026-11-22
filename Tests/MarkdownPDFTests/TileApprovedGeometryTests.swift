import Foundation
@testable import MarkdownPDF
import Testing

/// The drawing of the board tiles the owner looked at and approved on 2026-11-22 ("looks good"): the pill box, the progress bar, the KPI card grid and the
/// timeline rail, as the exact numbers of the page's content stream (A4, 54 point margins, so a content width of 487.28). MEASURED on the drawing she saw, tag
/// `verified/pdf-tiles-s2-s3-2026-11-22`. A change to any number here changes what she approved and needs a permit that names the tag.
@Suite("Approved tile geometry (pinned 2026-11-22)")
struct TileApprovedGeometryTests {
    private struct Rectangle: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    private func stream(_ markdown: String) throws -> [String] {
        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let text = String(data: data, encoding: .isoLatin1) ?? ""
        return text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
    }

    /// The rectangles drawn, once each (a filled and stroked box is written twice).
    private func rectangles(_ markdown: String) throws -> [Rectangle] {
        let tokens = try stream(markdown)
        var found: [Rectangle] = []
        for (index, token) in tokens.enumerated() where token == "re" && index >= 4 {
            let numbers = tokens[(index - 4) ..< index].compactMap { Double($0) }
            guard numbers.count == 4 else { continue }
            let rectangle = Rectangle(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
            if found.last != rectangle {
                found.append(rectangle)
            }
        }
        return found
    }

    private func moves(_ markdown: String) throws -> [(Double, Double)] {
        let tokens = try stream(markdown)
        return tokens.enumerated().compactMap { index, token in
            guard token == "m", index >= 2, let x = Double(tokens[index - 2]), let y = Double(tokens[index - 1]) else { return nil }
            return (x, y)
        }
    }

    private func expect(_ actual: Rectangle?, _ x: Double, _ y: Double, _ width: Double, _ height: Double, _ name: String) {
        guard let actual else {
            Issue.record("\(name): no rectangle")
            return
        }
        let close = abs(actual.x - x) < 0.001 && abs(actual.y - y) < 0.001 && abs(actual.width - width) < 0.001 && abs(actual.height - height) < 0.001
        #expect(close, Comment(rawValue: "\(name): \(actual) expected \(x) \(y) \(width) \(height)"))
    }

    @Test("the pill is one box 21 points high at the left margin, as wide as its label and state plus the padding")
    func pill() throws {
        let boxes = try rectangles("```tile pill\nstatus: running\nlabel: Release 0.14.1\n```\n")
        #expect(boxes.count == 1)
        expect(boxes.first, 54, 766.890, 141.044, 21, "pill box")
    }

    @Test("the bar is a track the width of the page 8 points high, and a fill of exactly 3083 hundredths of it")
    func progress() throws {
        let boxes = try rectangles("```tile progress\nvalue: 37\nmax: 120\nlabel: Pages written\nstatus: running\n```\n")
        #expect(boxes.count == 2)
        expect(boxes.first, 54, 760.490, 487.280, 8, "track")
        expect(boxes.last, 54, 760.490, 150.228, 8, "fill")
        #expect(abs(487.28 * 3083 / 10000 - 150.228) < 0.001, "the fill is the exact fraction of the track")
    }

    @Test("the cards are three to a row, 157.093 wide and 72.1 high, 8 apart, and the fourth starts the next row")
    func cards() throws {
        let markdown = "```tile kpi\nkpi: Open issues\nvalue: 42\ndelta: +3\nnote: since Monday\nkpi: Failures\nvalue: 5\ndelta: +1\n"
            + "kpi: Done\nvalue: 17\nkpi: Rate\nvalue: 3.5%\ndelta: -2\n```\n"
        let boxes = try rectangles(markdown)
        #expect(boxes.count == 4)
        expect(boxes[0], 54, 715.790, 157.093, 72.1, "card 1")
        expect(boxes[1], 219.093, 715.790, 157.093, 72.1, "card 2")
        expect(boxes[2], 384.187, 715.790, 157.093, 72.1, "card 3")
        expect(boxes[3], 54, 635.690, 157.093, 72.1, "card 4 starts the next row")
        let cardsWidth: Double = 3 * 157.093
        let used: Double = cardsWidth + 16
        #expect(abs(used - 487.28) < 0.01, "three cards and two gaps fill the content width")
    }

    @Test("the rail starts at x 59 and each event has a dot of radius 3.2 on it")
    func timeline() throws {
        let markdown = "```tile timeline\norder: descending\nevent: A\ndate: 2026-11-22\nbody: b\nevent: B\ndate: 2026-11-10\ntime: 17:00\n```\n"
        let points = try moves(markdown)
        #expect(points.count == 4)
        let expected: [(Double, Double)] = [(59, 778.980), (62.2, 782.390), (59, 743.340), (62.2, 727.940)]
        for (actual, wanted) in zip(points, expected) {
            #expect(abs(actual.0 - wanted.0) < 0.001 && abs(actual.1 - wanted.1) < 0.001, Comment(rawValue: "\(actual) expected \(wanted)"))
        }
    }
}
