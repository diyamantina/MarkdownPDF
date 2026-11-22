import Foundation

extension ChartBlock {
    /// The closed form of a doughnut chart: a pie with a hole.
    ///
    /// The slices run clockwise from twelve o'clock, as the pie chart draws them. Slice `i` of values `v` with total `T`
    /// sweeps `2 * pi * v[i] / T` radians, so the sweeps add up to one full turn. The hole is a circle at the centre of
    /// the outer circle with radius `holeFraction * outerRadius`; a ring slice is the area between the two circles
    /// inside its sweep. Nothing here depends on the drawing code, so a test can state the numbers without it.
    enum DoughnutGeometry {
        /// The hole radius as a fraction of the outer radius. Named, so a test and the drawing say the same number.
        static let holeFraction = 0.55

        /// The angles of one slice in radians, counter-clockwise from the positive x axis (the PDF convention). The
        /// sweep is negative: the slices go clockwise.
        struct Arc: Equatable {
            var start: Double
            var end: Double

            var sweep: Double {
                end - start
            }
        }

        /// The start of the first slice: twelve o'clock.
        static let firstAngle = Double.pi / 2

        /// The arcs of the slices for `values`, in order. An empty list or a total that is not positive has no arcs.
        static func arcs(for values: [Double]) -> [Arc] {
            let total = values.reduce(0, +)
            guard total > 0, total.isFinite else {
                return []
            }
            var angle = firstAngle
            return values.map { value in
                let next = angle - Double.pi * 2 * value / total
                defer { angle = next }
                return Arc(start: angle, end: next)
            }
        }

        /// The hole radius for an outer radius.
        static func holeRadius(outer: Double) -> Double {
            holeFraction * outer
        }

        /// The area of one ring slice: `sweep / 2 * (outer^2 - hole^2)`. The oracle for the drawn path's area.
        static func ringArea(sweep: Double, outer: Double) -> Double {
            let hole = holeRadius(outer: outer)
            return abs(sweep) / 2 * (outer * outer - hole * hole)
        }
    }
}
