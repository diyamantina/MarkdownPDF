import Foundation

/// How a flowchart link is drawn between its two end points: straight, or, when the straight line would run through other nodes, as an arc around them.
///
/// The arc is a cubic Bezier from the start `s` to the end `e` whose control points lie a third and two thirds of the way along the line, `n d` to one
/// side of it (`n` the unit normal): the arc is then at position `t L` along the line, `3 d t (1 - t)` to its side (`3 d / 4` at the middle, where the
/// label sits). A corner of an obstacle at parameter `t` and `r` past the line needs `3 d t (1 - t) >= r + margin`, which also clears the obstacle between
/// its corners (the arc's offset is concave, the obstacle's outline linear between corners); `d` is the largest such value over the corners of the
/// obstacles in the way. The side that needs the smaller `d` and keeps the whole arc inside the bounds, and clear of the obstacles when sampled, is
/// taken, the upper one on a tie. When neither side works the link stays straight.
struct MermaidEdgeRoute: Equatable {
    struct Point: Equatable {
        var x: Double
        var y: Double
    }

    /// A rectangle with `y` pointing up: `bottom <= top`.
    struct Rectangle: Equatable {
        var left: Double
        var bottom: Double
        var right: Double
        var top: Double

        var corners: [Point] {
            [Point(x: left, y: bottom), Point(x: right, y: bottom), Point(x: right, y: top), Point(x: left, y: top)]
        }

        func contains(_ point: Point) -> Bool {
            point.x >= left && point.x <= right && point.y >= bottom && point.y <= top
        }

        /// Whether the two rectangles share area; rectangles that only touch do not overlap.
        func overlaps(_ other: Rectangle) -> Bool {
            left < other.right && right > other.left && bottom < other.top && top > other.bottom
        }

        /// Whether the segment from `start` to `end` meets the rectangle (Liang-Barsky clipping of the segment against its four sides).
        func isCrossed(from start: Point, to end: Point) -> Bool {
            var entering = 0.0
            var leaving = 1.0
            let dx = end.x - start.x
            let dy = end.y - start.y
            for (direction, distance) in [(-dx, start.x - left), (dx, right - start.x), (-dy, start.y - bottom), (dy, top - start.y)] {
                if direction == 0 {
                    if distance < 0 {
                        return false
                    }
                } else {
                    let ratio = distance / direction
                    if direction < 0 {
                        entering = max(entering, ratio)
                    } else {
                        leaving = min(leaving, ratio)
                    }
                    if entering > leaving {
                        return false
                    }
                }
            }
            return true
        }
    }

    enum Path: Equatable {
        case straight
        case arc(control1: Point, control2: Point)
    }

    var path: Path
    /// Where the label of the link is centred: the middle of the line, or the apex of the arc.
    var labelPoint: Point

    /// The clear space between an arc and the nodes it passes, in points.
    static let margin = 6.0

    /// The size of a label that sits on the link, centred on the middle of the line or on the apex of the arc.
    struct LabelSize: Equatable {
        var width: Double
        var height: Double
    }

