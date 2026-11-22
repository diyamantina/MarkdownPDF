import Foundation

public enum MarkdownPDFError: Error, Equatable, LocalizedError, Sendable {
    case unreadableImage(String)
    case unsupportedImage(String)
    case invalidImage(String)
    case tableOfContentsDidNotConverge(maxPasses: Int)
    case missingConformanceTitle(profile: String)
    case unembeddedBaseFontsForConformance(profile: String, fonts: [String])
    case missingEmbeddedMathFont(font: String)
    case pageNumbersNeedBottomMargin(minimum: Double, actual: Double)
    case coverImageUnreadable(String)
    case coverImageUnsupported(String)
    case colophonTextEmpty
    case indexTermEmptyForm(term: String)
    /// The page holds characters that no embedded face draws, and ``PDFOptions/undrawnCharacters`` is `.fail`.
    case undrawnCharacters(MarkdownPDF.Render.Report)

    public var errorDescription: String? {
        switch self {
        case let .unreadableImage(path):
            "Could not read image at \(path)."
        case let .unsupportedImage(path):
            "Unsupported image format at \(path). Supported formats are JPEG and PNG."
        case let .invalidImage(path):
            "Invalid image data at \(path)."
        case let .tableOfContentsDidNotConverge(maxPasses):
            "Generated table of contents and index page numbers did not converge after \(maxPasses) layout passes."
        case let .missingConformanceTitle(profile):
            "\(profile) output requires a non-empty document title."
        case let .unembeddedBaseFontsForConformance(profile, fonts):
            "\(profile) output requires embedded font programs for every rendered font role. Missing roles: \(fonts.joined(separator: ", "))."
        case let .missingEmbeddedMathFont(font):
            "Math typesetting requires an embedded OpenType MATH font for \(font)."
        case let .pageNumbersNeedBottomMargin(minimum, actual):
            "Page numbers need a bottom margin of at least \(minimum) points, but the margin is \(actual)."
        case let .coverImageUnreadable(path):
            "Could not read the cover image at \(path)."
        case let .coverImageUnsupported(source):
            "The cover image (\(source)) is not a decodable PNG or JPEG."
        case .colophonTextEmpty:
            "The colophon is enabled with custom text that is empty."
        case let .indexTermEmptyForm(term):
            "The index term \"\(term)\" has an empty form between its pipes."
        case let .undrawnCharacters(report):
            Self.undrawnDescription(report)
        }
    }

    private static func undrawnDescription(_ report: MarkdownPDF.Render.Report) -> String {
        let shown = report.undrawn.prefix(8).map { entry in
            "\(entry.text) (" + entry.codePoints.map { "U+" + String($0, radix: 16, uppercase: true) }.joined(separator: " ") + ")"
        }
        let more = report.undrawn.count > shown.count ? " and \(report.undrawn.count - shown.count) more" : ""
        let reasons = Set(report.undrawn.map(\.reason))
        var text = "\(report.undrawn.count) character(s) are not drawn from a face: \(shown.joined(separator: ", "))\(more)."
        if reasons.contains(.bundledFacesUnavailable) {
            text += " The bundled faces are unavailable: the resource bundle MarkdownPDF_MarkdownPDF.bundle is missing from the deployment."
        }
        return text
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
            "Reduce pagination churn around headings or render without a generated table of contents or index."
        case .missingConformanceTitle:
            "Pass PDFOptions(title:) when enabling the conformance profile."
        case .unembeddedBaseFontsForConformance:
            "Pass PDFOptions(embeddedFonts:) with font data for every Markdown role used by the document."
        case .pageNumbersNeedBottomMargin:
            "Increase PDFOptions.margins.bottom or disable page numbers."
        case .coverImageUnreadable:
            "Confirm the cover image path exists and is relative to the base URL given to PDFOptions.Cover, or pass the image bytes with ImageSource.data."
        case .coverImageUnsupported:
            "Use a valid PNG or JPEG file for the cover image."
        case .colophonTextEmpty:
            "Give PDFOptions.Colophon some Markdown text, or leave the text nil for the default colophon."
        case .indexTermEmptyForm:
            "Remove the stray pipe, or write a literal pipe as \\| inside a form."
        case .undrawnCharacters:
            "Ship the resource bundle MarkdownPDF_MarkdownPDF.bundle beside the executable, give the faces in PDFOptions(embeddedFonts:), or leave PDFOptions.undrawnCharacters at .report and read the list."
        case .missingEmbeddedMathFont:
            "Pass PDFOptions(embeddedFonts:) with TrueType math-font data that contains an OpenType MATH table, or use PDFOptions.MathTypesetting.enabled for fallback rendering."
        }
    }
}
