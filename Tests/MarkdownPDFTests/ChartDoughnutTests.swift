import Foundation
@testable import MarkdownPDF
import Testing

/// The doughnut chart type: a pie with a hole. The oracle is the closed form in `ChartBlock.DoughnutGeometry` (the sweep of a slice
/// is `2 * pi * value / total`, the hole radius is the named fraction of the outer radius); the drawing is read back from the bytes of
/// the page and has to agree with it.
@Suite("Doughnut chart")
struct ChartDoughnutTests {
    /// A tolerance derived, not guessed: the sweeps are sums of at most eight double-precision products of magnitude at most `2 * pi`,
    /// each carrying a relative error of at most `2^-53`, so the total error stays below `8 * 2 * pi * 2^-53`, under `1e-14`.
    /// The drawn coordinates are printed with at most two decimals, so a read-back distance is exact only to `0.01` per coordinate.
    private static let angleTolerance = 1e-14
    private static let printedTolerance = 0.02

    private static let fence = """
    ```chart
    type: doughnut
    title: Share
    slice: North = 25
    slice: East = 25
    slice: South = 25
    slice: West = 25
    ```
    """

    // MARK: The closed form

    @Test("the sweeps are 2 pi times the share, clockwise from twelve o'clock, and add up to one turn")
    func sweepsAreTheShares() {
        let arcs = ChartBlock.DoughnutGeometry.arcs(for: [62, 31, 7])
        #expect(arcs.count == 3)
        #expect(arcs[0].start == Double.pi / 2)
        let expected = [62.0, 31.0, 7.0].map { -Double.pi * 2 * $0 / 100 }
        for (arc, sweep) in zip(arcs, expected) {
            #expect(abs(arc.sweep - sweep) <= Self.angleTolerance, "sweep \(arc.sweep) is not \(sweep)")
        }
        #expect(abs(arcs.reduce(0) { $0 + $1.sweep } + Double.pi * 2) <= Self.angleTolerance)
        for (previous, next) in zip(arcs, arcs.dropFirst()) {
            #expect(previous.end == next.start, "slices must touch with no gap and no overlap")
        }
    }

    @Test("a total that is not positive has no arcs")
    func noArcsWithoutATotal() {
        #expect(ChartBlock.DoughnutGeometry.arcs(for: []).isEmpty)
        #expect(ChartBlock.DoughnutGeometry.arcs(for: [0, 0]).isEmpty)
        #expect(ChartBlock.DoughnutGeometry.arcs(for: [Double.infinity, 1]).isEmpty)
    }

    @Test("the hole is the named fraction of the outer radius and the ring area is the difference of two sectors")
    func holeAndArea() {
        #expect(ChartBlock.DoughnutGeometry.holeRadius(outer: 100) == 100 * ChartBlock.DoughnutGeometry.holeFraction)
        // A whole turn of radius 10 with a hole of radius 5.5 is pi * (100 - 30.25).
        let whole = ChartBlock.DoughnutGeometry.ringArea(sweep: -Double.pi * 2, outer: 10)
        #expect(abs(whole - Double.pi * (100 - 30.25)) <= 1e-12)
        // The areas of the slices add up to the area of the whole ring.
        let parts = ChartBlock.DoughnutGeometry.arcs(for: [1, 2, 3, 4]).map { ChartBlock.DoughnutGeometry.ringArea(sweep: $0.sweep, outer: 10) }
        #expect(abs(parts.reduce(0, +) - whole) <= 1e-12)
    }

    // MARK: The parse

    @Test("both spellings parse to a doughnut with the same slices as a pie")
    func parses() {
        for word in ["doughnut", "donut"] {
            let source = "type: \(word)\nslice: A = 3\nslice: B = 1"
            guard case let .chart(chart) = ChartBlock.parseChartFence(source) else {
                Issue.record("`\(word)` should parse")
                continue
            }
            #expect(chart.kind == .doughnut)
            #expect(chart.series.first?.points.map(\.y) == [3, 1])
            #expect(chart.categories == ["A", "B"])
        }
    }

    @Test("a doughnut with no positive total or too many slices is reported by name, not drawn")
    func refusals() {
        let zero = ChartBlock.parseChartFence("type: doughnut\nslice: A = 0\nslice: B = 0")
        #expect(zero == .unsupported("pie chart total must be greater than zero"))
        let nine = (1 ... 9).map { "slice: S\($0) = 1" }.joined(separator: "\n")
        #expect(ChartBlock.parseChartFence("type: doughnut\n\(nine)") == .unsupported("too many pie slices for the portable chart profile"))
    }

    // MARK: The drawing, read back from the page

