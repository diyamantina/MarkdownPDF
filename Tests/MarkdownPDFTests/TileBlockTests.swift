@testable import MarkdownPDF
import Testing

/// The board tiles of a TileDown page (a pill, a progress bar, a KPI row) in a PDF. The fence is ```tile TYPE, and the lines of its body are the lines of
/// the tile on the page, so a page's tile and its print have the same syntax. Every case is either a tile or a named refusal; nothing is guessed.
@Suite("Tile blocks: parsing and the exact numbers")
struct TileBlockTests {
    private func tile(_ type: String, _ body: String) -> TileBlock? {
        if case let .tile(block) = TileBlock.parse(type: type, body: body) {
            return block
        }
        return nil
    }

    private func refusal(_ type: String, _ body: String) -> String? {
        if case let .unsupported(reason) = TileBlock.parse(type: type, body: body) {
            return reason
        }
        return nil
    }

    // MARK: pill

    @Test("a pill is a status and an optional label, the five states only")
    func pill() {
        #expect(tile("pill", "status: blocked\nlabel: Nightly build") == .pill(.init(status: .blocked, label: "Nightly build")))
        #expect(tile("pill", "status: done") == .pill(.init(status: .done, label: nil)))
        for word in ["running", "waiting", "blocked", "done", "failed"] {
            #expect(tile("pill", "status: \(word)") != nil, Comment(rawValue: word))
        }
    }

    @Test("every mistake of a pill is a refusal that says what is wrong")
    func pillRefusals() {
        #expect(refusal("pill", "label: x")?.contains("status") == true)
        #expect(refusal("pill", "status: ok")?.contains("running, waiting, blocked, done or failed") == true)
        #expect(refusal("pill", "status: Running") != nil)
        #expect(refusal("pill", "status: done\ncolor: red")?.contains("color") == true)
        #expect(refusal("pill", "status: done\nstatus: failed")?.contains("twice") == true)
        #expect(refusal("pill", "") != nil)
    }

    // MARK: progress

