import ExtendedMarkdownCore
import Foundation
@testable import MarkdownPDF
import Testing

/// Every tick label of a chart lies inside the page and inside the chart's frame, at every page width. The line chart
/// "Temps de rendu" of the showcase fixture `05-charts-dashboard.md` drew the label "20" past the right edge of the
/// page: its x values run from 1 to 16, and the axis drew the ticks 0 and 20 of the rounded range although the plot
/// spans 1 to 16 only.
///
/// The drawn labels are read back from the PDF with the package's reader and compared with `ChartTickLabelKey`, an
/// answer key that shares no code with the renderer.
@Suite("A chart's tick labels stay inside the page and the chart's frame")
struct ChartTickLabelTests {
    /// What a rendered chart shows: its frame as drawn, and its label runs.
    private struct Drawn {
        var box: (x: Double, y: Double, width: Double, height: Double)
        var xLabels: [PDFDocumentReader.TextRun]
        var yLabels: [PDFDocumentReader.TextRun]
        var all: [PDFDocumentReader.TextRun]
    }

    private static let pageHeight = 792.0
    private static let tolerance = 0.01

    /// The chart of the key, rendered and read back, or `nil` when the renderer reported the chart as not drawable and
    /// printed its source instead.
    private static func draw(_ key: ChartTickLabelKey) throws -> Drawn? {
        let options = PDFOptions(
            pageSize: PDFOptions.PageSize(width: key.pageWidth, height: pageHeight),
            margins: PDFOptions.Margins(top: 36, right: key.margin, bottom: 36, left: key.margin),
        )
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: key.markdown)
        let text = String(decoding: pdf, as: UTF8.self)
        let expression = try NSRegularExpression(pattern: #"(-?[0-9.]+) (-?[0-9.]+) (-?[0-9.]+) (-?[0-9.]+) re"#)
        let range = NSRange(text.startIndex..., in: text)
        let boxes = expression.matches(in: text, range: range).compactMap { match -> [Double]? in
            let numbers = (1 ... 4).compactMap { Range(match.range(at: $0), in: text).flatMap { Double(text[$0]) } }
            return numbers.count == 4 ? numbers : nil
        }
        let frameWidth = key.pageWidth - 2 * key.margin + 8
        guard let box = boxes.first(where: { abs($0[2] - frameWidth) < tolerance && $0[3] >= 170 }) else {
            return nil
        }
        let pages = try PDFDocumentReader(data: pdf).pages
        try #require(pages.count == 1, "a single chart takes one page")
        let runs = pages[0].runs.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let numeric = runs.filter { Double($0.text) != nil }
        let axisBaseline = numeric.map(\.y).min() ?? 0
        return Drawn(
            box: (box[0], box[1], box[2], box[3]),
            xLabels: numeric.filter { abs($0.y - axisBaseline) < tolerance }.sorted { $0.x < $1.x },
            yLabels: numeric.filter { abs($0.y - axisBaseline) >= tolerance }.sorted { $0.y < $1.y },
            all: runs,
        )
    }

