import Foundation
import MarkdownPDF

/// Portable renderer entry point for Linux-compatible PDF generation.
public struct MarkdownPDFLinuxRenderer: Sendable {
    public var options: PDFOptions

    public init(options: PDFOptions = PDFOptions()) {
        self.options = options
    }

    public func render(
        markdown: String,
        assetsBaseURL: URL? = nil,
    ) throws -> Data {
        try MarkdownPDFRenderer(options: options).render(
            markdown: markdown,
            assetsBaseURL: assetsBaseURL,
        )
    }
}