    @Test("a progress bar has a value, a total of 100 by default, an optional label and a status of running by default")
    func progress() {
        #expect(tile("progress", "value: 37\nmax: 120\nlabel: Pages written\nstatus: waiting")
            == .progress(.init(value: 37, max: 120, label: "Pages written", status: .waiting)))
        #expect(tile("progress", "value: 5") == .progress(.init(value: 5, max: 100, label: nil, status: .running)))
    }

    @Test(
        "the numbers and the width are exact integer arithmetic, rounded down, never fuller than the count",
        arguments: [
            (0, 1, 0, 0, "0 of 1 (0%)"),
            (1, 3, 3333, 33, "1 of 3 (33%)"),
            (2, 3, 6666, 66, "2 of 3 (66%)"),
            (37, 120, 3083, 30, "37 of 120 (30%)"),
            (10, 11, 9090, 90, "10 of 11 (90%)"),
            (1, 1, 10000, 100, "1 of 1 (100%)"),
            (999_999_999_999, 1_000_000_000_000, 9999, 99, "999999999999 of 1000000000000 (99%)"),
            (1_000_000_000_000, 1_000_000_000_000, 10000, 100, "1000000000000 of 1000000000000 (100%)"),
        ],
    )
    func arithmetic(value: Int, max: Int, hundredths: Int, percent: Int, text: String) {
        let progress = TileBlock.Progress(value: value, max: max, label: nil, status: .running)
        #expect(progress.hundredths == hundredths)
        #expect(progress.percent == percent)
        #expect(progress.numbers == text)
    }

    @Test("every mistake of a progress bar is a refusal", arguments: [
        ("max: 10", "value"),
        ("value: 11\nmax: 10", "above"),
        ("value: -1", "whole"),
        ("value: 1.5", "whole"),
        ("value: x", "whole"),
        ("value: 1\nmax: 0", "max"),
        ("value: 1\nmax: 1000000000001", "max"),
        ("value: 1\nstatus: ok", "running, waiting, blocked, done or failed"),
        ("value: 1\nspeed: 3", "speed"),
        ("value: 1\nvalue: 2", "twice"),
    ])
    func progressRefusals(body: String, mention: String) {
        let reason = refusal("progress", body)
        #expect(reason?.contains(mention) == true, Comment(rawValue: reason ?? "no refusal"))
    }

    // MARK: kpi

    @Test("each kpi line starts a card and the lines after it belong to it; the change defaults to the sign of the delta")
    func kpi() {
        guard case let .kpi(cards)? = tile("kpi", """
        kpi: Open issues
        value: 42
        delta: +3
        note: since Monday
        kpi: Failures
        value: 5
        delta: +1
        tone: bad
        kpi: Done
        value: 17
        kpi: Rate
        value: 3.5%
        delta: -2
        kpi: Same
        value: 1
        delta: 0
        """) else {
            Issue.record("not a kpi row")
            return
        }
        #expect(cards.map(\.label) == ["Open issues", "Failures", "Done", "Rate", "Same"])
        #expect(cards.map(\.value) == ["42", "5", "17", "3.5%", "1"])
        #expect(cards[0].change == .init(trend: .up, tone: .good, delta: "+3"))
        #expect(cards[0].note == "since Monday")
        #expect(cards[1].change == .init(trend: .up, tone: .bad, delta: "+1"))
        #expect(cards[2].change == nil)
        #expect(cards[3].change == .init(trend: .down, tone: .bad, delta: "-2"))
        #expect(cards[4].change == .init(trend: .flat, tone: .neutral, delta: "0"))
    }

    @Test("the minus sign counts as down, an explicit trend wins over the sign, and a trend needs a delta")
    func kpiTrend() {
        guard case let .kpi(cards)? = tile("kpi", "kpi: A\nvalue: 1\ndelta: \u{2212}4\nkpi: B\nvalue: 2\ndelta: -1\ntrend: up") else {
            Issue.record("not a kpi row")
            return
        }
        #expect(cards[0].change?.trend == .down)
        #expect(cards[1].change?.trend == .up)
        #expect(refusal("kpi", "kpi: A\nvalue: 1\ntrend: up")?.contains("delta") == true)
        #expect(refusal("kpi", "kpi: A\nvalue: 1\ndelta: +1\ntrend: sideways")?.contains("up, down or flat") == true)
        #expect(refusal("kpi", "kpi: A\nvalue: 1\ndelta: +1\ntone: great")?.contains("good, bad or neutral") == true)
    }

    @Test("every other mistake of a KPI row is a refusal, and at most twelve cards", arguments: [
        ("", "no card"),
        ("value: 1", "before"),
        ("kpi: A", "value"),
        ("kpi: \nvalue: 1", "label"),
        ("kpi: A\nvalue: 1\nvalue: 2", "twice"),
        ("kpi: A\nvalue: 1\nweight: 2", "weight"),
    ])
    func kpiRefusals(body: String, mention: String) {
        let reason = refusal("kpi", body)
        #expect(reason?.contains(mention) == true, Comment(rawValue: reason ?? "no refusal"))
    }

    @Test("twelve cards are fine and thirteen are not")
    func kpiLimit() {
        let twelve = (1 ... 12).map { "kpi: K\($0)\nvalue: \($0)" }.joined(separator: "\n")
        #expect(tile("kpi", twelve) != nil)
        #expect(refusal("kpi", twelve + "\nkpi: K13\nvalue: 13")?.contains("12") == true)
    }

    // MARK: the type

    @Test("a type this renderer does not draw is a refusal that names it")
    func unknownType() {
        #expect(refusal("gauge", "value: 1")?.contains("gauge") == true)
    }

    @Test("blank lines and the spaces around a line do not matter, a line without a colon is a refusal")
    func lines() {
        #expect(tile("pill", "\n  status:   done  \n\n  label:  A b \n") == .pill(.init(status: .done, label: "A b")))
        #expect(refusal("pill", "status done")?.contains("status done") == true)
    }
}