    /// Compares one drawn chart with the key. Every difference is recorded with the chart that shows it.
    private static func check(_ key: ChartTickLabelKey, _ drawn: Drawn) {
        let name = "\(key.kind) chart, page \(key.pageWidth), margin \(key.margin), points \(key.points)"
        let frame = key.frame
        for run in drawn.all {
            let right = run.x + run.width
            #expect(run.x >= -tolerance && right <= key.pageWidth + tolerance, Comment(rawValue: "'\(run.text)' at \(run.x)...\(right) leaves the page: \(name)"))
            #expect(
                run.x >= frame.lowerBound - tolerance && right <= frame.upperBound + tolerance,
                Comment(rawValue: "'\(run.text)' at \(run.x)...\(right) leaves the frame \(frame): \(name)"),
            )
            #expect(
                run.y >= drawn.box.y - tolerance && run.y + run.fontSize <= drawn.box.y + drawn.box.height + tolerance,
                Comment(rawValue: "'\(run.text)' at baseline \(run.y) leaves the frame from \(drawn.box.y), \(drawn.box.height) high: \(name)"),
            )
        }
        // A chart with a tick between two hundredths is held to the page and the frame only: the key does not say its labels.
        guard key.labelsAreExact else {
            return
        }
        compare(drawn.xLabels, with: key.xLabels.sorted { $0.left < $1.left }, axis: "x", name)
        compare(drawn.yLabels, with: key.yLabels, axis: "y", name)
    }

    private static func compare(_ runs: [PDFDocumentReader.TextRun], with labels: [ChartTickLabelKey.Label], axis: String, _ name: String) {
        #expect(runs.map(\.text) == labels.map(\.text), Comment(rawValue: "the \(axis) axis shows other labels than the key says: \(name)"))
        for (run, label) in zip(runs, labels) where run.text == label.text {
            #expect(abs(run.x - label.left) < tolerance, Comment(rawValue: "\(axis) label '\(run.text)' starts at \(run.x), the key says \(label.left): \(name)"))
            #expect(abs(run.width - label.width) < tolerance, Comment(rawValue: "\(axis) label '\(run.text)' is \(run.width) wide, the key says \(label.width): \(name)"))
        }
    }

    // MARK: The defect

    @Test("the chart of the showcase fixture keeps the ticks 5, 10 and 15 and draws none outside the plot")
    func showcaseChart() throws {
        let key = ChartTickLabelKey(
            kind: .line,
            points: [(1, 12), (2, 19), (4, 33), (8, 61), (16, 118)],
            pageWidth: 612,
            margin: 54,
        )
        let drawn = try #require(try Self.draw(key), "the chart is not drawn")
        #expect(drawn.xLabels.map(\.text) == ["5", "10", "15"])
        Self.check(key, drawn)
    }

    // MARK: The layout rule alone

    @Test("labels that lie inside the frame are centred under their ticks, exactly")
    func untouched() {
        let lefts = ExtendedMarkdown.Core.Chart.TickLabelLayout.lefts(centers: [100, 150, 200], widths: [10, 20, 30], bounds: 50 ... 250)
        #expect(lefts == [95, 140, 185])
    }

    @Test("a label that passes an end of the frame is moved to that end")
    func moved() {
        let lefts = ExtendedMarkdown.Core.Chart.TickLabelLayout.lefts(centers: [52, 150, 248], widths: [10, 20, 30], bounds: 50 ... 250)
        #expect(lefts == [50, 140, 220])
    }

    @Test("a label within 4 points of a moved label is not drawn, one further away is")
    func thinned() {
        let close = ExtendedMarkdown.Core.Chart.TickLabelLayout.lefts(centers: [100, 200, 245], widths: [20, 34, 30], bounds: 50 ... 250)
        #expect(close == [90, nil, 220], "the label from 183 to 217 ends 3 points before the moved label at 220")
        let clear = ExtendedMarkdown.Core.Chart.TickLabelLayout.lefts(centers: [100, 200, 245], widths: [20, 30, 30], bounds: 50 ... 250)
        #expect(clear == [90, 185, 220], "the label from 185 to 215 ends 5 points before the moved label at 220")
        let touching = ExtendedMarkdown.Core.Chart.TickLabelLayout.lefts(centers: [100, 205, 245], widths: [20, 30, 30], bounds: 50 ... 250)
        #expect(touching == [90, nil, 220])
    }

    @Test("two moved labels that meet: the first stays; a label wider than the frame is not drawn; no ticks, no labels")
    func edges() {
        #expect(ExtendedMarkdown.Core.Chart.TickLabelLayout.lefts(centers: [55, 140], widths: [40, 60], bounds: 50 ... 150) == [50, nil])
        #expect(ExtendedMarkdown.Core.Chart.TickLabelLayout.lefts(centers: [75], widths: [60], bounds: 50 ... 100) == [nil])
        #expect(ExtendedMarkdown.Core.Chart.TickLabelLayout.lefts(centers: [], widths: [], bounds: 50 ... 100) == [])
    }

    @Test("only the ticks inside the domain belong to the axis, the ends included")
    func ticksInsideDomain() {
        #expect(ExtendedMarkdown.Core.Chart.TickLabelLayout.ticks([0, 5, 10, 15, 20], inside: (1, 16)) == [5, 10, 15])
        #expect(ExtendedMarkdown.Core.Chart.TickLabelLayout.ticks([0, 5, 10], inside: (0, 10)) == [0, 5, 10])
        #expect(ExtendedMarkdown.Core.Chart.TickLabelLayout.ticks([0.1 + 0.2], inside: (0, 0.3)) == [0.1 + 0.2], "a tick a rounding past the end is on it")
        #expect(ExtendedMarkdown.Core.Chart.TickLabelLayout.ticks([], inside: (0, 1)).isEmpty)
    }

    // MARK: The sweep against the answer key

    /// The value ranges of the enumerated sweep: the range of the showcase chart, the ranges that make the widest
    /// labels, negative ranges, decimals, a single value, and y values whose labels are wider than the axis column.
    private static let ranges: [(x: (Double, Double), y: (Double, Double))] = [
        ((1, 16), (12, 118)),
        ((0, 20), (0, 20)),
        ((0, 1000), (0, 1000)),
        ((0, 1_000_000), (0, 1_000_000)),
        ((-1_000_000, 1_000_000), (-1_000_000, 1_000_000)),
        ((-50, -10), (-1000, 0)),
        ((-7, 93), (-0.75, 0.5)),
        ((0.25, 0.75), (3, 9.5)),
        ((0, 9.5), (0, 1_000_000_000_000_000)),
        ((3, 97), (-900_000_000_000_000, 100)),
        ((5, 5), (7, 7)),
        ((1, 1_000_000_000), (1, 2)),
    ]

    private static var enumerated: [ChartTickLabelKey] {
        var keys: [ChartTickLabelKey] = []
        for pageWidth in [200.0, 300, 612, 842] {
            for margin in [0.0, 3, 10, 36, 54] {
                for kind in ChartTickLabelKey.Kind.allCases {
                    for range in ranges {
                        let middle = (x: (range.x.0 + range.x.1) / 2, y: (range.y.0 + range.y.1) / 2)
                        let points = range.x.0 == range.x.1
                            ? [(range.x.0, range.y.0)]
                            : [(range.x.0, range.y.0), (middle.x, range.y.1), (range.x.1, middle.y)]
                        keys.append(ChartTickLabelKey(kind: kind, points: points, pageWidth: pageWidth, margin: margin))
                    }
                }
            }
        }
        return keys
    }

    /// 500 charts from a fixed seed: the kind, the page width from 200 to 900 points, the margin from 0 to 60, and two
    /// to six points whose magnitudes run from 1 to ten million on x and to a thousand million million on y.
    private static var seeded: [ChartTickLabelKey] {
        var random = SplitMix(state: 0x6469_6167_7261_6D73)
        return (0 ..< 500).map { _ in
            let kind: ChartTickLabelKey.Kind = random.next() % 2 == 0 ? .line : .scatter
            let pageWidth = Double(200 + random.next() % 701)
            let margin = Double(random.next() % 61)
            let xScale = pow(10, Double(random.next() % 8))
            let yScale = pow(10, Double(random.next() % 16))
            let count = 2 + Int(random.next() % 5)
            var points: [(x: Double, y: Double)] = []
            for index in 0 ..< count {
                let x = (Double(random.next() % 2001) - 1000) / 1000 * xScale
                let y = (Double(random.next() % 2001) - 1000) / 1000 * yScale
                // The source carries two decimals, and a line chart's x values must rise.
                let roundedX = (x * 100).rounded() / 100
                points.append((kind == .line ? roundedX.magnitude + Double(index) * xScale : roundedX, (y * 100).rounded() / 100))
            }
            return ChartTickLabelKey(kind: kind, points: points, pageWidth: pageWidth, margin: margin)
        }
    }

    private struct SplitMix {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    /// What a sweep covered, so that a sweep that checks nothing cannot pass.
    private struct Coverage: CustomStringConvertible {
        var charts = 0
        var drawn = 0
        var moved = 0
        var thinned = 0
        var widened = 0
        var compared = 0

        var description: String {
            "\(charts) charts, \(drawn) drawn, \(compared) compared label by label, \(moved) with a moved label, "
                + "\(thinned) with a label not drawn, \(widened) with a widened axis column"
        }
    }

    private static func sweep(_ keys: [ChartTickLabelKey]) throws -> Coverage {
        var coverage = Coverage(charts: keys.count)
        for key in keys {
            guard let drawn = try draw(key) else {
                continue
            }
            coverage.drawn += 1
            coverage.moved += key.movedCount > 0 ? 1 : 0
            coverage.thinned += key.thinnedCount > 0 ? 1 : 0
            coverage.widened += key.widensAxisColumn ? 1 : 0
            coverage.compared += key.labelsAreExact ? 1 : 0
            check(key, drawn)
        }
        return coverage
    }

    @Test("the enumerated page widths, margins and value ranges agree with the answer key")
    func enumeratedSweep() throws {
        let coverage = try Self.sweep(Self.enumerated)
        print("ChartTickLabelTests enumerated sweep: \(coverage)")
        #expect(coverage.charts == 480)
        // Measured on 2026-11-24, printed by the line above: 480 charts, 415 drawn, 415 compared label by label, 59 with a
        // moved label, 14 with a label not drawn, 68 with a widened axis column. The other 65 are reported by the renderer
        // as not drawable (a plot too small, scatter labels that would overlap) and print their source. The sweep is
        // fixed, so the floors are the measured numbers: a change that draws fewer charts, or that stops moving, thinning
        // or widening, fails here even if no label is wrong.
        #expect(coverage.drawn >= 415, Comment(rawValue: "\(coverage)"))
        #expect(coverage.compared >= 415, Comment(rawValue: "\(coverage)"))
        #expect(coverage.moved >= 59, Comment(rawValue: "\(coverage)"))
        #expect(coverage.thinned >= 14, Comment(rawValue: "\(coverage)"))
        #expect(coverage.widened >= 68, Comment(rawValue: "\(coverage)"))
    }

    @Test("500 seeded charts agree with the answer key")
    func seededSweep() throws {
        let coverage = try Self.sweep(Self.seeded)
        print("ChartTickLabelTests seeded sweep: \(coverage)")
        #expect(coverage.charts == 500)
        // Measured on 2026-11-24, printed by the line above: 500 charts, 460 drawn, 459 compared label by label, 24 with a
        // moved label, 0 with a label not drawn, 44 with a widened axis column. The seed is fixed, so the floors are the
        // measured numbers. No seeded chart thins a label: the enumerated sweep holds that case.
        #expect(coverage.drawn >= 460, Comment(rawValue: "\(coverage)"))
        #expect(coverage.compared >= 459, Comment(rawValue: "\(coverage)"))
        #expect(coverage.moved >= 24, Comment(rawValue: "\(coverage)"))
        #expect(coverage.widened >= 44, Comment(rawValue: "\(coverage)"))
    }
}
