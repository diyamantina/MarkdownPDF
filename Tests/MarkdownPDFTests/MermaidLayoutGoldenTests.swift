import Foundation
@testable import MarkdownPDF
import Testing

/// The page content of flowcharts without groups, captured before the layout was shared with
/// subgraphs. The layout of such a diagram must not move by a hundredth of a point.
@Suite("Mermaid layout golden")
struct MermaidLayoutGoldenTests {
    static let corpus: [(name: String, source: String)] = [
        ("topDown", """
        flowchart TD
            Input[Markdown source] --> Parse[Block parser]
            Parse --> Layout[Article layout]
            Layout --> PDF[PDF bytes]
            Parse -->|side| Index[Index]
        """),
        ("leftRight", """
        flowchart LR
            A[Apps] --> B[Features]
            B --> C[Foundation]
            A -.->|skip| C
            D[Alone]
        """),
        ("cycle", """
        flowchart TD
            A[First] --> B[Second]
            B -.->|feedback| A
        """),
        ("wide", """
        flowchart LR
            T["Destination state, your data"] --> Cp["Copy"]
            Cp --> Inj["Intermediate value injected"]
            Inj --> Rn["Copy is rendered"]
        """),
        ("breaks", """
        flowchart LR
          g["runAnimationGroup<br/>duration 0.5"] --> a["view.animator()<br/>.alphaValue = 0.2"] --> r["the view animates<br/>instead of popping"]
        """),
        ("bottomTop", """
        flowchart BT
            A[Base] --> B[Middle]
            B --> C[Top]
            A --> D[Side]
        """),
    ]

    static func rendered() throws -> String {
        try corpus.map { name, source in
            let markdown = "```mermaid\n\(source)\n```\n"
            let data = try MarkdownPDFRenderer().render(markdown: markdown)
            return "=== \(name)\n\(PDFInspector(data).text)\n"
        }.joined()
    }

    static var goldenURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/mermaid-layout-golden.txt")
    }

    @Test("Diagrams without groups lay out exactly as before")
    func ungroupedLayoutIsUnchanged() throws {
        let golden = try String(contentsOf: Self.goldenURL, encoding: .utf8)
        #expect(try Self.rendered() == golden)
    }
}
