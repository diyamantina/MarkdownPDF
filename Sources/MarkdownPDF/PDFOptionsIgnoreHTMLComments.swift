import Foundation

public extension PDFOptions {
    /// Drops HTML comments from the Markdown before it is parsed.
    ///
    /// The default value is ``disabled``, which leaves every document exactly as it
    /// was: a comment such as `<!-- note -->` is drawn as visible text, because the
    /// renderer treats it as an HTML block or as inline text. Enabled, every comment
    /// is deleted, so authoring markers that other tools read, such as
    /// `<!--print-only-->`, `<!--/print-only-->`, `<!--say: spoken form-->` and
    /// `<!--audio: file.mp3-->`, do not reach the page. The content between a pair of
    /// markers stays.
    ///
    /// ## Rule
    ///
    /// - A comment starts at `<!--` and ends at the first following `-->`. It may span
    ///   lines and may sit inside a line, a heading, a list item, a table cell or a
    ///   block quote.
    /// - A comment that is never closed is not a comment: its `<!--` is drawn as
    ///   text, so a stray opener cannot hide the rest of the document.
    /// - A line that held only comments disappears, including its newline, so a
    ///   marker on its own line leaves no gap and does not split the paragraph, list
    ///   or table next to it.
    /// - Comments inside fenced code blocks and inline code spans are literal text
    ///   and are kept.
    /// - `<!-- pagebreak -->` (any case, any spacing) is kept, because it is the page
    ///   break marker and not a note.
    ///
    /// The same rule applies to every source of a merged render and to a custom
    /// ``PDFOptions/Colophon`` text.
    struct IgnoreHTMLComments: Equatable, Sendable {
        public var isEnabled: Bool

        public init(isEnabled: Bool) {
            self.isEnabled = isEnabled
        }

        /// Comments are drawn as text, as before.
        public static let disabled = IgnoreHTMLComments(isEnabled: false)

        /// Comments are removed.
        public static let enabled = IgnoreHTMLComments(isEnabled: true)
    }
}
