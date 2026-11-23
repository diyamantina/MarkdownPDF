import Foundation

public extension MarkdownPDF.Render.Report {
    /// Something in a Mermaid diagram that the engine did not draw as the author wrote it, named. The diagram is still drawn, and the note says what was
    /// left out or flagged: a `classDef` property the engine does not draw, a colour it cannot read, a class or a node that a `class` line names and that
    /// does not exist, a text colour with too little contrast on its fill. The colours of the author are never changed.
    struct DiagramNote: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// A `classDef` property the engine does not draw (`font-weight`, `stroke-dasharray`, ...): `name` is the property.
            case unknownProperty
            /// A `classDef` value that is not a colour (`fill`, `stroke`, `color`) or a width (`stroke-width`): `name` is the property.
            case invalidValue
            /// A `class` line names a class no `classDef` defines: `name` is the class.
            case undefinedClass
            /// A `class` line names a node the diagram does not have: `name` is the node.
            case undefinedNode
            /// The text colour of a node on its fill is below the contrast ratio of 4.5: `name` is the node, `detail` the ratio.
            case lowContrast
        }

        public var kind: Kind
        public var name: String
        /// The position of the diagram among the Mermaid diagrams of the document, from 1.
        public var diagram: Int
        /// The line of the diagram source, from 1 (the header is line 1); 0 for a note about the diagram as a whole.
        public var line: Int
        public var detail: String

        public init(kind: Kind, name: String, diagram: Int = 0, line: Int = 0, detail: String = "") {
            self.kind = kind
            self.name = name
            self.diagram = diagram
            self.line = line
            self.detail = detail
        }
    }
}
