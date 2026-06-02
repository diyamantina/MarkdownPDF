import Foundation
import MarkdownPDF
import Testing

#if canImport(MarkdownPDFMac)
    import MarkdownPDFMac
#endif

@Suite("Fixtures")
struct FixtureTests {
    @Test("Public fixtures are anonymized")
    func publicFixturesAreAnonymized() throws {
        let forbiddenIdentifiers = [
            "Mihaela",
            "Mihaljevic",
            "Mihaljević",
            "Jakic",
            "Jakić",
            "mihaelamj",
            "aleahim",
            "diyamantina",
            "+385",
            "Zagreb",
            "Croatia",
            "Maurer",
            "Bundesdruckerei",
            "Code Weaver",
            "Everliv",
            "iOLAP",
            "iRobot",
            "Zumiez",
            "Cherishing",
            "Budtz",
            "Birch",
            "Wheels Up",
            "Masinerija",
            "Purch",
            "Undabot",
            "Cupertino",
            "iRelay",
            "OpenAPIDoctor",
            "ExtremePackaging",
            "OpenAPILoggingMiddleware",
            "CVBuilder",
            "iOSKonf",
            "NSSpain",
            "Skopje",
            "Logrono",
            "Logroño",
        ]

        for fixtureName in publicFixtureNames {
            let fixture = try fixture(named: fixtureName)
            for identifier in forbiddenIdentifiers {
                #expect(!fixture.localizedCaseInsensitiveContains(identifier))
            }
        }
    }

