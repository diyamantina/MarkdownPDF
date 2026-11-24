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
        // The witness holds every word inside its page. The line chart "Temps de
        // rendu" of `05-charts-dashboard.md` once drew the tick label "20" past the
        // right edge of the page, and the witness recorded it as a known issue.
        try assertEmbeddedFontVisualWitness(
            data,
            name: "showcase-\(base)",
            expectedSubstrings: Self.expectedSubstrings[fixtureName] ?? [base],
            minWords: 20,
        )

        // Every chart of the showcase is a block of its own, so its frame runs from
        // 4 points left of the left margin to 4 points right of the right margin.
        // Chart text is the only text set at the chart label size: each such run
        // lies inside that frame. The count guards against a pass that saw no label.
        let options = PDFOptions()
        let frame = ChartTickLabelKey.frame(
            pageWidth: options.pageSize.width,
            marginLeft: options.margins.left,
            marginRight: options.margins.right,
        )
        let labels = try PDFDocumentReader(data: data).pages.flatMap(\.runs).filter {
            abs($0.fontSize - ChartTickLabelKey.labelSize) < 0.001 && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
        for label in labels {
            #expect(
                label.x >= frame.lowerBound - 0.01 && label.x + label.width <= frame.upperBound + 0.01,
                Comment(rawValue: "chart label '\(label.text)' at \(label.x)...\(label.x + label.width) leaves the chart frame \(frame)"),
            )
        }
        if fixtureName == "05-charts-dashboard.md" {
            // Measured on 2026-11-24, printed by the line below: 40 chart labels in this fixture. The floor is the
            // measured number, so a filter that finds no label cannot pass.
            print("ShowcaseFixtureTests: \(labels.count) chart labels in \(fixtureName)")
            #expect(labels.count >= 40)
        }
    }

    /// The raster step the embedded-font witness ended with for every showcase
    /// fixture: two outside rasterizers drew each page and their ink had to agree.
    @Test(
        "Every page of a showcase fixture rasterizes to comparable ink",
        .disabled("not verified: needs a rasterizer inside MarkdownPDF, see Docs/NOT-VERIFIED.md"),
        arguments: ShowcaseFixtureTests.fixtureNames,
    )
    func rasterWitness(_ fixtureName: String) {
        PDFValidation.notVerified("the raster of \(fixtureName)")
    }

    /// Guards against a silent zero-case pass: if the fixture glob breaks (wrong
    /// path, bad working directory), the parameterized test above would run no
    /// cases and report success. This asserts the corpus is actually present.
    @Test
    func showcaseCorpusIsDiscovered() {
        #expect(
            Self.fixtureNames.count >= 8,
            "Expected at least 8 showcase fixtures, found \(Self.fixtureNames.count): \(Self.fixtureNames)",
        )
        #expect(Self.fixtureNames.contains("08-grand-handbook.md"))
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

        try PDFValidation.requireSoundStructure(data, name: name)

        let layout = try ReaderTextLayout(data: data)
        let issues = layout.visualLayoutIssues()
        #expect(layout.pages.allSatisfy { $0 == format.size }, "\(name): a page is not \(format.size)")
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

    /// Representative tokens per fixture (multilingual where possible) so the
    /// witness asserts the real content round-tripped through the embedded font,
    /// not merely that some words extracted.
    static let expectedSubstrings: [String: [String]] = [
        "01-combined-showcase.md": ["café", "Привет", "Καλημέρα"],
        "02-scientific-article.md": ["café", "Привет", "Καλημέρα"],
        "03-multilingual-gazette.md": ["Zürich", "Привет", "Καλημέρα"],
        "04-math-handbook.md": ["Légende", "Подпись", "Euler"],
        "05-charts-dashboard.md": ["Tableau", "Панель"],
        "06-engineering-rfc.md": ["Terminology", "FontDescriptor"],
        "07-changelog-and-readme.md": ["Changelog", "café", "Привет"],
        "08-grand-handbook.md": ["café", "Привет", "Καλημέρα"],
    ]

    static let pageFormats: [PageFormat] = [
        PageFormat(name: "us-letter", size: .letter),
        PageFormat(name: "legal", size: .legal),
        PageFormat(name: "tabloid", size: .tabloid),
        PageFormat(name: "a3", size: .a3),
        PageFormat(name: "a5", size: .a5),
    ]
}
