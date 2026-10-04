import Foundation

public extension PDFOptions {
    /// A full-page cover: physical page 1 of the PDF, drawn before everything else.
    ///
    /// The default value is ``disabled``. When enabled, the first page shows one
    /// image (PNG or JPEG, decoded exactly like a Markdown body image, so an RGBA
    /// PNG is composited through its soft mask) and nothing else: no margins, no
    /// text, no footer.
    ///
    /// ## Fit rule
    ///
    /// The image is scaled by `min(pageWidth / imageWidth, pageHeight / imageHeight)`,
    /// so the whole picture is visible and its aspect ratio is kept, and it is
    /// centred. It is scaled up as well as down. The page margins and
    /// ``PDFOptions/imageMaxHeightFraction`` do not apply. When the two aspect ratios
    /// differ by at most 0.1%, which is the case for an image cut to the page's own
    /// proportions (a portrait A4 image of 1 : 1.4142 against A4's 1 : 1.41421), the
    /// image is stretched by that imperceptible amount to fill the page exactly, so no
    /// hairline of paper shows at an edge. Otherwise the unused strip is split evenly
    /// on both sides of the short dimension and shows the page background: white, or
    /// the theme's ``PDFOptions/Theme/pageBackground`` when it has one. Transparent
    /// pixels show that same background.
    ///
    /// ## Numbering
    ///
    /// The cover carries no page number. The first page after it is printed page 1 (or
    /// ``PageNumbers/firstPageNumber``), `Page N of M` counts the pages after the
    /// cover only, and ``PageNumbers/skipsFirstPage`` refers to the first page after
    /// the cover. The table of contents and the index print those printed numbers
    /// when page numbers are enabled, and physical page numbers (the cover counts as
    /// page 1) when they are not. Links, named destinations and the outline always
    /// address physical pages. The cover is the first outline item, titled "Cover",
    /// and is not a table of contents entry.
    ///
    /// ## Accessibility
    ///
    /// With tagged PDF or a conformance profile, the cover is a Figure whose alternate
    /// text is built from ``PDFOptions/title`` and ``PDFOptions/author``: "Cover of
    /// Title by Author", "Cover of Title", "Cover by Author", or "Cover".
    ///
    /// ## Errors
    ///
    /// Rendering throws ``MarkdownPDFError/coverImageUnreadable(_:)`` for a file that
    /// cannot be read and ``MarkdownPDFError/coverImageUnsupported(_:)`` for bytes that
    /// are not a decodable PNG or JPEG. A cover is never skipped silently.
    struct Cover: Equatable, Sendable {
        /// The picture, or nil when there is no cover.
        public var image: ImageSource?

        public init(image: ImageSource? = nil) {
            self.image = image
        }

        /// No cover page.
        public static let disabled = Cover()

        /// A cover showing `image`.
        public static func enabled(image: ImageSource) -> Cover {
            Cover(image: image)
        }

        /// True when a cover page is drawn.
        public var isEnabled: Bool {
            image != nil
        }

        /// Where the cover picture comes from. Both forms are values, so the renderer
        /// reads nothing it was not handed: the caller supplies the bytes, or names a
        /// file together with the folder it is relative to.
        public enum ImageSource: Equatable, Sendable {
            /// The bytes of a PNG or JPEG file.
            case data(Data)
            /// A file path, read when the document is rendered. A relative path
            /// resolves against `baseURL`, or the current working directory when
            /// that is nil. An absolute path and a `file:` URL are used as given.
            case file(_ path: String, relativeTo: URL? = nil)
        }
    }
}
