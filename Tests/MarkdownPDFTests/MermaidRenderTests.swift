@testable import MarkdownPDF
import Testing

@Suite("Mermaid PDF rendering")
struct MermaidRenderTests {
    @Test("A figure separates itself from the next block", arguments: [
        """
        flowchart LR
            A[Apps] --> B[Features]
        """,
    ])
    func mermaidDiagramAddsTrailingSpacing(_ diagram: String) throws {
        try expectFigureTrailingSpacing(fenceInfo: "mermaid", body: diagram)
    }

    @Test("A native chart separates itself from the next block")
    func chartAddsTrailingSpacing() throws {
        try expectFigureTrailingSpacing(fenceInfo: "chart", body: """
        type: bar
        title: Revenue
        categories: Q1, Q2
        series: Actual = 3, 5
        """)
    }

    @Test("A trailing figure does not claim a page for whitespace it cannot use")
    func trailingFigureDoesNotForceAPageBreak() throws {
        // `ensureSpace` must reserve only what the figure draws. Reserving the
        // trailing gap too would push a figure that fits onto the next page for
        // the sake of whitespace with nothing after it.
        let fence = "```"
        let diagram = "\(fence)mermaid\nflowchart LR\n    A[Apps] --> B[Features]\n\(fence)\n"

        func pageCount(fillerParagraphs: Int) throws -> Int {
            let markdown = String(repeating: "Filler.\n\n", count: fillerParagraphs) + diagram
            return try PDFInspector(MarkdownPDFRenderer().render(markdown: markdown)).pageCount
        }

        // 34 paragraphs plus the diagram is the last layout that fits one page.
        #expect(try pageCount(fillerParagraphs: 34) == 1)
        #expect(try pageCount(fillerParagraphs: 35) == 2)
    }

    /// Both figure paths draw a frame, then advance `y`. Without
    /// `figureTrailingSpacing` the following paragraph's ascender lands on that
    /// frame, so assert the gap is the block model's spacing, not the bare 12pt
    /// figure padding.
    private func expectFigureTrailingSpacing(fenceInfo: String, body: String) throws {
        let fence = "```"
        let markdown = "Above.\n\n\(fence)\(fenceInfo)\n\(body)\n\(fence)\n\nBelow.\n"
        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let lines = PDFInspector(data).text.split(separator: "\n")

        // The figure frame is the widest filled rectangle on the page.
        let frameBottom = try #require(
            lines.compactMap { line -> (bottom: Double, width: Double)? in
                let parts = line.split(separator: " ")
                guard parts.count == 6, parts[4] == "re", parts[5] == "f",
                      let y = Double(parts[1]), let w = Double(parts[2])
                else { return nil }
                return (y, w)
            }
            .max { $0.width < $1.width }?.bottom,
            "no figure frame drawn for \(fenceInfo)",
        )

