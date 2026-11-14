import Foundation

public extension PDFOptions {
    /// What the layout keeps on one page instead of breaking it where the page ends.
    ///
    /// By default a page breaks wherever the text reaches the bottom margin, so a
    /// list item can start on one page and end on the next. Each member names a unit
    /// that is moved to the top of the next page, whole, when it does not fit in what
    /// is left of the current page but does fit on a page of its own. A unit taller
    /// than a page cannot be kept and breaks as it does by default.
    ///
    /// The default value is empty, which lays every document out as before, byte for
    /// byte. A document in which no unit meets the end of a page also renders the
    /// same bytes with any member set.
    ///
    /// Keeping units together leaves the space they did not fit in empty, so a
    /// document can grow by pages.
    struct KeepTogether: OptionSet, Equatable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// A list item: its marker and everything in it, nested lists included. A
        /// heading directly above a list stays with the list's first item.
        public static let listItems = KeepTogether(rawValue: 1 << 0)

        /// A heading and the blocks under it, up to the next heading of any level.
        /// A section too tall for one page is not kept, and its list items still are
        /// when ``listItems`` is set too. A section that holds the table of contents
        /// is never kept. Only headings at the top level of a document start a
        /// section, not headings inside a list item or a block quote.
        public static let sections = KeepTogether(rawValue: 1 << 1)
    }
}
