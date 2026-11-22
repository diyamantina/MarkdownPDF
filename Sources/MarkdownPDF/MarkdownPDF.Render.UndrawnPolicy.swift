public extension MarkdownPDF.Render {
    /// What a render does with a character it cannot draw from a face (``Report``).
    enum UndrawnPolicy: Equatable, Sendable {
        /// Draw what the faces allow and go on; ``MarkdownPDFRenderer/renderWithReport(markdown:assetsBaseURL:)`` returns the list.
        case report
        /// Throw ``MarkdownPDFError/undrawnCharacters(_:)`` when the list is not empty: a stripped build fails loudly instead of printing wrong letters.
        case fail
    }
}
