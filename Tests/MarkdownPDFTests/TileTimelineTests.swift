import Foundation
@testable import MarkdownPDF
import Testing

/// A timeline tile in the PDF: dated events down a rail, sorted by date and time with the written order kept for the same moment, in the words of the page
/// (the date and time as written, the title, the body). The checks of a date are the page's: a real calendar date, a time from 00:00 to 23:59.
@Suite("Tile blocks: the timeline")
struct TileTimelineTests {
    private func timeline(_ body: String) -> TileBlock.Timeline? {
        if case let .tile(.timeline(timeline)) = TileBlock.parse(type: "timeline", body: body) {
            return timeline
        }
        return nil
    }

    private func refusal(_ body: String) -> String? {
        if case let .unsupported(reason) = TileBlock.parse(type: "timeline", body: body) {
            return reason
        }
        return nil
    }

    @Test("events are sorted by date and time, whatever order they are written in, and the written order holds for one moment")
    func sorting() {
        let body = """
        event: C
        date: 2026-11-20
        event: A
        date: 2026-11-01
        time: 09:30
        event: B
        date: 2026-11-01
        event: A2
        date: 2026-11-01
        time: 09:30
        """
        #expect(timeline(body)?.events.map(\.title) == ["B", "A", "A2", "C"])
        #expect(timeline("order: descending\n" + body)?.events.map(\.title) == ["C", "A", "A2", "B"])
    }

    @Test("an event without a time sorts before the timed events of its day, in both directions' written order")
    func untimed() {
        let body = "event: late\ndate: 2026-01-01\ntime: 00:01\nevent: none\ndate: 2026-01-01"
        #expect(timeline(body)?.events.map(\.title) == ["none", "late"])
    }

    @Test("the lines of an event are its date, its optional time and body, kept as written")
    func lines() {
        let events = timeline("event: Release 0.13.0\ndate: 2026-11-22\nbody: shipped\nevent: Plan\ndate: 2026-11-01\ntime: 09:30")?.events
        #expect(events?.first == .init(title: "Plan", date: "2026-11-01", time: "09:30", body: nil))
        #expect(events?.last == .init(title: "Release 0.13.0", date: "2026-11-22", time: nil, body: "shipped"))
    }

    @Test("real calendar dates only", arguments: [
        ("2026-02-29", false), ("2024-02-29", true), ("2100-02-29", false), ("2000-02-29", true),
        ("2026-04-31", false), ("2026-12-31", true), ("2026-13-01", false), ("2026-00-10", false),
        ("2026-1-01", false), ("26-01-01", false), ("2026/01/01", false), ("0000-01-01", false), ("2026-01-0a", false),
    ])
    func dates(date: String, valid: Bool) {
        let result = timeline("event: E\ndate: \(date)")
        #expect((result != nil) == valid, Comment(rawValue: date))
    }

    @Test("times run from 00:00 to 23:59", arguments: [
        ("00:00", true), ("23:59", true), ("24:00", false), ("12:60", false), ("9:30", false), ("09:3", false), ("12-30", false),
    ])
    func times(time: String, valid: Bool) {
        #expect((timeline("event: E\ndate: 2026-01-01\ntime: \(time)") != nil) == valid, Comment(rawValue: time))
    }

    @Test("every mistake is a refusal that says what to change", arguments: [
        ("", "no event"),
        ("date: 2026-01-01", "before"),
        ("event: A", "date"),
        ("event: \ndate: 2026-01-01", "title"),
        ("event: A\ndate: 2026-01-01\ndate: 2026-01-02", "twice"),
        ("event: A\ndate: 2026-01-01\nmood: x", "mood"),
        ("event: A\ndate: 2026-01-01\norder: descending", "order"),
        ("order: sideways\nevent: A\ndate: 2026-01-01", "ascending or descending"),
        ("event: A\ndate: 2026-02-30", "2026-02-30"),
        ("event: A\ndate: 2026-01-01\ntime: 25:00", "25:00"),
    ])
    func refusals(body: String, mention: String) {
        let reason = refusal(body)
        #expect(reason?.contains(mention) == true, Comment(rawValue: reason ?? "no refusal"))
    }

    @Test("two hundred events are fine and two hundred and one are not")
    func limit() {
        let many = (1 ... 200).map { "event: E\($0)\ndate: 2026-01-01" }.joined(separator: "\n")
        #expect(timeline(many) != nil)
        #expect(refusal(many + "\nevent: E201\ndate: 2026-01-01")?.contains("200") == true)
    }

    @Test("the PDF prints, for each event in order, the date (and time), the title and the body")
    func printed() throws {
        let markdown = "```tile timeline\norder: descending\nevent: Release 0.13.0\ndate: 2026-11-22\nbody: shipped\n"
            + "event: Plan the board\ndate: 2026-11-01\ntime: 09:30\n```\n"
        let reader = try PDFDocumentReader(data: MarkdownPDFRenderer().render(markdown: markdown))
        let words = reader.pages.flatMap(\.words)
        #expect(words.map(\.text) == ["2026-11-22", "Release", "0.13.0", "shipped", "2026-11-01", "09:30", "Plan", "the", "board"], Comment(rawValue: "\(words.map(\.text))"))
        #expect(words.allSatisfy { $0.width > 0 && $0.x >= 0 && $0.x + $0.width <= 595.28 })
        let ys = words.map(\.y)
        #expect(ys == ys.sorted(by: >))
    }

    @Test("a long timeline runs onto the next page and never leaves a page")
    func pages() throws {
        let events = (1 ... 80).map { "event: Event \($0)\ndate: 2026-01-\(String(format: "%02d", min($0, 28)))\nbody: text \($0)" }.joined(separator: "\n")
        let reader = try PDFDocumentReader(data: MarkdownPDFRenderer().render(markdown: "```tile timeline\n\(events)\n```\n"))
        #expect(reader.pages.count > 1)
        #expect(reader.pages.flatMap(\.words).allSatisfy { $0.y > 0 && $0.y < 842 })
    }
}