    /// The route of the link from `start` to `end`. `obstacles` are the nodes the line must not cross (not the two it joins). A `label` is kept
    /// off every rectangle of `labelObstacles` (the nodes, the two it joins too): when it would overlap one at the middle of the straight line,
    /// the link bends into an arc whose apex, in steps of two points of the control offset, is the first that lifts the label clear.
    static func route(
        from start: Point,
        to end: Point,
        avoiding obstacles: [Rectangle],
        within bounds: Rectangle,
        label: LabelSize? = nil,
        labelObstacles: [Rectangle] = [],
    ) -> MermaidEdgeRoute {
        let middle = Point(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let straight = MermaidEdgeRoute(path: .straight, labelPoint: middle)
        let length = hypot(end.x - start.x, end.y - start.y)
        let blocking = obstacles.filter { $0.isCrossed(from: start, to: end) }
        let labelBlockers = obstacles + labelObstacles
        func labelCollides(at center: Point) -> Bool {
            guard let label else {
                return false
            }
            let frame = Rectangle(
                left: center.x - label.width / 2,
                bottom: center.y - label.height / 2,
                right: center.x + label.width / 2,
                top: center.y + label.height / 2,
            )
            return labelBlockers.contains { frame.overlaps($0) }
        }
        guard length > 0, !blocking.isEmpty || labelCollides(at: middle) else {
            return straight
        }

        let along = Point(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        let normals = [Point(x: -along.y, y: along.x), Point(x: along.y, y: -along.x)].sorted { $0.y > $1.y }
        var best: (offset: Double, normal: Point)?
        for normal in normals {
            var offset = 0.0
            if !blocking.isEmpty {
                guard let needed = self.offset(from: start, along: along, length: length, normal: normal, blocking: blocking) else {
                    continue
                }
                offset = needed
            }
            func apex(_ offset: Double) -> Point {
                Point(x: middle.x + normal.x * 0.75 * offset, y: middle.y + normal.y * 0.75 * offset)
            }
            while labelCollides(at: apex(offset)), offset < 800 {
                offset += 2
            }
            guard !labelCollides(at: apex(offset)), offset > 0 else {
                continue
            }
            let controls = controlPoints(from: start, to: end, normal: normal, offset: offset)
            guard arcFits(from: start, to: end, controls: controls, avoiding: obstacles, within: bounds) else {
                continue
            }
            if best == nil || offset < best?.offset ?? 0 {
                best = (offset, normal)
            }
        }
        guard let chosen = best else {
            return straight
        }
        let controls = controlPoints(from: start, to: end, normal: chosen.normal, offset: chosen.offset)
        return MermaidEdgeRoute(
            path: .arc(control1: controls.first, control2: controls.second),
            labelPoint: Point(
                x: middle.x + chosen.normal.x * 0.75 * chosen.offset,
                y: middle.y + chosen.normal.y * 0.75 * chosen.offset,
            ),
        )
    }

    private static func controlPoints(from start: Point, to end: Point, normal: Point, offset: Double) -> (first: Point, second: Point) {
        (
            Point(x: start.x + (end.x - start.x) / 3 + normal.x * offset, y: start.y + (end.y - start.y) / 3 + normal.y * offset),
            Point(x: start.x + (end.x - start.x) * 2 / 3 + normal.x * offset, y: start.y + (end.y - start.y) * 2 / 3 + normal.y * offset),
        )
    }

    /// The control offset `d` that clears every corner of the obstacles on the side of `normal`, or nil when a corner sits so close to an end
    /// (parameter 0 or 1) that no arc clears it.
    private static func offset(from start: Point, along: Point, length: Double, normal: Point, blocking: [Rectangle]) -> Double? {
        var offset = 0.0
        for obstacle in blocking {
            for corner in obstacle.corners {
                let relative = Point(x: corner.x - start.x, y: corner.y - start.y)
                let reach = relative.x * normal.x + relative.y * normal.y
                let parameter = (relative.x * along.x + relative.y * along.y) / length
                // A corner more than the margin on the other side of the line needs nothing; one within the margin of it still needs a little.
                guard reach > -margin, parameter > 0, parameter < 1 else {
                    continue
                }
                offset = max(offset, (reach + margin) / (3 * parameter * (1 - parameter)))
            }
        }
        return offset > 0 ? offset : nil
    }

    private static func arcFits(
        from start: Point,
        to end: Point,
        controls: (first: Point, second: Point),
        avoiding obstacles: [Rectangle],
        within bounds: Rectangle,
    ) -> Bool {
        for step in 0 ... 256 {
            let t = Double(step) / 256
            let u = 1 - t
            let x = u * u * u * start.x + 3 * u * u * t * controls.first.x + 3 * u * t * t * controls.second.x + t * t * t * end.x
            let y = u * u * u * start.y + 3 * u * u * t * controls.first.y + 3 * u * t * t * controls.second.y + t * t * t * end.y
            let point = Point(x: x, y: y)
            if !bounds.contains(point) || obstacles.contains(where: { $0.containsStrictly(point) }) {
                return false
            }
        }
        return true
    }
}

private extension MermaidEdgeRoute.Rectangle {
    func containsStrictly(_ point: MermaidEdgeRoute.Point) -> Bool {
        point.x > left && point.x < right && point.y > bottom && point.y < top
    }
}
