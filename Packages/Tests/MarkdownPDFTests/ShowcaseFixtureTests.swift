import Foundation
@testable import MarkdownPDF
import Testing

/// Renders the diverse showcase corpus (multilingual prose, TeX math, native
/// charts, Mermaid diagrams, mixed-script tables) with an embedded font and the
/// full visual witness battery, and renders the large handbook across popular
/// page formats. See #198 and #199.
@Suite("Showcase corpus")
struct ShowcaseFixtureTests {
    @Test(
        .enabled(if: OpenTrueTypeFontFixture.isAvailable, OpenTrueTypeFontFixture.skipReason),
        arguments: ShowcaseFixtureTests.fixtureNames,
    )
    func rendersShowcaseFixtureWithEmbeddedFont(_ fixtureName: String) throws {
        let fontURL = try #require(OpenTrueTypeFontFixture.url)
        let source = try PDFOptions.EmbeddedFontSource(data: Data(contentsOf: fontURL))
        let markdown = try String(contentsOf: Self.showcaseDirectory.appendingPathComponent(fixtureName), encoding: .utf8)

        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                embeddedFonts: .allRoles(source),
                title: fixtureName,
                mathTypesetting: .enabled,
            ),
        ).render(markdown: markdown)

        let base = (fixtureName as NSString).deletingPathExtension
        try assertEmbeddedFontVisualWitness(
            data,
            name: "showcase-\(base)",
            expectedSubstrings: [],
            minWords: 20,
        )
    }

    struct PageFormat: CustomStringConvertible {
        let name: String
        let size: PDFOptions.PageSize
        var description: String {
            name
        }
    }

    @Test(
        .enabled(if: OpenTrueTypeFontFixture.isAvailable, OpenTrueTypeFontFixture.skipReason),
        arguments: ShowcaseFixtureTests.pageFormats,
    )
    func rendersGrandHandbookAcrossPageFormats(_ format: PageFormat) throws {
        let fontURL = try #require(OpenTrueTypeFontFixture.url)
        let source = try PDFOptions.EmbeddedFontSource(data: Data(contentsOf: fontURL))
        let markdown = try String(
            contentsOf: Self.showcaseDirectory.appendingPathComponent("08-grand-handbook.md"),
            encoding: .utf8,
        )

        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: format.size,
                embeddedFonts: .allRoles(source),
                title: "Grand handbook \(format.name)",
                mathTypesetting: .enabled,
            ),
        ).render(markdown: markdown)

        let name = "showcase-formats/grand-handbook-\(format.name)"
        try PDFValidation.writeArtifact(data, name: "\(name).pdf")
        let url = try PDFValidation.temporaryPDF(name: name.replacingOccurrences(of: "/", with: "-"), data: data)

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "\(name): qpdf --check failed:\n\(qpdf.output)")

        let tsv = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsv.exitCode == 0, "\(name): pdftotext -tsv failed:\n\(tsv.output)")
        let layout = try PopplerTextLayout(tsv: tsv.output)
        let issues = layout.visualLayoutIssues()
        #expect(layout.pages.count >= 8, "\(name): expected a multi-page handbook, got \(layout.pages.count) pages")
        #expect(issues.isEmpty, "\(name): word-box layout issues:\n\(issues.joined(separator: "\n"))")
    }

    private static let showcaseDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/showcase")

    static let fixtureNames: [String] = {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: showcaseDirectory,
            includingPropertiesForKeys: nil,
        )) ?? []
        return urls
            .filter { $0.pathExtension == "md" }
            .map(\.lastPathComponent)
            .sorted()
    }()

    static let pageFormats: [PageFormat] = [
        PageFormat(name: "us-letter", size: .letter),
        PageFormat(name: "legal", size: .legal),
        PageFormat(name: "tabloid", size: .tabloid),
        PageFormat(name: "a3", size: .a3),
        PageFormat(name: "a5", size: .a5),
    ]
}
