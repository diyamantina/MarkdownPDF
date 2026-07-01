import Foundation
import MarkdownPDF

/// macOS renderer entry point reserved for platform-specific PDF generation.
public struct MarkdownPDFMacRenderer: Sendable {
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