    /// Every path point of the page's content streams: the points of `m` and `l` operators and the end point of each `c`.
    private func pathPoints(_ markdown: String) throws -> [(x: Double, y: Double)] {
        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        var points: [(x: Double, y: Double)] = []
        for stream in PDFInspector(data).streams {
            // One appended group of operators is one line, so the operands are read token by token.
            var operands: [Double] = []
            for token in stream.body.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
                if let number = Double(token) {
                    operands.append(number)
                    continue
                }
                switch token {
                case "m", "l":
                    if operands.count >= 2 {
                        points.append((operands[operands.count - 2], operands[operands.count - 1]))
                    }
                case "c":
                    if operands.count >= 6 {
                        points.append((operands[operands.count - 2], operands[operands.count - 1]))
                    }
                default:
                    break
                }
                operands.removeAll()
            }
        }
        return points
    }

    @Test("every drawn point lies on the outer circle or on the hole circle, and the hole is the named fraction")
    func drawnPointsLieOnTwoCircles() throws {
        let points = try pathPoints(Self.fence)
        #expect(!points.isEmpty, "the doughnut drew no path")
        // Four equal slices end at twelve, three, six and nine o'clock: the extremes of the outer circle.
        let minX = try #require(points.map(\.x).min())
        let maxX = try #require(points.map(\.x).max())
        let minY = try #require(points.map(\.y).min())
        let maxY = try #require(points.map(\.y).max())
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let outer = (maxX - minX) / 2
        #expect(abs((maxY - minY) / 2 - outer) <= Self.printedTolerance, "the outer shape is not a circle")
        let hole = ChartBlock.DoughnutGeometry.holeRadius(outer: outer)

        var onOuter = 0
        var onHole = 0
        for point in points {
            let distance = ((point.x - centerX) * (point.x - centerX) + (point.y - centerY) * (point.y - centerY)).squareRoot()
            if abs(distance - outer) <= Self.printedTolerance {
                onOuter += 1
            } else if abs(distance - hole) <= Self.printedTolerance {
                onHole += 1
            } else {
                Issue.record("point (\(point.x), \(point.y)) is \(distance) from the centre, neither \(outer) nor \(hole)")
            }
        }
        #expect(onOuter > 0 && onHole > 0, "outer \(onOuter), hole \(onHole): the ring has both edges")
        // No path goes to the centre: that is a pie, which has no hole.
        #expect(!points.contains { abs($0.x - centerX) <= Self.printedTolerance && abs($0.y - centerY) <= Self.printedTolerance })
    }

    @Test("the slice boundaries of unequal slices are drawn at the angles of the closed form")
    func boundariesFollowTheShares() throws {
        // The same title and labels as the four-slice chart, so the legend, the radius and the centre are the same.
        let values = [50.0, 25, 15, 10]
        let markdown = "```chart\ntype: doughnut\ntitle: Share\nslice: North = 50\nslice: East = 25\nslice: South = 15\nslice: West = 10\n```"
        let points = try pathPoints(markdown)
        // The outer circle's centre and radius come from the four-slice chart.
        let reference = try pathPoints(Self.fence)
        let centerX = try (#require(reference.map(\.x).min()) + #require(reference.map(\.x).max())) / 2
        let centerY = try (#require(reference.map(\.y).min()) + #require(reference.map(\.y).max())) / 2
        let outer = try (#require(reference.map(\.x).max()) - #require(reference.map(\.x).min())) / 2
        let arcs = ChartBlock.DoughnutGeometry.arcs(for: values)
        // Each slice's path starts at its outer start point: the first three outer points that are the start of a slice.
        for arc in arcs {
            let wantedX = centerX + cos(arc.start) * outer
            let wantedY = centerY + sin(arc.start) * outer
            #expect(
                points.contains { abs($0.x - wantedX) <= Self.printedTolerance && abs($0.y - wantedY) <= Self.printedTolerance },
                "no drawn point at the start of the slice at angle \(arc.start)",
            )
        }
    }

    @Test("the doughnut is drawn as a chart with its legend, not as source text, and a pie of the same data is a different drawing")
    func drawsWithLegend() throws {
        let data = try MarkdownPDFRenderer().render(markdown: Self.fence)
        let inspector = PDFInspector(data)
        #expect(!inspector.text.contains("Unsupported chart"))
        #expect(!inspector.text.contains("type: doughnut"))
        for label in ["North 25", "East 25", "South 25", "West 25", "Share"] {
            #expect(inspector.text.contains(label), "missing `\(label)`")
        }
        #expect(inspector.hasValidXrefOffsets())
        let pie = try MarkdownPDFRenderer().render(markdown: Self.fence.replacingOccurrences(of: "doughnut", with: "pie"))
        #expect(pie != data)
    }

    @Test("a single slice is a whole ring, not a filled disc")
    func singleSliceIsARing() throws {
        let points = try pathPoints("```chart\ntype: doughnut\nslice: Only = 5\n```")
        let minX = try #require(points.map(\.x).min())
        let maxX = try #require(points.map(\.x).max())
        let centerX = (minX + maxX) / 2
        let outer = (maxX - minX) / 2
        let inside = points.filter { abs($0.x - centerX) < outer * 0.99 }
        #expect(!inside.isEmpty, "a whole turn must still show the hole edge")
    }
}
