import Foundation
@testable import MarkdownPDF
import Testing

/// Where a flowchart link meets its two nodes, and that two links never lie on one line.
///
/// Oracle, on the drawn geometry (the node rectangles and the strokes of the page content):
///
/// 1. A link between two nodes of different layers leaves the source through the side that faces along the flow and enters the target through
///    the side that faces it: bottom to top in a top-down diagram, right to left in a left-to-right one, at the middle of each side, however far
///    to the side the target lies. Before, the sides were chosen by the larger distance between the centres, so a child far to the side of its
///    parent was entered through its flank.
/// 2. A second link between the same two nodes (the way back of a loop) is not drawn on the line of the first: it bends into an arc, and its
///    label sits on the arc, clear of the first link's shaft.
@Suite("A Mermaid link meets the sides that face along the flow, and two links between two nodes do not share a line")
struct MermaidEdgeAttachmentTests {
    private struct Box {
        var left: Double
        var bottom: Double
        var width: Double
        var height: Double

        var right: Double {
            left + width
        }

        var top: Double {
            bottom + height
        }

        var centerX: Double {
            left + width / 2
        }

        var centerY: Double {
            bottom + height / 2
        }

        var area: Double {
            width * height
        }
    }

    private struct Stroke {
        var x1: Double
        var y1: Double
        var x2: Double
        var y2: Double
    }

    private static let tolerance = 0.01

    private func content(_ diagram: String) throws -> String {
        try PDFInspector(MarkdownPDFRenderer().render(markdown: "```mermaid\n\(diagram)\n```\n")).text
    }

    /// The filled rectangles of the page content, `x y width height re f`, the largest first: the diagram's ground, then the nodes.
    private func boxes(in text: String) -> [Box] {
        text.split(separator: "\n").compactMap { line -> Box? in
            let parts = line.split(separator: " ")
            guard parts.count == 6, parts[4] == "re", parts[5] == "f",
                  let left = Double(parts[0]), let bottom = Double(parts[1]),
                  let width = Double(parts[2]), let height = Double(parts[3])
            else { return nil }
            return Box(left: left, bottom: bottom, width: width, height: height)
        }
        .sorted { $0.area > $1.area }
    }

    /// The straight strokes of the page content, `x1 y1 m x2 y2 l S`, in drawing order: an arrow is its shaft, then the two strokes of its head.
    private func strokes(in text: String) -> [Stroke] {
        text.split(separator: "\n").compactMap { line -> Stroke? in
            let parts = line.split(separator: " ")
            guard let move = parts.firstIndex(of: "m"), move >= 2, parts.count > move + 4,
                  parts[move + 3] == "l", parts[move + 4] == "S",
                  let x1 = Double(parts[move - 2]), let y1 = Double(parts[move - 1]),
                  let x2 = Double(parts[move + 1]), let y2 = Double(parts[move + 2])
            else { return nil }
            return Stroke(x1: x1, y1: y1, x2: x2, y2: y2)
        }
    }

    private func near(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < Self.tolerance
    }

    private typealias Rectangle = MermaidEdgeRoute.Rectangle
    private typealias Point = MermaidEdgeRoute.Point

    /// A parent 100 by 40 over a row of children 60 by 40, 36 below it: the closed form of the ends, for a child under it, one whose span
    /// overlaps it, and one far to either side (clear space across larger than the clear space along the flow).
    @Test("the ends in closed form, top-down: bottom middle to top middle for every horizontal position of the child", arguments: [-400.0, -60, 0, 20, 90, 400])
    func endsTopDown(shift: Double) {
        let parent = Rectangle(left: 0, bottom: 76, right: 100, top: 116)
        let child = Rectangle(left: 20 + shift, bottom: 0, right: 80 + shift, top: 40)
        let ends = MermaidEdgeRoute.endpoints(from: parent, to: child, flowIsVertical: true)
        #expect(ends.start == Point(x: 50, y: 76))
        #expect(ends.end == Point(x: 50 + shift, y: 40))
        // The way back joins the same two points.
        let back = MermaidEdgeRoute.endpoints(from: child, to: parent, flowIsVertical: true)
        #expect(back.start == ends.end && back.end == ends.start)
    }

