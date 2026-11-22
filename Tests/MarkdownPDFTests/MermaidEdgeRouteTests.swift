import Foundation
@testable import MarkdownPDF
import Testing

/// A link whose straight line would run through other nodes bends around them as an arc, and its label sits on the arc.
/// Closed form: a cubic Bezier from `s` to `e` whose two control points lie a third and two thirds along the line, `n d` to its side (`n` the unit
/// normal), is at `t L` along the line and `3 d t (1 - t)` to its side, so `3 d / 4` at its middle. A corner of an obstacle at parameter `t` and
/// `r` past the line needs `3 d t (1 - t) >= r + margin`, the margin being 6 pt.
@Suite("Mermaid edge routes")
struct MermaidEdgeRouteTests {
    typealias Route = MermaidEdgeRoute
    private let wide = Route.Rectangle(left: -1000, bottom: -1000, right: 1000, top: 1000)

    /// Equal to within a rounding error: the closed forms have a divisor such as `3 * (1/3) * (2/3)`.
    private func near(_ lhs: Route.Point, _ rhs: Route.Point) -> Bool {
        abs(lhs.x - rhs.x) < 1e-9 && abs(lhs.y - rhs.y) < 1e-9
    }

    private func isArc(_ path: Route.Path, _ expected1: Route.Point, _ expected2: Route.Point) -> Bool {
        guard case let .arc(control1, control2) = path else {
            return false
        }
        return near(control1, expected1) && near(control2, expected2)
    }

    @Test("a link nothing is in the way of stays straight, its label at the middle")
    func straight() {
        let route = Route.route(from: .init(x: 0, y: 0), to: .init(x: 300, y: 0), avoiding: [], within: wide)
        #expect(route.path == .straight)
        #expect(route.labelPoint == .init(x: 150, y: 0))
    }

    @Test("an obstacle beside the line, not on it, does not bend it")
    func beside() {
        let beside = Route.Rectangle(left: 100, bottom: 10, right: 200, top: 50)
        let route = Route.route(from: .init(x: 0, y: 0), to: .init(x: 300, y: 0), avoiding: [beside], within: wide)
        #expect(route.path == .straight)
    }

    @Test("a node in the way makes an arc above it: d = (r + margin) / (3 t (1 - t)), the label at the apex 3d/4")
    func arc() {
        let node = Route.Rectangle(left: 100, bottom: -20, right: 200, top: 20)
        let route = Route.route(from: .init(x: 0, y: 0), to: .init(x: 300, y: 0), avoiding: [node], within: wide)
        // t = 1/3 is the part of the node nearest an end, r = 20: d = 26 / (3 * 2/9) = 39.
        #expect(isArc(route.path, .init(x: 100, y: 39), .init(x: 200, y: 39)), Comment(rawValue: "\(route)"))
        #expect(near(route.labelPoint, .init(x: 150, y: 29.25)), Comment(rawValue: "\(route)"))
    }

    @Test("the arc goes below when there is no room above, and the link stays straight when there is room on neither side")
    func sides() {
        let node = Route.Rectangle(left: 100, bottom: -20, right: 200, top: 20)
        let start = Route.Point(x: 0, y: 0)
        let end = Route.Point(x: 300, y: 0)
        let noRoomAbove = Route.Rectangle(left: -1000, bottom: -1000, right: 1000, top: 25)
        let below = Route.route(from: start, to: end, avoiding: [node], within: noRoomAbove)
        #expect(isArc(below.path, .init(x: 100, y: -39), .init(x: 200, y: -39)), Comment(rawValue: "\(below)"))
        #expect(near(below.labelPoint, .init(x: 150, y: -29.25)), Comment(rawValue: "\(below)"))
        let noRoom = Route.Rectangle(left: -1000, bottom: -25, right: 1000, top: 25)
        #expect(Route.route(from: start, to: end, avoiding: [node], within: noRoom).path == .straight)
    }

    @Test("a label wider than the gap between the two nodes lifts the link into an arc until the label clears them")
    func labelLifted() {
        let source = Route.Rectangle(left: 0, bottom: -20, right: 100, top: 20)
        let target = Route.Rectangle(left: 160, bottom: -20, right: 260, top: 20)
        let route = Route.route(
            from: .init(x: 100, y: 0),
            to: .init(x: 160, y: 0),
            avoiding: [],
            within: wide,
            label: .init(width: 110, height: 14),
            labelObstacles: [source, target],
        )
        // The label's bottom, y - 7, must be at or above the nodes' tops, 20: the smallest apex 3d/4 in steps of 2 is 27 (d = 36).
        #expect(isArc(route.path, .init(x: 120, y: 36), .init(x: 140, y: 36)), Comment(rawValue: "\(route)"))
        #expect(near(route.labelPoint, .init(x: 130, y: 27)), Comment(rawValue: "\(route)"))
    }

    @Test("a label that fits in the gap leaves the link straight")
    func labelFits() {
        let source = Route.Rectangle(left: 0, bottom: -20, right: 100, top: 20)
        let target = Route.Rectangle(left: 300, bottom: -20, right: 400, top: 20)
        let route = Route.route(
            from: .init(x: 100, y: 0),
            to: .init(x: 300, y: 0),
            avoiding: [],
            within: wide,
            label: .init(width: 50, height: 14),
            labelObstacles: [source, target],
        )
        #expect(route.path == .straight)
        #expect(route.labelPoint == .init(x: 200, y: 0))
    }

    @Test("the arc clears every obstacle along its whole length, on a slanted line too", arguments: [
        (Route.Point(x: 0, y: 0), Route.Point(x: 300, y: 0)),
        (Route.Point(x: 300, y: 0), Route.Point(x: 0, y: 0)),
        (Route.Point(x: 0, y: 0), Route.Point(x: 240, y: 120)),
        (Route.Point(x: 240, y: -90), Route.Point(x: 10, y: 60)),
    ])
    func clears(start: Route.Point, end: Route.Point) {
        let obstacles = [
            Route.Rectangle(left: 60, bottom: -30, right: 120, top: 30),
            Route.Rectangle(left: 130, bottom: -10, right: 190, top: 50),
        ]
        let route = Route.route(from: start, to: end, avoiding: obstacles, within: wide)
        guard case let .arc(control1, control2) = route.path else {
            Issue.record("the line crosses a node, so it must bend: \(route)")
            return
        }
        for step in 0 ... 200 {
            let t = Double(step) / 200
            let u = 1 - t
            let x = u * u * u * start.x + 3 * u * u * t * control1.x + 3 * u * t * t * control2.x + t * t * t * end.x
            let y = u * u * u * start.y + 3 * u * u * t * control1.y + 3 * u * t * t * control2.y + t * t * t * end.y
            for obstacle in obstacles {
                let inside = x > obstacle.left && x < obstacle.right && y > obstacle.bottom && y < obstacle.top
                #expect(!inside, Comment(rawValue: "the arc enters \(obstacle) at t=\(t): (\(x), \(y))"))
            }
        }
    }
}
