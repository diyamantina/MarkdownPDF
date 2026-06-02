import Foundation

public enum MarkdownPDFError: Error, Equatable, LocalizedError, Sendable {
    case unreadableImage(String)
    case unsupportedImage(String)
    case invalidImage(String)
    case tableOfContentsDidNotConverge(maxPasses: Int)
    case missingConformanceTitle(profile: String)
    case unembeddedBaseFontsForConformance(profile: String, fonts: [String])

    public var errorDescription: String? {
        switch self {
        case let .unreadableImage(path):
            "Could not read image at \(path)."
        case let .unsupportedImage(path):
            "Unsupported image format at \(path). Supported formats are JPEG and PNG without interlaced alpha."
        case let .invalidImage(path):
            "Invalid image data at \(path)."
        case let .tableOfContentsDidNotConverge(maxPasses):
            "Generated table of contents page numbers did not converge after \(maxPasses) layout passes."
        case let .missingConformanceTitle(profile):
            "\(profile) output requires a non-empty document title."
        case let .unembeddedBaseFontsForConformance(profile, fonts):
            "\(profile) output requires embedded font programs for every rendered font role. Missing roles: \(fonts.joined(separator: ", "))."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unreadableImage:
            "Confirm the image path is relative to the input document or pass the correct assetsBaseURL."
        case .unsupportedImage:
            "Use a local JPEG or PNG image supported by MarkdownPDF."
        case .invalidImage:
            "Replace the image with valid JPEG or PNG data."
        case .tableOfContentsDidNotConverge:
            "Reduce pagination churn around headings or render without a generated table of contents."
        case .missingConformanceTitle:
            "Pass PDFOptions(title:) when enabling the conformance profile."
        case .unembeddedBaseFontsForConformance:
            "Pass PDFOptions(embeddedFonts:) with font data for every Markdown role used by the document."
        }
    }
}