    @Test("the ends in closed form, left to right: right middle to left middle for every vertical position of the next node", arguments: [-400.0, -50, 0, 30, 400])
    func endsLeftToRight(shift: Double) {
        let source = Rectangle(left: 0, bottom: 0, right: 100, top: 40)
        let next = Rectangle(left: 118, bottom: shift, right: 178, top: 40 + shift)
        let ends = MermaidEdgeRoute.endpoints(from: source, to: next, flowIsVertical: false)
        #expect(ends.start == Point(x: 100, y: 20))
        #expect(ends.end == Point(x: 118, y: 20 + shift))
        let back = MermaidEdgeRoute.endpoints(from: next, to: source, flowIsVertical: false)
        #expect(back.start == ends.end && back.end == ends.start)
    }

    @Test("two nodes of one layer are joined across the flow, and nodes with no clear space by the larger distance of their centres")
    func endsWithinALayerAndOverlapping() {
        let left = Rectangle(left: 0, bottom: 0, right: 60, top: 40)
        let right = Rectangle(left: 84, bottom: 5, right: 144, top: 35)
        // One row of a top-down diagram: no clear space along the flow, 24 across it.
        let row = MermaidEdgeRoute.endpoints(from: left, to: right, flowIsVertical: true)
        #expect(row.start == Point(x: 60, y: 20) && row.end == Point(x: 84, y: 20))
        // One column of a left-to-right diagram, the lower node first.
        let lower = Rectangle(left: 0, bottom: 0, right: 60, top: 40)
        let upper = Rectangle(left: 10, bottom: 60, right: 50, top: 100)
        let column = MermaidEdgeRoute.endpoints(from: lower, to: upper, flowIsVertical: false)
        #expect(column.start == Point(x: 30, y: 40) && column.end == Point(x: 30, y: 60))
        // A node inside a frame: the old choice, by the centres (60 across, 10 up).
        let frame = Rectangle(left: 0, bottom: 0, right: 200, top: 100)
        let inside = Rectangle(left: 140, bottom: 40, right: 180, top: 80)
        for flowIsVertical in [true, false] {
            let ends = MermaidEdgeRoute.endpoints(from: frame, to: inside, flowIsVertical: flowIsVertical)
            #expect(ends.start == Point(x: 200, y: 50) && ends.end == Point(x: 140, y: 60))
        }
    }

