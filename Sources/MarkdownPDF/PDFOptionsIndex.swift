import Foundation

public extension PDFOptions {
    /// Controls the back-of-book index appended after the last page of content.
    ///
    /// The default value is ``disabled``. Entries come from two sources, merged by
    /// case and diacritic-insensitive term:
    ///
    /// - The inline marker `{{index: term}}` (and `{{index: main > sub}}` for a
    ///   sub-entry). It renders nothing and records the page it lands on. A marker
    ///   whose term is empty after trimming is ignored: it renders nothing and
    ///   records nothing. Markers are recognized only while the index is enabled;
    ///   with the index disabled the text stays literal. Markers inside code
    ///   blocks and inline code are literal text.
    /// - ``terms``, found by whole-word, case-insensitive match in paragraphs, list
    ///   items, table cells, block quotes, and headings, and recorded for each page
    ///   they occur on. Code, inline code, math, link destinations, the table of
    ///   contents, and the index itself are not searched. A term may list variant
    ///   forms separated by pipes, such as `flattening|flatten|flattened`: the first
    ///   form is the heading, and a page holding any form is listed once under it.
    ///   See ``Term`` for the rules, including `\|` for a literal pipe.
    ///
    /// The index is sorted with a stable fold that does not depend on the platform
    /// locale (see ``PDFOptions/Index``'s documentation page), grouped under letter
    /// headings, lists page numbers as internal links with consecutive pages
    /// collapsed to ranges such as `12-14`, and indents sub-entries. Its heading is
    /// an ordinary level-one heading, so it appears in the outline and in the table
    /// of contents. When no entry is found, no index is written.
    struct Index: Equatable, Sendable {
        public var isEnabled: Bool
        public var title: String
        /// Terms to find and list, each a pipe-separated string of forms (see ``Term``).
        /// A string without a pipe is one literal whole word or phrase.
        public var terms: [String]

        public init(
            isEnabled: Bool,
            title: String = "Index",
            terms: [String] = [],
        ) {
            self.isEnabled = isEnabled
            self.title = title
            self.terms = terms
        }

        public static let disabled = Index(isEnabled: false)
        public static let enabled = Index(isEnabled: true)
    }
}
