import Foundation
@testable import MarkdownPDF
import Testing

/// A cycle is entered where the author starts it: when every node has an incoming edge, layering starts at the node declared first (the others follow
/// its edges), and the edge back to it is the one that is drawn backwards. It used to start at the node with the smallest id, which scrambled the order
/// of a loop such as `s --> g --> p --> l -.-> s`.
@Suite("A cycle is laid out from the node declared first")
struct MermaidCycleLayeringTests {
    private func layerIDs(_ body: String, direction: String = "LR") throws -> [[String]] {
        guard case let .diagram(diagram) = MermaidDiagram.parse("flowchart \(direction)\n\(body)") else {
            Issue.record("did not parse: \(body)")
            return []
        }
        return diagram.layers().map { $0.map(\.id) }
    }

    @Test("a loop is laid out in the order it is written, whatever the node ids sort like")
    func loop() throws {
        #expect(try layerIDs("  s --> g --> p --> l -.-> s") == [["s"], ["g"], ["p"], ["l"]])
        #expect(try layerIDs("  z --> y --> x --> z") == [["z"], ["y"], ["x"]])
    }

    @Test("a loop with a tail that is not part of it keeps the tail first")
    func tail() throws {
        #expect(try layerIDs("  start --> b --> c --> b") == [["start"], ["b"], ["c"]])
    }

    @Test("two separate loops each start at their first node")
    func twoLoops() throws {
        let layers = try layerIDs("  s --> g --> s\n  r --> l --> r")
        #expect(layers.count == 2)
        #expect(layers[0].sorted() == ["r", "s"], Comment(rawValue: "\(layers)"))
        #expect(layers[1].sorted() == ["g", "l"], Comment(rawValue: "\(layers)"))
    }
}