    @Test("a first link between two nodes is straight; each later one is an arc whose apex is one lift further from the line")
    func laterLinksAreLifted() {
        let start = Point(x: 100, y: 50)
        let end = Point(x: 160, y: 50)
        let bounds = Rectangle(left: 0, bottom: 0, right: 300, top: 100)
        let label = MermaidEdgeRoute.LabelSize(width: 27, height: 12)
        // Half the ground along the normal and the margin of 6: its height over a level line, its width beside an upright one.
        #expect(MermaidEdgeRoute.apexLift(label: label, normal: Point(x: 0, y: 1)) == 12)
        #expect(MermaidEdgeRoute.apexLift(label: label, normal: Point(x: -1, y: 0)) == 19.5)
        #expect(MermaidEdgeRoute.apexLift(label: nil, normal: Point(x: 0, y: 1)) == 12)
        // Beside an upright line the label is lifted by its width: its ground ends 6 pt from the line, on either side.
        let upright = MermaidEdgeRoute.route(
            from: Point(x: 150, y: 20), to: Point(x: 150, y: 80), avoiding: [], within: bounds, label: label, earlierLinks: 1,
        )
        #expect(abs(upright.labelPoint.x - 150) == 19.5 && upright.labelPoint.y == 50)
        let first = MermaidEdgeRoute.route(from: start, to: end, avoiding: [], within: bounds, label: label)
        #expect(first.path == .straight && first.labelPoint == Point(x: 130, y: 50))
        for earlier in 1 ... 3 {
            // The way back runs from the far end to the near one.
            let later = MermaidEdgeRoute.route(from: end, to: start, avoiding: [], within: bounds, label: label, earlierLinks: earlier)
            // The upper side on a tie: the apex is 12 pt above the line for each earlier link, the controls 16 pt (apex = 3/4 of the offset).
            #expect(later.labelPoint == Point(x: 130, y: 50 + 12 * Double(earlier)))
            #expect(later.path == .arc(
                control1: Point(x: 140, y: 50 + 16 * Double(earlier)),
                control2: Point(x: 120, y: 50 + 16 * Double(earlier)),
            ))
        }
        // With no room on either side the link stays straight: the limit of the rule.
        let tight = Rectangle(left: 0, bottom: 45, right: 300, top: 55)
        #expect(MermaidEdgeRoute.route(from: end, to: start, avoiding: [], within: tight, label: label, earlierLinks: 1).path == .straight)
    }

    @Test("the placement of links: the flow of the pair's own layout, and the count of drawn links before it between the same two nodes")
    func placements() {
        let source = """
        flowchart LR
          a --> b
          b --> a
          a ~~~ c
          c --> a
          a --> b
          a --> a
          subgraph G
            direction TB
            x --> y
          end
          y --> a
        """
        guard case let .diagram(diagram) = MermaidDiagram.parse(source) else {
            Issue.record("the diagram is not read")
            return
        }
        let found = diagram.edgePlacements(outerDirection: .leftRight)
        let byEnds = Dictionary(grouping: zip(diagram.edges, found), by: { "\($0.0.source)>\($0.0.target)" })
        #expect(byEnds["a>b"]?.map(\.1.earlierLinks) == [0, 2])
        #expect(byEnds["b>a"]?.map(\.1.earlierLinks) == [1])
        // The hidden link is not counted: the first drawn link between a and c is the one back.
        #expect(byEnds["c>a"]?.map(\.1.earlierLinks) == [0])
        #expect(byEnds["a>a"]?.map(\.1.earlierLinks) == [0])
        #expect(byEnds["x>y"]?.map(\.1.flowIsVertical) == [true])
        #expect(byEnds["y>a"]?.map(\.1.flowIsVertical) == [false])
        #expect(byEnds["a>b"]?.map(\.1.flowIsVertical) == [false, false])
    }

    @Test("top-down: every child of a parent, however far to the side, is entered through the middle of its top edge")
    func treeEntersTopEdges() throws {
        let text = try content("""
        flowchart TD
          SUI["SwiftUI, one graph"] --> CA["Core Animation, the compositor"]
          CA --> CG["Core Graphics, drawing"]
          CA --> CT["Core Text, typesetting"]
          CA --> CI["Core Image, effects"]
        """)
        #expect(!text.contains("Unsupported"))
        let nodes = Array(boxes(in: text).dropFirst())
        #expect(nodes.count == 5)
        let drawn = strokes(in: text)
        #expect(drawn.count == 12, "four arrows, each a shaft and two head strokes")
        let shafts = stride(from: 0, to: drawn.count, by: 3).map { drawn[$0] }
        for shaft in shafts {
            let leaves = nodes.contains { near(shaft.y1, $0.bottom) && near(shaft.x1, $0.centerX) }
            let enters = nodes.contains { near(shaft.y2, $0.top) && near(shaft.x2, $0.centerX) }
            #expect(leaves, Comment(rawValue: "the shaft from (\(shaft.x1), \(shaft.y1)) does not leave the middle of a bottom edge"))
            #expect(enters, Comment(rawValue: "the shaft to (\(shaft.x2), \(shaft.y2)) does not enter the middle of a top edge"))
        }
    }

    @Test("left to right: every node of the next column, however far up or down, is entered through the middle of its left edge")
    func fanEntersLeftEdges() throws {
        let text = try content("""
        flowchart LR
          A --> B
          A --> C
          A --> D
          A --> E
          A --> F
          A --> G
          A --> H
        """)
        #expect(!text.contains("Unsupported"))
        let nodes = Array(boxes(in: text).dropFirst())
        #expect(nodes.count == 8)
        let drawn = strokes(in: text)
        #expect(drawn.count == 21, "seven arrows, each a shaft and two head strokes")
        let shafts = stride(from: 0, to: drawn.count, by: 3).map { drawn[$0] }
        for shaft in shafts {
            let leaves = nodes.contains { near(shaft.x1, $0.right) && near(shaft.y1, $0.centerY) }
            let enters = nodes.contains { near(shaft.x2, $0.left) && near(shaft.y2, $0.centerY) }
            #expect(leaves, Comment(rawValue: "the shaft from (\(shaft.x1), \(shaft.y1)) does not leave the middle of a right edge"))
            #expect(enters, Comment(rawValue: "the shaft to (\(shaft.x2), \(shaft.y2)) does not enter the middle of a left edge"))
        }
    }

    @Test("a link there and a labelled link back: one stroke on the line between the two nodes, and the label off it")
    func wayBackIsNotDrawnOnTheWayThere() throws {
        let markdown = """
        ```mermaid
        flowchart LR
          I["Inputs, 0 to n"] --> F["Function"]
          F --> O["Cached output, persistent"]
          O -.->|re-run| F
        ```

        """
        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let text = PDFInspector(data).text
        #expect(!text.contains("Unsupported"))
        let filled = boxes(in: text)
        // The ground, the three nodes, then the small ground of the label.
        #expect(filled.count == 5)
        let nodes = filled[1 ... 3].sorted { $0.left < $1.left }
        let function = nodes[1]
        let output = nodes[2]
        let line = function.centerY
        #expect(near(line, output.centerY))

        let onTheLine = strokes(in: text).filter {
            near($0.y1, line) && near($0.y2, line)
                && min($0.x1, $0.x2) > function.right - Self.tolerance && max($0.x1, $0.x2) < output.left + Self.tolerance
        }
        #expect(onTheLine.count == 1, Comment(rawValue: "\(onTheLine.count) strokes lie on the line between the two nodes"))

        // The label is drawn 3 pt above the bottom of its ground, which is its size and 4 pt high.
        let label = try #require(PDFDocumentReader(data: data).pages.flatMap(\.words).first { $0.text == "re-run" })
        let groundBottom = label.y - 3
        let groundTop = groundBottom + label.fontSize + 4
        #expect(groundBottom > line + 0.4 || groundTop < line - 0.4, Comment(rawValue: "the label's ground (\(groundBottom) to \(groundTop)) covers the line at \(line)"))
        #expect(label.x - 3 > function.right && label.x + label.width + 3 < output.left, "the label stays between the two nodes")
    }

    @Test("top-down, a link down and a labelled link back up: the label's ground is beside the upright line, not on it")
    func wayBackUpIsBesideTheWayDown() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "```mermaid\nflowchart TD\n  A[First] --> B[Second]\n  B -.->|feedback| A\n```\n")
        let text = PDFInspector(data).text
        #expect(!text.contains("Unsupported"))
        let filled = boxes(in: text)
        #expect(filled.count == 4)
        let line = filled[1].centerX
        #expect(near(line, filled[2].centerX))
        let upright = strokes(in: text).filter { near($0.x1, line) && near($0.x2, line) }
        #expect(upright.count == 1, Comment(rawValue: "\(upright.count) strokes lie on the upright line between the two nodes"))
        let label = try #require(PDFDocumentReader(data: data).pages.flatMap(\.words).first { $0.text == "feedback" })
        let groundLeft = label.x - 3
        let groundRight = label.x + label.width + 3
        #expect(groundRight < line - 0.4 || groundLeft > line + 0.4, Comment(rawValue: "the label's ground (\(groundLeft) to \(groundRight)) covers the line at \(line)"))
    }
}
