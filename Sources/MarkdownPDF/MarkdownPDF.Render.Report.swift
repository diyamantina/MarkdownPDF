import Foundation

public extension MarkdownPDF.Render {
    /// What a render could not draw from a face: each character of the page that no embedded face has a glyph for, named, with the reason and how often
    /// it occurs. A character in this list is not drawn as the character: the base-14 font writes a stand-in letter for it (the check mark as `v`, an
    /// emoji as `?`), and an embedded face that lacks it draws its missing-glyph box. It is never replaced silently: it is here.
    ///
    /// The report is made from the text of the document, in the order of first appearance, with the same questions the drawing asks (does an embedded
    /// face have the glyph, can the colour face draw the emoji), so a character the page draws from a face is not in it. The text of diagrams and charts
    /// (a Mermaid or chart fence) and the source of formulas are not read: they have their own paths.
    struct Report: Equatable, Sendable {
        /// The characters that were not drawn, in the order of first appearance.
        public var undrawn: [Character]
        /// What a Mermaid diagram asked for and the engine did not draw as written (see ``DiagramNote``), in the order of the diagrams and their lines.
        public var diagramNotes: [DiagramNote]

        public init(undrawn: [Character] = [], diagramNotes: [DiagramNote] = []) {
            self.undrawn = undrawn
            self.diagramNotes = diagramNotes
        }

        /// True when every character of the page is drawn from a face and no diagram has a note.
        public var isEmpty: Bool {
            undrawn.isEmpty && diagramNotes.isEmpty
        }
    }
}
