import Foundation

public extension MarkdownPDF.Render {
    /// A rendered document and what it could not draw.
    struct Output: Equatable, Sendable {
        /// The bytes of the PDF.
        public var data: Data
        /// The characters it could not draw from a face.
        public var report: Report

        public init(data: Data, report: Report) {
            self.data = data
            self.report = report
        }
    }
}
