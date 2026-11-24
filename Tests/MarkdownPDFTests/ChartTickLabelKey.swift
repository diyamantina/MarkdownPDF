import Foundation

/// The answer key for the tick labels of a line or scatter chart with a numeric x axis: from the chart's data, the page
/// width and the margin it says which labels are drawn and where each one lies. It is written apart from the renderer
/// and calls none of its layout code, so the two can only agree by being right.
///
/// The rules it states, in plain words:
///
/// - The step of an axis is 0.2, 0.5, 1 or 2 times a power of ten, by the span rounded up to 1, 2, 5 or 10 times a
///   power of ten. The y axis and a scatter chart's x axis run from the multiple of the step below the least value to
///   the multiple above the greatest. A line chart's x axis runs from the least x to the greatest x, and only the
///   multiples of the step between them are ticks.
/// - A label is set in Helvetica at 0.72 of the base size. A y label ends 6 points left of the plot. An x label is
///   centred under its tick.
/// - The chart's frame runs from 4 points left of the left margin to 4 points right of the right margin, cut to the
///   page. No label leaves it: the y axis column is widened for a label wider than the column, an x label that would
///   leave the frame is moved inward to its end, and a label that then comes within 4 points of a moved label is not
///   drawn.
struct ChartTickLabelKey {
    enum Kind: String, CaseIterable {
        case line
        case scatter
    }

    struct Label: Equatable, CustomStringConvertible {
        var text: String
        var left: Double
        var width: Double

        var right: Double {
            left + width
        }

        var description: String {
            "'\(text)' \(left)...\(right)"
        }
    }

    var kind: Kind
    var points: [(x: Double, y: Double)]
    var pageWidth: Double
    var margin: Double

    /// The label size at the default base font size of 11 points.
    static let labelSize = 11 * 0.72

    /// The chart source for these data.
    var markdown: String {
        let body = switch kind {
        case .line:
            "x: \(points.map { Self.source($0.x) }.joined(separator: ", "))\n"
                + "series: s = \(points.map { Self.source($0.y) }.joined(separator: ", "))"
        case .scatter:
            "points: s = \(points.map { "(\(Self.source($0.x)), \(Self.source($0.y)))" }.joined(separator: ", "))"
        }
        return "```chart\ntype: \(kind.rawValue)\n\(body)\n```\n"
    }

    /// The left and right end of the chart's frame, cut to the page.
    var frame: ClosedRange<Double> {
        Self.frame(pageWidth: pageWidth, marginLeft: margin, marginRight: margin)
    }

    static func frame(pageWidth: Double, marginLeft: Double, marginRight: Double) -> ClosedRange<Double> {
        max(0, marginLeft - 4) ... min(pageWidth, pageWidth - marginRight + 4)
    }

    /// The labels of the y axis, from the lowest tick up.
    var yLabels: [Label] {
        let plot = plot
        return yTicks.map { tick in
            let text = Self.text(tick)
            let width = Self.width(text)
            return Label(text: text, left: plot.left - 6 - width, width: width)
        }
    }

    /// The labels of the x axis that are drawn, from left to right of their ticks.
    var xLabels: [Label] {
        placedXLabels.compactMap(\.label)
    }

    /// How many x labels were moved inward to stay in the frame.
    var movedCount: Int {
        placedXLabels.count(where: { $0.moved && $0.label != nil })
    }

    /// How many x labels are not drawn because a moved label took their place.
    var thinnedCount: Int {
        placedXLabels.count(where: { $0.label == nil })
    }

    /// Whether the y axis column had to be widened past its usual 68 points to keep a label in the frame.
    var widensAxisColumn: Bool {
        axisColumn > 68
    }

    /// Whether every tick is a whole number of hundredths, so that its label of two decimals says it exactly. A tick
    /// such as 0.085 lies on the tie between two labels, where the last bit of the sum decides the text: the key does
    /// not say which, and such a chart is outside what it answers.
    var labelsAreExact: Bool {
        (yTicks + xAxis.ticks).allSatisfy { abs(($0 * 100).rounded() - $0 * 100) < 1e-6 }
    }

    // MARK: The axes

    private var yTicks: [Double] {
        let range = Self.spread(points.map(\.y))
        return Self.outwardTicks(range)
    }

