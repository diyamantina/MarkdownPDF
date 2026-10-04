import Foundation

public extension PDFOptions {
    /// A colophon: the last page or pages of the document, after the index.
    ///
    /// The default value is ``disabled``, which leaves the document byte for byte as
    /// it was. Enabled, the colophon starts on a fresh page after everything else,
    /// including the index (which is otherwise always last), so a colophon never ends
    /// up before the index the way a source merged into the body would.
    ///
    /// ## Default text
    ///
    /// With no custom ``markdown``, the page is this Markdown, where the title and
    /// the author come from ``PDFOptions/title`` and ``PDFOptions/author``:
    ///
    /// ```markdown
    /// # Colophon
    ///
    /// *Title* by Author.
    ///
    /// This edition was typeset with MarkdownPDF, a pure Swift Markdown to PDF
    /// renderer written by Mihaela Mihaljevic. MarkdownPDF parses the Markdown, lays
    /// out the pages and writes the PDF bytes itself, with no browser, no word
    /// processor and no LaTeX.
    ///
    /// MarkdownPDF is open source: [https://codeberg.org/MarkdownPdfHQ/MarkdownPDF](https://codeberg.org/MarkdownPdfHQ/MarkdownPDF)
    /// ```
    ///
    /// A missing part is dropped cleanly: with a title only the line is `*Title*.`,
    /// with an author only it is `By Author.`, with neither the line is left out. The
    /// title and the author are drawn as given and are never read as Markdown. The
    /// link has visible text and a real URI link annotation.
    ///
    /// ## Custom text
    ///
    /// ``markdown`` replaces the default text entirely, heading included. It is parsed
    /// like any other source (and, with ``PDFOptions/ignoreHTMLComments`` on, stripped
    /// of comments), and its relative image paths resolve against ``assetsBaseURL``.
    /// Rendering throws ``MarkdownPDFError/colophonTextEmpty`` for a custom text that
    /// is empty or only white space: an enabled colophon is never skipped silently.
    ///
    /// ## Behaviour
    ///
    /// The colophon is laid out inside the same convergence loop as the table of
    /// contents and the index. A level-one heading in it reaches the outline and the
    /// table of contents with its correct page number, its pages carry page numbers
    /// like body pages, and the index does not search it. Footnote references in a
    /// custom text are not resolved: footnotes belong to the body sources.
    struct Colophon: Equatable, Sendable {
        /// Whether a colophon is drawn.
        public var isEnabled: Bool

        /// Custom Markdown that replaces the default text, or nil for the default.
        public var markdown: String?

        /// The folder relative image paths in ``markdown`` resolve against. When nil,
        /// the current working directory is used.
        public var assetsBaseURL: URL?

        public init(isEnabled: Bool, markdown: String? = nil, assetsBaseURL: URL? = nil) {
            self.isEnabled = isEnabled
            self.markdown = markdown
            self.assetsBaseURL = assetsBaseURL
        }

        /// No colophon.
        public static let disabled = Colophon(isEnabled: false)

        /// A colophon with the default text.
        public static let enabled = Colophon(isEnabled: true)

        /// A colophon with `markdown` instead of the default text.
        public static func enabled(markdown: String, assetsBaseURL: URL? = nil) -> Colophon {
            Colophon(isEnabled: true, markdown: markdown, assetsBaseURL: assetsBaseURL)
        }
    }
}