    @Test("Renders demo CV fixture")
    func rendersDemoCVFixture() throws {
        let fixture = try demoCVFixture()
        let data = try MarkdownPDFRenderer().render(markdown: fixture)
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.hasPrefix("%PDF-1.4"))
        #expect(text.contains("/BaseFont /Helvetica"))
        #expect(text.contains("/Type /Page"))
        #expect(text.contains("xref"))
    }

    @Test("Renders article-grade fixtures with valid PDF structure")
    func rendersArticleGradeFixtures() throws {
        for fixtureName in articleGradeFixtureNames {
            let data = try renderArticleFixture(named: fixtureName)
            let inspector = PDFInspector(data)

            #expect(inspector.text.hasPrefix("%PDF-1.4"))
            #expect(inspector.text.contains("/BaseFont /Helvetica"))
            #expect(!inspector.text.contains("/FontFile"))
            #expect(inspector.pageCount >= expectedMinimumPageCount(for: fixtureName))
            #expect(inspector.hasValidXrefOffsets())
            #expect(inspector.streamLengthsMatch())
            #expect(
                inspector.canonicalStructureIssues().isEmpty,
                "Canonical PDF structure failed for \(fixtureName):\n\(inspector.canonicalStructureReport())",
            )

            let qpdf = try PDFValidation.qpdfCheck(data: data, name: fixtureName)
            #expect(qpdf.exitCode == 0, "qpdf --check failed for \(fixtureName):\n\(qpdf.output)")

            let infoResult = try PDFValidation.pdfinfo(data: data, name: fixtureName)
            let info = PDFValidation.parsedInfo(from: infoResult)
            #expect(infoResult.exitCode == 0, "pdfinfo failed for \(fixtureName):\n\(infoResult.output)")
            #expect(info["PDF version"] == "1.4", "Unexpected pdfinfo output for \(fixtureName):\n\(infoResult.output)")
            #expect(info["Pages"] == "\(inspector.pageCount)", "Unexpected pdfinfo output for \(fixtureName):\n\(infoResult.output)")

            let textResult = try PDFValidation.pdftotext(data: data, name: fixtureName)
            #expect(textResult.exitCode == 0, "pdftotext failed for \(fixtureName):\n\(textResult.output)")
            #expect(
                textResult.output.contains(expectedTextFragment(for: fixtureName)),
                "Unexpected pdftotext output for \(fixtureName):\n\(textResult.output)",
            )

            let render = try PDFValidation.pdftoppmPNG(data: data, name: fixtureName)
            let pngData = try? Data(contentsOf: render.pngURL)
            let dimensions = PDFValidation.pngDimensions(in: pngData)
            #expect(render.result.exitCode == 0, "pdftoppm failed for \(fixtureName):\n\(render.result.output)")
            #expect(dimensions != nil)
            #expect((dimensions?.width ?? 0) > 0)
            #expect((dimensions?.height ?? 0) > 0)
        }
    }

    @Test("Article stress fixture covers ToC, images, fallback, raw HTML, and Mermaid")
    func articleStressFixtureCoversPortableArticleFeatures() throws {
        let data = try renderArticleFixture(named: "article-grade-stress.md")
        let inspector = PDFInspector(data)
        let textResult = try PDFValidation.pdftotext(data: data, name: "article-grade-stress-features")
        try #require(textResult.exitCode == 0, "pdftotext failed for article-grade stress fixture:\n\(textResult.output)")
        let extractedText = textResult.output

        #expect(inspector.pageCount >= 6)
        #expect(inspector.linkAnnotationCount >= 2)
        #expect(inspector.text.contains("/Names << /Dests"))
        #expect(inspector.text.contains("/Subtype /Image"))
        #expect(inspector.text.contains("/Width 96"))
        #expect(inspector.text.contains("/Height 48"))
        #expect(inspector.text.contains("/FlateDecode"))
        #expect(extractedText.contains("Table of Contents"))
        #expect(extractedText.contains("[Remote image: Remote measurement plot]"))
        #expect(extractedText.contains("Raw HTML fallback"))
        #expect(extractedText.contains("Markdown source"))
        #expect(extractedText.contains("Open tool witnesses"))
        #expect(!extractedText.contains("Unsupported Mermaid diagram"))
        #expect(!extractedText.contains("flowchart TD"))
    }

    @Test("Hard Markdown fixture covers dense portable Markdown features")
    func hardMarkdownFixtureCoversDensePortableMarkdownFeatures() throws {
        let data = try renderArticleFixture(named: "hard-markdown-corpus.md")
        let inspector = PDFInspector(data)
        let textResult = try PDFValidation.pdftotext(data: data, name: "hard-markdown-corpus-features")
        try #require(textResult.exitCode == 0, "pdftotext failed for hard Markdown fixture:\n\(textResult.output)")
        let extractedText = textResult.output
        let normalizedText = normalizedExtractedText(extractedText)

        #expect(inspector.pageCount >= 8)
        #expect(inspector.linkAnnotationCount >= 4)
        #expect(inspector.text.contains("/Names << /Dests"))
        #expect(inspector.text.contains("/Subtype /Image"))
        #expect(inspector.text.contains("/Width 96"))
        #expect(inspector.text.contains("/Height 48"))
        #expect(inspector.text.contains("/FlateDecode"))
        #expect(extractedText.contains("Table of Contents"))
        #expect(normalizedText.contains("Portable Hard Markdown Corpus"))
        #expect(normalizedText.contains("Raw HTML fallback for the hard corpus"))
        #expect(extractedText.contains("[Remote image: Remote hard corpus figure]"))
        #expect(normalizedText.contains("Hard input"))
        #expect(normalizedText.contains("Open tools"))
        #expect(extractedText.contains("Unsupported Mermaid diagram"))
        #expect(normalizedText.contains("Unsupported hard corpus chart"))
        #expect(normalizedText.contains("Hard Fixture Exit Marker"))
        #expect(!extractedText.contains("Source[Hard input]"))
    }

    @Test("A4 manuscript fixture covers manuscript-scale portable Markdown")
    func a4ManuscriptFixtureCoversManuscriptScalePortableMarkdown() throws {
        let data = try renderArticleFixture(named: "a4-manuscript.md")
        let inspector = PDFInspector(data)
        let infoResult = try PDFValidation.pdfinfo(data: data, name: "a4-manuscript-features")
        try #require(infoResult.exitCode == 0, "pdfinfo failed for A4 manuscript fixture:\n\(infoResult.output)")
        let info = PDFValidation.parsedInfo(from: infoResult)
        let textResult = try PDFValidation.pdftotext(data: data, name: "a4-manuscript-features")
        try #require(textResult.exitCode == 0, "pdftotext failed for A4 manuscript fixture:\n\(textResult.output)")
        let extractedText = textResult.output
        let normalizedText = normalizedExtractedText(extractedText)

        #expect(inspector.pageCount >= 5)
        #expect(info["Page size"]?.contains("595.28 x 841.89 pts") == true)
        #expect(inspector.linkAnnotationCount >= 3)
        #expect(inspector.text.contains("/Names << /Dests"))
        #expect(inspector.text.contains("/Subtype /Image"))
        #expect(inspector.text.contains("/Width 96"))
        #expect(inspector.text.contains("/Height 48"))
        #expect(inspector.text.contains("/FlateDecode"))
        #expect(extractedText.contains("Table of Contents"))
        #expect(normalizedText.contains("Portable A4 Manuscript Fixture"))
        #expect(normalizedText.contains("A4 local chart"))
        #expect(extractedText.contains("[Remote image: Remote A4 figure]"))
        #expect(normalizedText.contains("Manuscript source"))
        #expect(normalizedText.contains("Open witnesses"))
        #expect(extractedText.contains("Unsupported Mermaid diagram"))
        #expect(extractedText.contains("Unsupported A4 manuscript chart"))
        #expect(normalizedText.contains("A4 Manuscript Exit Marker"))
        #expect(!extractedText.contains("Manuscript[Manuscript source]"))
        #expect(!extractedText.contains("Writer[PDF writer]"))
    }

    @Test("US patent fixture renders complete local image corpus")
    func usPatentFixtureRendersCompleteLocalImageCorpus() throws {
        try assertExternalFixtureRenders(
            directory: "us-patent-8130226",
            title: "US Patent 8130226",
            expectedTitle: "US Patent 8,130,226",
            expectedFragments: [
                "Framework for Graphics Animation and Compositing Operations",
                "Claim 17 adds that performing comprises using directional information",
            ],
            expectedImageReferences: 23,
            minimumPageCount: 20,
            minimumPDFBytes: 1_000_000,
        )
    }

    @Test("WWDC ray tracing fixture renders optimized large local asset corpus")
    func wwdcRayTracingFixtureRendersOptimizedLargeLocalAssetCorpus() throws {
        let sourceMarkdown = try fixture(named: "\(wwdcFixtureDirectory)/README.md")
        let markdown = selectedLocalImageFixtureMarkdown(
            from: sourceMarkdown,
            allowedAssetNames: wwdcOptimizedAssetNames,
            lineLimit: 223,
            marker: "WWDC Ray Tracing Fixture Excerpt Marker",
        )

        try assertExternalFixtureRenders(
            directory: wwdcFixtureDirectory,
            title: "WWDC 2019 Session 613 Ray Tracing with Metal",
            expectedTitle: "WWDC 2019 Session 613: Ray Tracing with Metal",
            markdown: markdown,
            expectedFragments: [
                "MPSRayIntersector",
                "Now builds on the GPU",
                "Putting the Pipeline Together",
                "WWDC Ray Tracing Fixture Excerpt Marker",
            ],
            expectedImageReferences: 13,
            minimumPageCount: 10,
            minimumPDFBytes: 4_000_000,
        )
    }

    @Test("WWDC large fixture renders selected oversized assets when enabled")
    func wwdcLargeFixtureRendersSelectedOversizedAssetsWhenEnabled() throws {
        guard largeFixtureStressTestsEnabled() else {
            return
        }

        let artifactName = "wwdc-2019-613-ray-tracing-with-metal-large-stress"
        let sourceMarkdown = try fixture(named: "\(wwdcFixtureDirectory)/README.md")
        let markdown = selectedLocalImageFixtureMarkdown(
            from: sourceMarkdown,
            allowedAssetNames: wwdcLargeStressAssetNames,
            marker: "WWDC Ray Tracing Large Fixture Stress Marker",
        )
        let data = try MarkdownPDFRenderer(
            options: externalFixtureOptions(title: "WWDC 2019 Session 613 Ray Tracing with Metal Large Stress"),
        ).render(
            markdown: markdown,
            assetsBaseURL: externalFixtureAssetsBaseURL(directory: wwdcFixtureDirectory),
        )
        let url = try PDFValidation.temporaryPDF(name: artifactName, data: data)

        try PDFValidation.writeArtifact(data, name: "\(artifactName).pdf")
        #expect(data.count > 35_000_000)
        #expect(localImageReferenceCount(in: markdown) == wwdcLargeStressAssetNames.count)

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        #expect(qpdf.exitCode == 0, "qpdf --check failed for \(artifactName):\n\(qpdf.output)")

        let infoResult = try PDFValidation.pdfinfo(url: url)
        let info = PDFValidation.parsedInfo(from: infoResult)
        #expect(infoResult.exitCode == 0, "pdfinfo failed for \(artifactName):\n\(infoResult.output)")
        #expect((Int(info["Pages"] ?? "") ?? 0) >= 25, "Unexpected pdfinfo output for \(artifactName):\n\(infoResult.output)")
        #expect(info["Page size"]?.contains("595.28 x 841.89 pts") == true)

        let textResult = try PDFValidation.pdftotext(url: url)
        #expect(textResult.exitCode == 0, "pdftotext failed for \(artifactName):\n\(textResult.output)")
        let normalizedText = normalizedExtractedText(textResult.output)
        #expect(normalizedText.contains("WWDC 2019 Session 613: Ray Tracing with Metal"))
        #expect(normalizedText.contains("MPSRayIntersector"))
        #expect(normalizedText.contains("WWDC Ray Tracing Large Fixture Stress Marker"))

        let render = try PDFValidation.pdftoppmPNG(url: url)
        let pngData = try? Data(contentsOf: render.pngURL)
        let dimensions = PDFValidation.pngDimensions(in: pngData)
        #expect(render.result.exitCode == 0, "pdftoppm failed for \(artifactName):\n\(render.result.output)")
        #expect(dimensions != nil)
        #expect((dimensions?.width ?? 0) > 0)
        #expect((dimensions?.height ?? 0) > 0)
    }

    @Test("Formidabble fixture renders code-heavy manuscript")
    func formidabbleFixtureRendersCodeHeavyManuscript() throws {
        try assertExternalMarkdownFixtureRenders(
            fixtureName: "formidabble.md",
            title: "Formidabble",
            artifactName: "formidabble",
            expectedFragments: [
                "Formidabble",
                "Clean Architecture",
                "Actor-Based Concurrency",
                "Dependency Injection",
            ],
            minimumPageCount: 10,
            minimumPDFBytes: 100_000,
        )
    }

    @Test("App Intents fixture renders framework manuscript")
    func appIntentsFixtureRendersFrameworkManuscript() throws {
        try assertExternalMarkdownFixtureRenders(
            fixtureName: "appintents.md",
            title: "App Intents Voice Data Manuscript",
            artifactName: "appintents",
            expectedFragments: [
                "Voice Input and Understanding",
                "Speech-to-Text Transcription",
                "App Intents framework",
                "MailKit",
                "Tool Calling",
            ],
            minimumPageCount: 5,
            minimumPDFBytes: 75000,
        )
    }

    @Test("Scientific article fixture covers links, image fallback, and Mermaid")
    func scientificArticleFixtureCoversLinksImageFallbackAndMermaid() throws {
        let data = try MarkdownPDFRenderer().render(markdown: fixture(named: "scientific-article.md"))
        let inspector = PDFInspector(data)
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")

        #expect(inspector.linkAnnotationCount >= 1)
        #expect(inspector.text.contains("/URI (https://example.com/research/layout-measurements)"))
        #expect(streamText.contains("([Remote )"))
        #expect(streamText.contains("(image: )"))
        #expect(streamText.contains("(Markdown )"))
        #expect(streamText.contains("(source)"))
        #expect(streamText.contains("(PDF )"))
        #expect(streamText.contains("(bytes)"))
        #expect(!streamText.contains("(flowchart TD)"))
    }

    #if canImport(MarkdownPDFMac)
        @Test("Mac product renders scientific article fixture")
        func macProductRendersScientificArticleFixture() throws {
            let data = try MarkdownPDFMacRenderer().render(markdown: fixture(named: "scientific-article.md"))
            let inspector = PDFInspector(data)

            #expect(inspector.text.hasPrefix("%PDF-1.4"))
            #expect(!inspector.text.contains("/FontFile"))
            #expect(inspector.hasValidXrefOffsets())
            #expect(inspector.streamLengthsMatch())
        }
    #endif

    private func demoCVFixture() throws -> String {
        try fixture(named: "democv.md")
    }

    private func fixture(named name: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }

    private func renderArticleFixture(named fixtureName: String) throws -> Data {
        try MarkdownPDFRenderer(options: articleFixtureOptions(for: fixtureName)).render(
            markdown: fixture(named: fixtureName),
            assetsBaseURL: articleFixtureAssetsBaseURL(for: fixtureName),
        )
    }

    private func assertExternalFixtureRenders(
        directory: String,
        title: String,
        expectedTitle: String,
        markdown providedMarkdown: String? = nil,
        artifactName providedArtifactName: String? = nil,
        expectedFragments: [String],
        expectedImageReferences: Int,
        minimumPageCount: Int,
        minimumPDFBytes: Int,
    ) throws {
        let markdown: String = if let providedMarkdown {
            providedMarkdown
        } else {
            try fixture(named: "\(directory)/README.md")
        }
        let artifactName = providedArtifactName ?? directory
        let data = try MarkdownPDFRenderer(options: externalFixtureOptions(title: title)).render(
            markdown: markdown,
            assetsBaseURL: externalFixtureAssetsBaseURL(directory: directory),
        )
        let inspector = PDFInspector(data)

        try PDFValidation.writeArtifact(data, name: "\(artifactName).pdf")
        #expect(data.count > minimumPDFBytes)
        #expect(inspector.pageCount >= minimumPageCount)
        #expect(inspector.hasValidXrefOffsets())
        #expect(inspector.streamLengthsMatch())
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "Canonical PDF structure failed for \(directory):\n\(inspector.canonicalStructureReport())",
        )
        #expect(localImageReferenceCount(in: markdown) == expectedImageReferences)
        #expect(imageXObjectCount(in: inspector.text) == expectedImageReferences)

        let qpdf = try PDFValidation.qpdfCheck(data: data, name: artifactName)
        #expect(qpdf.exitCode == 0, "qpdf --check failed for \(directory):\n\(qpdf.output)")

        let infoResult = try PDFValidation.pdfinfo(data: data, name: artifactName)
        let info = PDFValidation.parsedInfo(from: infoResult)
        #expect(infoResult.exitCode == 0, "pdfinfo failed for \(directory):\n\(infoResult.output)")
        #expect(info["Page size"]?.contains("595.28 x 841.89 pts") == true)
        #expect(info["Pages"] == "\(inspector.pageCount)", "Unexpected pdfinfo output for \(directory):\n\(infoResult.output)")

        let textResult = try PDFValidation.pdftotext(data: data, name: artifactName)
        #expect(textResult.exitCode == 0, "pdftotext failed for \(directory):\n\(textResult.output)")
        let normalizedText = normalizedExtractedText(textResult.output)
        #expect(normalizedText.contains(expectedTitle))
        for fragment in expectedFragments {
            #expect(normalizedText.contains(fragment))
        }

        let render = try PDFValidation.pdftoppmPNG(data: data, name: artifactName)
        let pngData = try? Data(contentsOf: render.pngURL)
        let dimensions = PDFValidation.pngDimensions(in: pngData)
        #expect(render.result.exitCode == 0, "pdftoppm failed for \(directory):\n\(render.result.output)")
        #expect(dimensions != nil)
        #expect((dimensions?.width ?? 0) > 0)
        #expect((dimensions?.height ?? 0) > 0)
    }

    private func assertExternalMarkdownFixtureRenders(
        fixtureName: String,
        title: String,
        artifactName: String,
        expectedFragments: [String],
        minimumPageCount: Int,
        minimumPDFBytes: Int,
    ) throws {
        let markdown = try fixture(named: fixtureName)
        let data = try MarkdownPDFRenderer(options: externalFixtureOptions(title: title)).render(markdown: markdown)
        let inspector = PDFInspector(data)

        try PDFValidation.writeArtifact(data, name: "\(artifactName).pdf")
        #expect(data.count > minimumPDFBytes)
        #expect(inspector.pageCount >= minimumPageCount)
        #expect(inspector.hasValidXrefOffsets())
        #expect(inspector.streamLengthsMatch())
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "Canonical PDF structure failed for \(fixtureName):\n\(inspector.canonicalStructureReport())",
        )

        let qpdf = try PDFValidation.qpdfCheck(data: data, name: artifactName)
        #expect(qpdf.exitCode == 0, "qpdf --check failed for \(fixtureName):\n\(qpdf.output)")

        let infoResult = try PDFValidation.pdfinfo(data: data, name: artifactName)
        let info = PDFValidation.parsedInfo(from: infoResult)
        #expect(infoResult.exitCode == 0, "pdfinfo failed for \(fixtureName):\n\(infoResult.output)")
        #expect(info["Page size"]?.contains("595.28 x 841.89 pts") == true)
        #expect(info["Pages"] == "\(inspector.pageCount)", "Unexpected pdfinfo output for \(fixtureName):\n\(infoResult.output)")

        let textResult = try PDFValidation.pdftotext(data: data, name: artifactName)
        #expect(textResult.exitCode == 0, "pdftotext failed for \(fixtureName):\n\(textResult.output)")
        let normalizedText = normalizedExtractedText(textResult.output)
        for fragment in expectedFragments {
            #expect(normalizedText.contains(fragment))
        }

        let render = try PDFValidation.pdftoppmPNG(data: data, name: artifactName)
        let pngData = try? Data(contentsOf: render.pngURL)
        let dimensions = PDFValidation.pngDimensions(in: pngData)
        #expect(render.result.exitCode == 0, "pdftoppm failed for \(fixtureName):\n\(render.result.output)")
        #expect(dimensions != nil)
        #expect((dimensions?.width ?? 0) > 0)
        #expect((dimensions?.height ?? 0) > 0)
    }

    private func articleFixtureOptions(for fixtureName: String) -> PDFOptions {
        if ["article-grade-stress.md", "hard-markdown-corpus.md"].contains(fixtureName) {
            return PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                title: expectedTextFragment(for: fixtureName),
                tableOfContents: .enabled,
            )
        }

        if fixtureName == "a4-manuscript.md" {
            return PDFOptions(
                pageSize: .a4,
                margins: PDFOptions.Margins(top: 56, right: 54, bottom: 56, left: 54),
                baseFontSize: 11,
                title: "Portable A4 Manuscript Fixture",
                tableOfContents: .enabled,
            )
        }

        return PDFOptions()
    }

    private func externalFixtureOptions(title: String) -> PDFOptions {
        PDFOptions(
            pageSize: .a4,
            margins: PDFOptions.Margins(top: 56, right: 54, bottom: 56, left: 54),
            baseFontSize: 10,
            title: title,
            tableOfContents: .enabled,
        )
    }

    private func articleFixtureAssetsBaseURL(for fixtureName: String) throws -> URL? {
        if ["article-grade-stress.md", "hard-markdown-corpus.md", "a4-manuscript.md"].contains(fixtureName) {
            return try TestImageAssets.directoryWithChartPNG()
        }

        return nil
    }

    private func externalFixtureAssetsBaseURL(directory: String) throws -> URL {
        try fixtureURL(named: "\(directory)/README.md").deletingLastPathComponent()
    }

    private var publicFixtureNames: [String] {
        ["democv.md"] + articleGradeFixtureNames
    }

    private var articleGradeFixtureNames: [String] {
        [
            "article-grade-stress.md",
            "hard-markdown-corpus.md",
            "a4-manuscript.md",
            "scientific-article.md",
            "technical-report.md",
        ]
    }

    private func expectedTextFragment(for fixtureName: String) -> String {
        switch fixtureName {
        case "article-grade-stress.md":
            "Portable Article Stress Corpus"
        case "hard-markdown-corpus.md":
            "Portable Hard Markdown Corpus"
        case "a4-manuscript.md":
            "Portable A4 Manuscript Fixture"
        case "scientific-article.md":
            "Reproducible Layout Measurements"
        case "technical-report.md":
            "Portable PDF Validation Technical Report"
        default:
            fixtureName
        }
    }

    private func expectedMinimumPageCount(for fixtureName: String) -> Int {
        switch fixtureName {
        case "article-grade-stress.md", "hard-markdown-corpus.md":
            6
        case "a4-manuscript.md":
            5
        default:
            1
        }
    }

    private func normalizedExtractedText(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func fixtureURL(named name: String) throws -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }

    private func localImageReferenceCount(in markdown: String) -> Int {
        markdown.components(separatedBy: "![](assets/").count - 1
    }

    private func imageXObjectCount(in pdfText: String) -> Int {
        pdfText.components(separatedBy: "/Subtype /Image").count - 1
    }

    private func selectedLocalImageFixtureMarkdown(
        from markdown: String,
        allowedAssetNames: Set<String>,
        lineLimit: Int? = nil,
        marker: String,
    ) -> String {
        let sourceLines = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let limitedLines = lineLimit.map { Array(sourceLines.prefix($0)) } ?? sourceLines
        let filteredLines = limitedLines.filter { line in
            guard let assetName = localImageAssetName(in: line) else {
                return true
            }

            return allowedAssetNames.contains(assetName)
        }

        return (filteredLines + ["", "## Fixture Boundary", marker]).joined(separator: "\n")
    }

    private func localImageAssetName(in line: String) -> String? {
        let prefix = "![](assets/"
        guard line.hasPrefix(prefix), line.hasSuffix(")") else {
            return nil
        }

        return String(line.dropFirst(prefix.count).dropLast())
    }

    private func largeFixtureStressTestsEnabled() -> Bool {
        ProcessInfo.processInfo.environment["MARKDOWNPDF_LARGE_FIXTURE_TESTS"] == "1"
    }

    private var wwdcFixtureDirectory: String {
        "wwdc-2019-613-ray-tracing-with-metal"
    }

    private var wwdcOptimizedAssetNames: Set<String> {
        Set([
            "2019_613_page-001.png",
            "frame_00001.jpg",
            "2019_613_page-002.png",
            "2019_613_page-005.png",
            "2019_613_page-009.png",
            "2019_613_page-015.png",
            "2019_613_page-018.png",
            "2019_613_page-020.png",
            "2019_613_page-027.png",
            "frame_00042.jpg",
            "2019_613_page-030.png",
            "2019_613_page-031.png",
            "2019_613_page-032.png",
        ])
    }

    private var wwdcLargeStressAssetNames: Set<String> {
        Set([
            "2019_613_page-154.png",
            "2019_613_page-155.png",
            "2019_613_page-216.png",
            "2019_613_page-232.png",
        ])
    }
}
