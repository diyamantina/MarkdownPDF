import ExtendedMarkdownCore
import Foundation

extension ExtendedMarkdown.Core.Chart {
    /// Where the tick labels of a chart's numeric x axis lie.
    ///
    /// Three rules, each a closed form, so a test can state the numbers without the drawing code.
    ///
    /// 1. A tick belongs to the axis only when its value lies inside the axis domain. A tick outside the domain maps to a
    ///    point outside the plot, and its label can leave the chart and the page.
    /// 2. A label is centred under its tick, and when its box would then pass an end of the chart's frame it is moved
    ///    inward until the box ends at the frame. A label wider than the whole frame is not drawn.
    /// 3. A label that rule 2 moved keeps its place. A label that comes closer than `gap` to a moved label that is drawn is
    ///    not drawn: its tick and gridline stay, the axis is thinned by that one label. Two labels that rule 2 did not
    ///    move are never compared here, so an axis whose labels all lay inside the frame is placed exactly as before.
    enum TickLabelLayout {
        /// The least clear space between a moved label and its neighbour, in points. The same number the scatter chart's
        /// overlap rule uses.
        static let gap = 4.0

        /// The ticks whose value lies inside `domain`, in order. The ends count as inside, and a tick that misses an end
        /// by the rounding of the step sum (a billionth of the span) counts as on it.
        static func ticks(_ ticks: [Double], inside domain: (min: Double, max: Double)) -> [Double] {
            let slack = abs(domain.max - domain.min) * 1e-9
            return ticks.filter { $0 >= domain.min - slack && $0 <= domain.max + slack }
        }

        /// The left edge of each label, or `nil` for a label that is not drawn.
        ///
        /// - Parameters:
        ///   - centers: the x of each tick, in order.
        ///   - widths: the width of each label, one per tick.
        ///   - bounds: the left and right end of the chart's frame, cut to the page.
        static func lefts(centers: [Double], widths: [Double], bounds: ClosedRange<Double>) -> [Double?] {
            let count = min(centers.count, widths.count)
            var lefts = [Double?](repeating: nil, count: count)
            var moved = [Bool](repeating: false, count: count)
            for index in 0 ..< count where widths[index] <= bounds.upperBound - bounds.lowerBound {
                let natural = centers[index] - widths[index] / 2
                let placed = min(max(natural, bounds.lowerBound), bounds.upperBound - widths[index])
                lefts[index] = placed
                moved[index] = placed != natural
            }

            var kept: [Int] = []
            for index in 0 ..< count where moved[index] {
                if touchesAny(index, of: kept, lefts: lefts, widths: widths) {
                    lefts[index] = nil
                } else {
                    kept.append(index)
                }
            }
            for index in 0 ..< count where !moved[index] && lefts[index] != nil {
                if touchesAny(index, of: kept, lefts: lefts, widths: widths) {
                    lefts[index] = nil
                }
            }
            return lefts
        }

        /// Whether the label at `index` comes closer than `gap` to one of the labels in `kept`.
        private static func touchesAny(_ index: Int, of kept: [Int], lefts: [Double?], widths: [Double]) -> Bool {
            guard let left = lefts[index] else {
                return false
            }
            return kept.contains { other in
                guard let otherLeft = lefts[other] else {
                    return false
                }
                return left < otherLeft + widths[other] + gap && otherLeft < left + widths[index] + gap
            }
        }
    }
}