    private var xAxis: (ticks: [Double], low: Double, high: Double) {
        let range = Self.spread(points.map(\.x))
        switch kind {
        case .line:
            let step = Self.step(range)
            let first = Int((range.low / step - 1e-9).rounded(.up))
            let last = Int((range.high / step + 1e-9).rounded(.down))
            let ticks = first <= last ? (first ... last).map { Double($0) * step } : []
            return (ticks, range.low, range.high)
        case .scatter:
            let ticks = Self.outwardTicks(range)
            return (ticks, ticks.first ?? range.low, ticks.last ?? range.high)
        }
    }

    private var axisColumn: Double {
        let widest = yTicks.map { Self.width(Self.text($0)) }.max() ?? 0
        let usual = min(max(38, max(34, widest) + 10), 68)
        let needed = widest + 6 + frame.lowerBound - margin
        return max(usual, needed)
    }

    private var plot: (left: Double, width: Double) {
        (margin + axisColumn, pageWidth - 2 * margin - axisColumn - 12)
    }

    private var placedXLabels: [(label: Label?, moved: Bool)] {
        let axis = xAxis
        let plot = plot
        var placed: [(label: Label?, moved: Bool)] = axis.ticks.map { tick in
            let text = Self.text(tick)
            let width = Self.width(text)
            let center = plot.left + (tick - axis.low) / (axis.high - axis.low) * plot.width
            var left = center - width / 2
            var moved = false
            if left < frame.lowerBound {
                left = frame.lowerBound
                moved = true
            }
            if left + width > frame.upperBound {
                left = frame.upperBound - width
                moved = true
            }
            return (width <= frame.upperBound - frame.lowerBound ? Label(text: text, left: left, width: width) : nil, moved)
        }
        // A moved label keeps its place unless an earlier moved label already holds it.
        for index in placed.indices where placed[index].moved {
            for earlier in 0 ..< index where placed[earlier].moved && Self.tooClose(placed[earlier].label, placed[index].label) {
                placed[index].label = nil
            }
        }
        // A label that was not moved gives way to a moved one.
        for index in placed.indices where !placed[index].moved {
            for other in placed.indices where placed[other].moved && Self.tooClose(placed[other].label, placed[index].label) {
                placed[index].label = nil
            }
        }
        return placed
    }

    private static func tooClose(_ one: Label?, _ other: Label?) -> Bool {
        guard let one, let other else {
            return false
        }
        return one.left < other.right + 4 && other.left < one.right + 4
    }

    // MARK: Numbers

    /// The least and greatest value; a single value is spread by a tenth of itself, one at least, to both sides.
    private static func spread(_ values: [Double]) -> (low: Double, high: Double) {
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        if high > low {
            return (low, high)
        }
        let padding = max(1, abs(low) / 10)
        return (low - padding, high + padding)
    }

    /// The step for a range: the span rounded up to 1, 2, 5 or 10 times a power of ten gives 0.2, 0.5, 1 or 2 times it.
    private static func step(_ range: (low: Double, high: Double)) -> Double {
        let span = range.high - range.low
        let power = pow(10, floor(log10(span)))
        let mantissa = span / power
        if mantissa <= 1 {
            return 0.2 * power
        }
        if mantissa <= 2 {
            return 0.5 * power
        }
        if mantissa <= 5 {
            return power
        }
        return 2 * power
    }

    private static func outwardTicks(_ range: (low: Double, high: Double)) -> [Double] {
        let step = step(range)
        let first = Int((range.low / step).rounded(.down))
        let last = Int((range.high / step).rounded(.up))
        return (first ... last).map { Double($0) * step }
    }

    /// A tick as its label: a whole number without a fraction, a number of 10 or more with one decimal, a smaller one
    /// with two.
    static func text(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }
        return String(format: abs(value) >= 10 ? "%.1f" : "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// The width of a label in Helvetica at the label size, from the advance widths of the Adobe font metrics: a digit
    /// is 556 thousandths of the size, the hyphen 333, the full stop 278.
    static func width(_ text: String) -> Double {
        text.reduce(0) { sum, character in
            let advance: Double = switch character {
            case "-":
                333
            case ".":
                278
            default:
                556
            }
            return sum + advance / 1000 * labelSize
        }
    }

    /// A value as the chart source writes it.
    private static func source(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 9e15
            ? String(Int(value))
            : String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
