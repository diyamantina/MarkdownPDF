import Foundation
@testable import MarkdownPDF
import Testing

/// An edge that ends at the middle of the side of a rounded node comes in over the rounded end when it is diagonal, so the part of it that lies inside
/// the outline, and its arrowhead, are painted over by the node's fill. The edge must end where it meets the OUTLINE: then the arrowhead is outside the
/// node and seen. The geometry is that of the post's second diagram: a stadium target below and to the right of a rectangle, reached on a diagonal.
@Suite("A Mermaid edge ends on the outline of a rounded node")
struct MermaidEdgeEndTests {
    private typealias Shape = MermaidDiagram.Node.Shape

    /// The stadium of "Row kept its place": 100 wide, 34 high, its left end at x = 0.
    private let box = (left: 0.0, bottom: 0.0, width: 100.0, height: 34.0)

    private func clipped(_ shape: Shape, from start: (x: Double, y: Double)) -> (x: Double, y: Double) {
        let end = (x: box.left, y: box.bottom + box.height / 2)
        return Shape.clippedEnd(from: start, to: end, shape: shape, left: box.left, bottom: box.bottom, width: box.width, height: box.height)
    }

    @Test("a diagonal edge to the left tip of a stadium ends outside the fill: on the outline, before the tip")
    func stadiumDiagonal() {
        let end = clipped(.stadium, from: (x: 60, y: 120))
        // The old end was the tip (0, 17), inside the capsule's boundary only by the corner of the rounded end: the new end is on the boundary of the
        // capsule on the way from the start, so it is nearer the start than the tip is.
        let distanceToStart = hypot(end.x - 60, end.y - 120)
        let distanceOfTip: Double = hypot(-60.0, -103.0)
        #expect(distanceToStart < distanceOfTip - 1, Comment(rawValue: "the edge still ends at the tip: \(end)"))
        // And the point just before it, toward the start, is outside the outline: the arrowhead lies in the open.
        let before = (x: end.x + (60 - end.x) * 0.02, y: end.y + (120 - end.y) * 0.02)
        #expect(!Shape.stadium.contains(x: before.x, y: before.y, left: box.left, bottom: box.bottom, width: box.width, height: box.height))
    }

    @Test("an edge that meets the side of a rectangle ends where it always did, byte for byte")
    func rectangleUnchanged() {
        let end = clipped(.rectangle, from: (x: 60, y: 120))
        #expect(end.x == 0 && end.y == 17)
    }

    @Test("a straight edge into the middle of the long side of a stadium is not shortened")
    func straightOnUnchanged() {
        let end = Shape.clippedEnd(
            from: (x: 50, y: 120), to: (x: 50, y: 34), shape: .stadium, left: 0, bottom: 0, width: 100, height: 34,
        )
        #expect(abs(end.x - 50) < 1e-6 && abs(end.y - 34) < 0.001, Comment(rawValue: "\(end)"))
    }

    @Test("a diamond is clipped on its slanted side")
    func diamond() {
        let end = Shape.clippedEnd(
            from: (x: 100, y: 100), to: (x: 50, y: 17), shape: .diamond, left: 0, bottom: 0, width: 100, height: 34,
        )
        // Aimed at the centre, the edge stops on the outline: nearer the start than the centre, and on the boundary.
        let distanceOfCentre: Double = hypot(-50.0, -83.0)
        #expect(hypot(end.x - 100, end.y - 100) < distanceOfCentre - 0.5, Comment(rawValue: "\(end)"))
        let onBoundary = abs(end.x - 50) / 50 + abs(end.y - 17) / 17
        #expect(abs(onBoundary - 1) < 1e-6, Comment(rawValue: "\(end) is not on the outline"))
    }
}