        let belowBaseline = try #require(
            lines.first { $0.contains("(Below") }
                .flatMap { line -> Double? in
                    let parts = line.split(separator: " ")
                    return parts.count > 5 ? Double(parts[5]) : nil
                },
            "no paragraph after the \(fenceInfo) figure",
        )

        let baseFontSize = PDFOptions().baseFontSize
        let paragraphSpacing = baseFontSize * PDFOptions.Theme.default.style(for: .paragraph).spacingAfterMultiplier
        #expect(abs((frameBottom - belowBaseline) - (12 + paragraphSpacing)) < 0.01)
        #expect(frameBottom - belowBaseline > 12)
    }

    @Test("A dashed edge inside a cycle renders without falling back to source")
    func dashedEdgeAndCycleRender() throws {
        let markdown = """
        ```mermaid
        flowchart TD
            A[First] --> B[Second]
            B -.->|feedback| A
        ```
        """

        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let inspector = PDFInspector(data)

        // Neither the dashed edge nor the cycle drops the diagram to its source.
        #expect(!inspector.text.contains("Unsupported"))
        #expect(!inspector.text.contains("flowchart TD"))
        #expect(inspector.hasValidXrefOffsets())
    }

    @Test("A chained flowchart with line breaks draws every label on its own lines")
    func chainedFlowchartWithLineBreaksRenders() throws {
        let markdown = """
        ```mermaid
        flowchart LR
          g["runAnimationGroup<br/>duration 0.5"] --> a["view.animator()<br/>.alphaValue = 0.2"] --> r["the view animates<br/>instead of popping"]
        ```
        """

        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let inspector = PDFInspector(data)
        let lines = inspector.text.split(separator: "\n").map(String.init)

        // No tag, no arrow and no source is left on the page.
        #expect(!inspector.text.contains("<br"))
        #expect(!inspector.text.contains("-->"))
        #expect(!inspector.text.contains("Unsupported"))
        #expect(!inspector.text.contains("flowchart LR"))

        // The text operators put each word at a baseline: `BT /F1 9.680 Tf x y Td (word) Tj ET`.
        func baseline(ofWordStartingWith word: String) throws -> Double {
            let line = try #require(lines.first { $0.contains("(\(word)") }, "no text starting with \(word)")
            let parts = line.split(separator: " ")
            return try #require(parts.count > 6 ? Double(parts[5]) : nil, "no baseline in \(line)")
        }

        // A line break puts the second half of a label on a lower baseline, and the words of
        // one half share a baseline.
        for (upper, lower) in [
            ("runAnimationGroup", "duration"),
            ("view.animator", ".alphaValue"),
            ("animates", "instead"),
        ] {
            let upperBaseline = try baseline(ofWordStartingWith: upper)
            let lowerBaseline = try baseline(ofWordStartingWith: lower)
            #expect(upperBaseline > lowerBaseline + 5, "\(lower) is not below \(upper)")
        }
        #expect(try baseline(ofWordStartingWith: "duration") == baseline(ofWordStartingWith: "0.5"))
        #expect(try baseline(ofWordStartingWith: "instead") == baseline(ofWordStartingWith: "popping"))
        #expect(inspector.hasValidXrefOffsets())
    }

    /// A filled rectangle of the page content, `x y width height re f`.
    private struct FilledRectangle {
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

        var area: Double {
            width * height
        }

        func contains(_ other: FilledRectangle) -> Bool {
            other.left >= left && other.right <= right && other.bottom >= bottom && other.top <= top
        }

        func overlaps(_ other: FilledRectangle) -> Bool {
            left < other.right && right > other.left && bottom < other.top && top > other.bottom
        }
    }

    private func filledRectangles(in text: String) -> [FilledRectangle] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count == 6, parts[4] == "re", parts[5] == "f",
                  let left = Double(parts[0]), let bottom = Double(parts[1]),
                  let width = Double(parts[2]), let height = Double(parts[3])
            else { return nil }
            return FilledRectangle(left: left, bottom: bottom, width: width, height: height)
        }
    }

    /// The strokes of arrows and links, one `m ... l S` line each: an arrow is a shaft and two
    /// head strokes, a link without a head is the shaft alone.
    private func strokeCount(in text: String) -> Int {
        text.split(separator: "\n").filter { $0.contains(" m ") && $0.contains(" l S") }.count
    }

    private func rendered(_ diagram: String) throws -> PDFInspector {
        try PDFInspector(MarkdownPDFRenderer().render(markdown: "```mermaid\n\(diagram)\n```\n"))
    }

    @Test("A subgraph is a titled frame around its nodes, laid out in its own direction")
    func subgraphsDrawAsFramesAroundTheirNodes() throws {
        let inspector = try rendered("""
        flowchart TB
          subgraph A["Group A"]
            direction TB
            a1["one"] --> a2["two"]
          end
          subgraph B["Group B"]
            direction LR
            b1["three"] --> b2["four"]
          end
          A ~~~ B
        """)

        for leftover in ["Unsupported", "subgraph", "direction", "~~~", "flowchart"] {
            #expect(!inspector.text.contains(leftover), "\(leftover) is left on the page")
        }
        #expect(inspector.text.contains("(Group"))

        // The page frame, two group frames and four nodes.
        let rectangles = filledRectangles(in: inspector.text).sorted { $0.area > $1.area }
        #expect(rectangles.count == 7)
        let groups = Array(rectangles[1 ... 2])
        let nodes = Array(rectangles[3...])
        #expect(!groups[0].overlaps(groups[1]))
        for group in groups {
            #expect(nodes.filter { group.contains($0) }.count == 2, "a group does not hold exactly its two nodes")
        }
        #expect(nodes.allSatisfy { node in groups.contains { $0.contains(node) } })

        // `A ~~~ B` puts group A above group B, and the two links inside draw as arrows;
        // the invisible link draws nothing.
        let above = groups.max { $0.bottom < $1.bottom }
        let below = groups.min { $0.bottom < $1.bottom }
        let aNodes = try nodes.filter { try #require(above).contains($0) }
        let bNodes = try nodes.filter { try #require(below).contains($0) }
        #expect(try #require(above).bottom >= #require(below).top)
        #expect(strokeCount(in: inspector.text) == 6)

        // Group A is top to bottom: its nodes share a column. Group B is left to right: its
        // nodes share a row.
        #expect(aNodes.count == 2 && abs(aNodes[0].left - aNodes[1].left) < 0.01)
        #expect(aNodes[0].bottom != aNodes[1].bottom)
        #expect(bNodes.count == 2 && abs(bNodes[0].bottom - bNodes[1].bottom) < 0.01)
        #expect(bNodes[0].left != bNodes[1].left)
        #expect(inspector.hasValidXrefOffsets())
    }

    @Test("A link from a node outside a group to one inside, and between groups, is drawn")
    func linksCrossGroupFrames() throws {
        let inspector = try rendered("""
        flowchart TB
          tick["ticks"] --> evaluate
          subgraph T["thread"]
            evaluate --> queue
          end
          subgraph R["server"]
            swap
          end
          queue --> swap
        """)

        #expect(!inspector.text.contains("Unsupported"))
        // Three arrows: tick to evaluate, evaluate to queue, queue to swap.
        #expect(strokeCount(in: inspector.text) == 9)
        // Page frame, two groups, four nodes.
        #expect(filledRectangles(in: inspector.text).count == 7)
    }

    @Test("A link to a group is drawn to the group's frame")
    func linkToAGroupEndsAtItsFrame() throws {
        let inspector = try rendered("""
        flowchart TB
          start --> G
          subgraph G["the group"]
            inside
          end
        """)

        #expect(!inspector.text.contains("Unsupported"))
        #expect(strokeCount(in: inspector.text) == 3)

        // The shaft is the first stroke: `0.800 w x1 y1 m x2 y2 l S`. It ends on the frame's
        // top edge, not on the node inside.
        let rectangles = filledRectangles(in: inspector.text).sorted { $0.area > $1.area }
        let group = rectangles[1]
        let inside = try #require(rectangles.last)
        let shaft = try #require(inspector.text.split(separator: "\n").first { $0.contains(" m ") && $0.contains(" l S") })
        let parts = shaft.split(separator: " ")
        let endY = try #require(parts.count >= 9 ? Double(parts[6]) : nil)
        #expect(abs(endY - group.top) < 0.01)
        #expect(abs(endY - inside.top) > 1)
    }

    @Test("A label inside a group sits on the group's colour and one that straddles its frame is refused")
    func edgeLabelsAndGroupFrames() throws {
        let inside = try rendered("""
        flowchart TB
          subgraph G
            a -->|yes| b
          end
        """)
        #expect(!inside.text.contains("Unsupported"))
        // The group frame and the label behind `yes` share the group colour.
        let groupFill = "0.930 0.950 0.970 rg"
        #expect(inside.text.split(separator: "\n").filter { $0 == groupFill }.count == 2)

        let straddling = try rendered("""
        flowchart LR
          x -->|feedback loop| a
          subgraph G
            a
          end
        """)
        #expect(straddling.text.contains("Unsupported"))
    }

    @Test("A plain link has no arrowhead and a dotted plain link is dashed")
    func plainLinksDrawWithoutHeads() throws {
        let plain = try rendered("flowchart LR\n  A --- B\n")
        let arrow = try rendered("flowchart LR\n  A --> B\n")
        let dotted = try rendered("flowchart LR\n  A -.- B\n")

        #expect(strokeCount(in: arrow.text) == 3)
        #expect(strokeCount(in: plain.text) == 1)
        #expect(strokeCount(in: dotted.text) == 1)
        #expect(dotted.text.contains("[2.400 1.800] 0 d"))
        #expect(!plain.text.contains("[2.400 1.800] 0 d"))
        #expect(!plain.text.contains("Unsupported"))
    }

    @Test("A group too wide for the page is shrunk to fit instead of falling back")
    func wideGroupIsScaledToFit() throws {
        let inspector = try rendered("""
        flowchart TB
          subgraph G["a left to right group"]
            direction LR
            a["first long label here"] --> b["second long label here"] --> c["third long label here"] --> d["fourth long label here"]
          end
        """)

        #expect(!inspector.text.contains("Unsupported"))
        #expect(!inspector.text.contains("subgraph"))
        #expect(inspector.hasValidXrefOffsets())
    }

    @Test("A diagram a little taller than the page is shrunk to fit instead of falling back")
    func tallDiagramScalesToFit() throws {
        // Twelve rows are taller than the page body at full size and fit once shrunk by the
        // same steps as a too-wide diagram.
        let chain = (1 ... 12).map { "n\($0)" }.joined(separator: " --> ")
        let inspector = try rendered("flowchart TB\n  \(chain)\n")

        #expect(!inspector.text.contains("Unsupported"))
        #expect(!inspector.text.contains("flowchart"))
        #expect(inspector.hasValidXrefOffsets())
    }

    @Test("A diagram too tall even when shrunk still falls back to its source")
    func hopelesslyTallDiagramFallsBack() throws {
        let chain = (1 ... 40).map { "n\($0)" }.joined(separator: " --> ")
        let inspector = try rendered("flowchart TB\n  \(chain)\n")

        #expect(inspector.text.contains("(Unsupported"))
        #expect(inspector.text.contains("(taller"))
    }

    @Test("A long group title wraps inside its frame")
    func longGroupTitleWraps() throws {
        let title = String(repeating: "a very long group title ", count: 12)
        let inspector = try rendered("""
        flowchart TB
          subgraph G["\(title)"]
            n["node"]
          end
        """)

        #expect(!inspector.text.contains("Unsupported"))
        let rectangles = filledRectangles(in: inspector.text).sorted { $0.area > $1.area }
        #expect(rectangles.count == 3)
        // The frame is inside the page frame and holds the node.
        #expect(rectangles[0].contains(rectangles[1]))
        #expect(rectangles[1].contains(rectangles[2]))
    }

    @Test("A wide horizontal flowchart is scaled to fit instead of falling back")
    func wideHorizontalFlowchartScalesToFit() throws {
        let markdown = """
        ```mermaid
        flowchart LR
            T["Destination state, your data"] --> Cp["Copy"]
            Cp --> Inj["Intermediate value injected"]
            Inj --> Rn["Copy is rendered"]
        ```
        """

        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let inspector = PDFInspector(data)

        // Four wide nodes in a row exceed the content width; the engine shrinks the
        // diagram to fit rather than dropping it to source.
        #expect(!inspector.text.contains("Unsupported"))
        #expect(!inspector.text.contains("flowchart LR"))
        #expect(inspector.hasValidXrefOffsets())
    }
}
