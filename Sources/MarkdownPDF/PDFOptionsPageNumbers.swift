import Foundation

public extension PDFOptions {
    /// Controls page number footers.
    ///
    /// The default value is ``disabled``. When enabled, each page carries its number
    /// in the bottom margin, in a small size of the document's regular font role
    /// (so embedded-font and bundled DejaVu documents draw it in the same face as
    /// the body). The footer is decoration: it is marked as an artifact when
    /// tagged PDF or a conformance profile is active, and it never enters the body
    /// area. The bottom margin must be at least twice the footer size
    /// (`0.8 * baseFontSize`) or rendering throws
    /// ``MarkdownPDFError/pageNumbersNeedBottomMargin(minimum:actual:)``.
    ///
    /// The same printed numbers appear in the generated table of contents and the
    /// index, so a custom ``firstPageNumber`` or roman ``format`` keeps all three in
    /// agreement. Internal links always target the physical page.
    struct PageNumbers: Equatable, Sendable {
        public var isEnabled: Bool
        public var position: Position
        public var format: Format
        /// The printed number of the first page. Defaults to 1.
        public var firstPageNumber: Int
        /// Leaves the first page without a footer, for example a cover. The first
        /// page still counts: the second page prints `firstPageNumber + 1`.
        public var skipsFirstPage: Bool

        public init(
            isEnabled: Bool,
            position: Position = .bottomCenter,
            format: Format = .plain,
            firstPageNumber: Int = 1,
            skipsFirstPage: Bool = false,
        ) {
            self.isEnabled = isEnabled
            self.position = position
            self.format = format
            self.firstPageNumber = firstPageNumber
            self.skipsFirstPage = skipsFirstPage
        }

        public static let disabled = PageNumbers(isEnabled: false)
        public static let enabled = PageNumbers(isEnabled: true)

        public enum Position: Equatable, Sendable {
            /// Centered between the left and right margins.
            case bottomCenter
            /// On the outside edge of facing pages: the right margin on odd printed
            /// numbers (right-hand pages) and the left margin on even ones.
            case bottomOutside
            /// Aligned to the right margin.
            case bottomRight
        }

        public enum Format: Equatable, Sendable {
            /// `1`
            case plain
            /// `Page 1 of N`, where `N` is the printed number of the last page
            /// (`firstPageNumber + pageCount - 1`). Table of contents and index
            /// references print the plain number.
            case ofTotal
            /// `i`, `ii`, `iii`, for front matter. A number outside `1 ... 3999`
            /// prints as decimal.
            case romanLowercase
        }
    }
}
