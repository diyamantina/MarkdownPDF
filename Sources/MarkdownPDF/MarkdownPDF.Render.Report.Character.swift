import Foundation

public extension MarkdownPDF.Render.Report {
    /// One character of a page, as written (a grapheme cluster: an emoji with its selector, a flag, a joined sequence), that no embedded face draws.
    struct Character: Equatable, Sendable {
        /// The character as written.
        public var text: String
        /// Its code points.
        public var codePoints: [UInt32]
        /// Why it is not drawn.
        public var reason: Reason
        /// How many times the document writes it.
        public var count: Int

        public init(text: String, codePoints: [UInt32], reason: Reason, count: Int) {
            self.text = text
            self.codePoints = codePoints
            self.reason = reason
            self.count = count
        }
    }
}
