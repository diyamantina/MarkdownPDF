import Foundation

public extension PDFOptions.EmbeddedFonts {
    /// The DejaVu Sans faces bundled with MarkdownPDF.
    ///
    /// The regular, bold, oblique, and monospaced roles are loaded once from the
    /// package resource bundle. If an installation omits those resources, this
    /// value degrades to ``disabled`` and the renderer retains its base-font path.
    static let dejaVu = BundledFonts.dejaVu
}

private enum BundledFonts {
    static let dejaVu: PDFOptions.EmbeddedFonts = {
        guard let bundle = resourceBundle else {
            return .disabled
        }
        do {
            return try PDFOptions.EmbeddedFonts(
                regular: source(named: "DejaVuSans", in: bundle),
                bold: source(named: "DejaVuSans-Bold", in: bundle),
                italic: source(named: "DejaVuSans-Oblique", in: bundle),
                monospaced: source(named: "DejaVuSansMono", in: bundle),
            )
        } catch {
            return .disabled
        }
    }()

    /// The synthesized `Bundle.module` accessor terminates when its resource
    /// bundle is absent. Use it only after proving its preferred path exists, then
    /// fall back to the exact bundle beside a SwiftPM test executable. Loading the
    /// discovered test bundle directly keeps stripped deployments non-fatal.
    private static var resourceBundle: Bundle? {
        let mainURL = Bundle.main.bundleURL.appendingPathComponent(
            moduleBundleName,
            isDirectory: true,
        )
        if Bundle(url: mainURL) != nil {
            return Bundle.module
        }

        for executableURL in swiftPMTestExecutableURLs {
            var root = executableURL
            for _ in 0 ..< 6 {
                let url = root.appendingPathComponent(moduleBundleName, isDirectory: true)
                if let bundle = Bundle(url: url) {
                    return bundle
                }
                root.deleteLastPathComponent()
            }
        }
        return nil
    }

    private static var moduleBundleName: String {
        #if canImport(Darwin)
            "MarkdownPDF_MarkdownPDF.bundle"
        #else
            "MarkdownPDF_MarkdownPDF.resources"
        #endif
    }

    private static var swiftPMTestExecutableURLs: [URL] {
        var paths: [String] = []
        let arguments = CommandLine.arguments
        if let executable = arguments.first,
           executable.split(separator: "/").contains(where: { $0.hasSuffix(".xctest") })
        {
            paths.append(executable)
        }
        for index in arguments.indices where arguments[index] == "--test-bundle-path" {
            let pathIndex = arguments.index(after: index)
            if pathIndex < arguments.endIndex {
                paths.append(arguments[pathIndex])
            }
        }
        return paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) }
    }

    private static func source(
        named name: String,
        in bundle: Bundle,
    ) throws -> PDFOptions.EmbeddedFontSource {
        guard let url = bundle.url(
            forResource: name,
            withExtension: "ttf",
            subdirectory: "Fonts",
        ) else {
            throw BundledFontError.missingResource
        }
        return try PDFOptions.EmbeddedFontSource(
            data: Data(contentsOf: url),
            baseName: name,
        )
    }
}

private enum BundledFontError: Error {
    case missingResource
}
