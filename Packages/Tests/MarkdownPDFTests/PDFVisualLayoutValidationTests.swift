import Foundation
@testable import MarkdownPDF
import Testing

@Suite("PDF visual layout validation")
struct PDFVisualLayoutValidationTests {
    @Test("Generated PDFs do not have overlapping Poppler word boxes")
    func generatedPDFsDoNotHaveOverlappingPopplerWordBoxes() throws {
        let data = try visualValidationPDF()
        let result = try PDFValidation.pdftotextTSV(data: data, name: "visual-layout")
        try #require(result.exitCode == 0, "pdftotext -tsv failed:\n\(result.output)")
        try PDFValidation.writeTextArtifact(result.output, name: "visual-layout/poppler.tsv")

        let textResult = try PDFValidation.pdftotext(data: data, name: "visual-layout-text")
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "visual-layout/text.txt")

        let infoResult = try PDFValidation.pdfinfo(data: data, name: "visual-layout-info")
        try #require(infoResult.exitCode == 0, "pdfinfo failed:\n\(infoResult.output)")
        try PDFValidation.writeTextArtifact(infoResult.output, name: "visual-layout/pdfinfo.txt")

        let layout = try PopplerTextLayout(tsv: result.output)
        let issues = layout.visualLayoutIssues()

        #expect(layout.pages.count >= 4)
        #expect(layout.words.count > 200)
        #expect(layout.words.contains { $0.text == "Table" })
        #expect(layout.words.contains { $0.text == "Contents" })
        #expect(
            issues.isEmpty,
            "Poppler text layout has visual issues:\n\(issues.joined(separator: "\n"))",
        )
    }

    @Test("Generated code blocks wrap long lines inside page bounds")
    func generatedCodeBlocksWrapLongLinesInsidePageBounds() throws {
        let markdown = """
        # Code block wrapping

        ```text
        let clippedLine = "Author[Author input] --> Parser[Swift parser] --> Renderer[PDF renderer] --> Tools[Open tools]"
        ```
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 220, height: 220),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
            ),
        ).render(markdown: markdown)

        let result = try PDFValidation.pdftotextTSV(data: data, name: "code-block-wrap")
        try #require(result.exitCode == 0, "pdftotext -tsv failed:\n\(result.output)")

        let layout = try PopplerTextLayout(tsv: result.output)
        #expect(layout.visualLayoutIssues().isEmpty)
        #expect(layout.words.contains { $0.text == "Renderer[PDF" })
        #expect(layout.words.contains { $0.text == "tools]\"" })
    }

    @Test("Generated PDFs do not have overlapping MuPDF character quads")
    func generatedPDFsDoNotHaveOverlappingMuPDFCharacterQuads() throws {
        let data = try visualValidationPDF()
        let result = try PDFValidation.mutoolStructuredText(data: data, name: "visual-layout-mupdf")
        try #require(result.exitCode == 0, "mutool structured text failed:\n\(result.output)")
        try PDFValidation.writeTextArtifact(result.output, name: "visual-layout/mupdf-stext.xml")

        let layout = try MuPDFStructuredText(xml: result.output)
        let visibleGlyphCount = layout.glyphs.count(where: { !$0.isWhitespace })
        let issues = layout.characterQuadIssues()

        #expect(layout.pages.count >= 4)
        #expect(visibleGlyphCount > 1200)
        #expect(
            issues.isEmpty,
            "MuPDF character layout has visual issues:\n\(issues.joined(separator: "\n"))",
        )
    }

    @Test("Poppler and MuPDF render comparable ink bounds")
    func popplerAndMuPDFRenderComparableInkBounds() throws {
        let data = try visualValidationPDF()
        let url = try PDFValidation.temporaryPDF(name: "visual-layout-raster", data: data)
        let pageCount = PDFInspector(data).pageCount

        #expect(pageCount >= 4)

        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "visual-layout/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "visual-layout/mupdf-render.log")

        var issues: [String] = []
        for page in 1 ... pageCount {
            let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
            let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
            try PDFValidation.copyArtifact(
                from: poppler.pnmURLs[page - 1],
                name: "visual-layout-pages/poppler/page-\(page).ppm",
            )
            try PDFValidation.copyArtifact(
                from: mupdf.pnmURLs[page - 1],
                name: "visual-layout-pages/mupdf/page-\(page).pnm",
            )
            issues += rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage).map {
                "page \(page): \($0)"
            }
        }

        #expect(
            issues.isEmpty,
            "Poppler and MuPDF raster output diverged:\n\(issues.joined(separator: "\n"))",
        )
    }

    @Test("Article stress fixture passes visual witness stack")
    func articleStressFixturePassesVisualWitnessStack() throws {
        let data = try articleStressFixturePDF()
        let url = try PDFValidation.temporaryPDF(name: "article-grade-stress", data: data)
        let pageCount = PDFInspector(data).pageCount

        #expect(pageCount >= 6)
        try PDFValidation.writeArtifact(data, name: "article-grade-stress.pdf")

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "article-stress/text.txt")
        #expect(textResult.output.contains("Portable Article Stress Corpus"))
        #expect(textResult.output.contains("Table of Contents"))
        #expect(textResult.output.contains("Local chart placeholder"))

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "article-stress/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()

        #expect(popplerLayout.pages.count == pageCount)
        #expect(popplerLayout.words.count > 500)
        #expect(
            popplerIssues.isEmpty,
            "Article stress fixture Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "article-stress/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()

        #expect(mupdfLayout.pages.count == pageCount)
        #expect(mupdfLayout.glyphs.count(where: { !$0.isWhitespace }) > 2500)
        #expect(
            mupdfIssues.isEmpty,
            "Article stress fixture MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "article-stress/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "article-stress/mupdf-render.log")

        var rasterIssues: [String] = []
        for page in 1 ... pageCount {
            let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
            let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
            try PDFValidation.copyArtifact(
                from: poppler.pnmURLs[page - 1],
                name: "article-stress-pages/poppler/page-\(page).ppm",
            )
            try PDFValidation.copyArtifact(
                from: mupdf.pnmURLs[page - 1],
                name: "article-stress-pages/mupdf/page-\(page).pnm",
            )
            rasterIssues += rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage).map {
                "page \(page): \($0)"
            }
        }

        #expect(
            rasterIssues.isEmpty,
            "Article stress fixture raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
        )
    }

    @Test("Portable text encoding profile passes visual witness stack")
    func portableTextEncodingProfilePassesVisualWitnessStack() throws {
        let markdown = """
        # Portable Text Encoding

        ASCII: The quick brown fox stays portable.

        Latin: Caf\u{00E9} ni\u{00F1}o NBSP\u{00A0}done.

        WinAnsi: \u{201C}quoted\u{201D} \u{20AC}.

        Unicode: \u{010D} \u{03C0} \u{1F680}.
        """
        let data = try MarkdownPDFRenderer(options: PDFOptions(baseFontSize: 10)).render(markdown: markdown)
        let url = try PDFValidation.temporaryPDF(name: "portable-text-encoding", data: data)
        let inspector = PDFInspector(data)

        #expect(inspector.pageCount == 1)
        #expect(!inspector.text.contains("/ToUnicode"))
        #expect(!inspector.text.contains("/FontFile"))
        try PDFValidation.writeArtifact(data, name: "text-encoding-profile.pdf")

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "text-encoding/text.txt")
        #expect(textResult.output.contains("ASCII: The quick brown fox stays portable."))
        #expect(textResult.output.contains("Latin: Caf? ni?o NBSP?done."))
        #expect(textResult.output.contains("WinAnsi: ?quoted? ?."))
        #expect(textResult.output.contains("Unicode: ? ? ?."))

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "text-encoding/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()
        #expect(
            popplerIssues.isEmpty,
            "Text encoding Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "text-encoding/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()
        #expect(
            mupdfIssues.isEmpty,
            "Text encoding MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNM(url: url)
        let mupdf = try PDFValidation.mutoolPNM(url: url)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "text-encoding/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "text-encoding/mupdf-render.log")
        try PDFValidation.copyArtifact(from: poppler.pnmURL, name: "text-encoding-pages/poppler/page-1.ppm")
        try PDFValidation.copyArtifact(from: mupdf.pnmURL, name: "text-encoding-pages/mupdf/page-1.pnm")

        let rasterIssues = try rasterComparisonIssues(
            poppler: PNMImage(data: Data(contentsOf: poppler.pnmURL)),
            mupdf: PNMImage(data: Data(contentsOf: mupdf.pnmURL)),
        )
        #expect(
            rasterIssues.isEmpty,
            "Text encoding raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
        )
    }

    @Test("Embedded CID text profile passes visual witness stack")
    func embeddedCIDTextProfilePassesVisualWitnessStack() throws {
        let data = try embeddedCIDTextPDF()
        let url = try PDFValidation.temporaryPDF(name: "embedded-cid-text", data: data)
        let inspector = PDFInspector(data)

        #expect(inspector.pageCount == 1)
        #expect(inspector.text.contains("/Subtype /Type0"))
        #expect(inspector.text.contains("/Subtype /CIDFontType2"))
        #expect(inspector.text.contains("/FontFile2"))
        #expect(inspector.text.contains("/ToUnicode"))
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        try PDFValidation.writeArtifact(data, name: "embedded-cid-text.pdf")

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "embedded-cid-text/text.txt")
        #expect(textResult.output.contains("WIDE WILLIAM MINIMUM MARGIN"))
        #expect(textResult.output.contains("LATIN CID TEXT STAYS ALIGNED"))

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "embedded-cid-text/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()
        #expect(popplerLayout.words.count >= 18)
        #expect(
            popplerIssues.isEmpty,
            "Embedded CID text Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "embedded-cid-text/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()
        #expect(mupdfLayout.glyphs.count(where: { !$0.isWhitespace }) >= 88)
        #expect(
            mupdfIssues.isEmpty,
            "Embedded CID text MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNM(url: url)
        let mupdf = try PDFValidation.mutoolPNM(url: url)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "embedded-cid-text/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "embedded-cid-text/mupdf-render.log")
        try PDFValidation.copyArtifact(from: poppler.pnmURL, name: "embedded-cid-text-pages/poppler/page-1.ppm")
        try PDFValidation.copyArtifact(from: mupdf.pnmURL, name: "embedded-cid-text-pages/mupdf/page-1.pnm")

        let rasterIssues = try rasterComparisonIssues(
            poppler: PNMImage(data: Data(contentsOf: poppler.pnmURL)),
            mupdf: PNMImage(data: Data(contentsOf: mupdf.pnmURL)),
        )
        #expect(
            rasterIssues.isEmpty,
            "Embedded CID text raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
        )
    }

    @Test("Oversized blocks split or scale inside page bounds")
    func oversizedBlocksSplitOrScaleInsidePageBounds() throws {
        let code = (1 ... 18)
            .map { "code_line_\($0) = \"portable overflow policy keeps this line on page\"" }
            .joined(separator: "\n")
        let tablePayload = (1 ... 54)
            .map { "cell\($0)" }
            .joined(separator: " ")
        let mermaidEdges = (1 ... 10)
            .map { "N\($0)[Node \($0)] --> N\($0 + 1)[Node \($0 + 1)]" }
            .joined(separator: "\n")
        let markdown = """
        ![Tall local chart](tall-chart.png)

        # Oversized Blocks

        | Kind | Payload |
        |---|---|
        | Tall row | \(tablePayload) |

        ```mermaid
        flowchart TD
        \(mermaidEdges)
        ```

        ```text
        \(code)
        ```
        """
        let assetsBaseURL = try TestImageAssets.directoryWithChartPNG(
            named: "tall-chart.png",
            width: 640,
            height: 1600,
        )
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 220),
                margins: PDFOptions.Margins(top: 70, right: 22, bottom: 70, left: 22),
                baseFontSize: 9,
            ),
        ).render(markdown: markdown, assetsBaseURL: assetsBaseURL)
        let url = try PDFValidation.temporaryPDF(name: "oversized-blocks", data: data)
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount

        #expect(pageCount >= 6)
        #expect(inspector.streams.contains { $0.body.contains("32 0 0 80 22 70 cm") })
        try PDFValidation.writeArtifact(data, name: "oversized-blocks.pdf")

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "oversized-blocks/text.txt")
        #expect(textResult.output.contains("Tall row"))
        #expect(textResult.output.contains("Unsupported Mermaid diagram"))
        #expect(textResult.output.contains("code_line_18"))

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "oversized-blocks/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()
        #expect(
            popplerIssues.isEmpty,
            "Oversized block Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "oversized-blocks/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()
        #expect(
            mupdfIssues.isEmpty,
            "Oversized block MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "oversized-blocks/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "oversized-blocks/mupdf-render.log")

        var rasterIssues: [String] = []
        for page in 1 ... pageCount {
            let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
            let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
            try PDFValidation.copyArtifact(
                from: poppler.pnmURLs[page - 1],
                name: "oversized-blocks-pages/poppler/page-\(page).ppm",
            )
            try PDFValidation.copyArtifact(
                from: mupdf.pnmURLs[page - 1],
                name: "oversized-blocks-pages/mupdf/page-\(page).pnm",
            )
            rasterIssues += rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage).map {
                "page \(page): \($0)"
            }
        }

        #expect(
            rasterIssues.isEmpty,
            "Oversized block raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
        )
    }

    @Test("Measured tables preserve alignment and repeat headers across pages")
    func measuredTablesPreserveAlignmentAndRepeatHeadersAcrossPages() throws {
        let longCell = (1 ... 56)
            .map { "span\($0)" }
            .joined(separator: " ")
        let rows = (1 ... 16)
            .map { row in
                let description = [
                    "Measured prose cell \(row) keeps words separated near borders",
                    "UltraPortableDeterministicTableTokenWithoutSpaces\(row)",
                    "and wraps dense article-style language across the measured column.",
                ].joined(separator: " ")
                return "| row-\(row) | \(description) | \(90 + row) |"
            }
            .joined(separator: "\n")
        let markdown = """
        # Measured Tables

        | ID | Description | Score |
        |:---|:---:|---:|
        | intro | \(longCell) | 100 |
        \(rows)
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 280, height: 250),
                margins: PDFOptions.Margins(top: 30, right: 24, bottom: 30, left: 24),
                baseFontSize: 9,
            ),
        ).render(markdown: markdown)
        let url = try PDFValidation.temporaryPDF(name: "measured-tables", data: data)
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount

        #expect(pageCount >= 4)
        #expect(tableRectangleWidths(in: inspector).contains { $0 < 60 })
        #expect(tableRectangleWidths(in: inspector).contains { $0 > 95 })
        try PDFValidation.writeArtifact(data, name: "measured-tables.pdf")

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "measured-tables/text.txt")
        #expect(textResult.output.contains("row-16"))
        #expect(textResult.output.components(separatedBy: "Description").count >= 3)

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "measured-tables/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()
        #expect(
            popplerIssues.isEmpty,
            "Measured table Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "measured-tables/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()
        #expect(
            mupdfIssues.isEmpty,
            "Measured table MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "measured-tables/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "measured-tables/mupdf-render.log")

        var rasterIssues: [String] = []
        for page in 1 ... pageCount {
            let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
            let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
            try PDFValidation.copyArtifact(
                from: poppler.pnmURLs[page - 1],
                name: "measured-tables-pages/poppler/page-\(page).ppm",
            )
            try PDFValidation.copyArtifact(
                from: mupdf.pnmURLs[page - 1],
                name: "measured-tables-pages/mupdf/page-\(page).pnm",
            )
            rasterIssues += rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage).map {
                "page \(page): \($0)"
            }
        }

        #expect(
            rasterIssues.isEmpty,
            "Measured table raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
        )
    }

    @Test("Diagram policy witness covers edge labels and chart fallback")
    func diagramPolicyWitnessCoversEdgeLabelsAndChartFallback() throws {
        let markdown = """
        # Diagram Policy

        ```mermaid
        flowchart TD
            Source["Markdown input"] -->|parse| Parser["Flow parser"]
            Parser -->|draw| Renderer["PDF renderer"]
        ```

        ```mermaid
        pie title Unsupported chart
            "Alpha" : 3
            "Beta" : 2
        ```
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 280, height: 300),
                margins: PDFOptions.Margins(top: 28, right: 24, bottom: 28, left: 24),
                baseFontSize: 10,
            ),
        ).render(markdown: markdown)
        let url = try PDFValidation.temporaryPDF(name: "diagram-policy", data: data)
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount

        #expect(pageCount >= 1)
        try PDFValidation.writeArtifact(data, name: "diagram-policy.pdf")

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "diagram-policy/text.txt")
        #expect(textResult.output.contains("Markdown input"))
        #expect(textResult.output.contains("parse"))
        #expect(textResult.output.contains("draw"))
        #expect(!textResult.output.contains("Source[\"Markdown input\"]"))
        #expect(!textResult.output.contains("Parser[\"Flow parser\"]"))
        #expect(textResult.output.contains("Unsupported Mermaid diagram"))
        #expect(textResult.output.contains("pie title Unsupported chart"))

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "diagram-policy/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()
        #expect(
            popplerIssues.isEmpty,
            "Diagram policy Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "diagram-policy/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()
        #expect(
            mupdfIssues.isEmpty,
            "Diagram policy MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "diagram-policy/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "diagram-policy/mupdf-render.log")

        var rasterIssues: [String] = []
        for page in 1 ... pageCount {
            let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
            let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
            try PDFValidation.copyArtifact(
                from: poppler.pnmURLs[page - 1],
                name: "diagram-policy-pages/poppler/page-\(page).ppm",
            )
            try PDFValidation.copyArtifact(
                from: mupdf.pnmURLs[page - 1],
                name: "diagram-policy-pages/mupdf/page-\(page).pnm",
            )
            rasterIssues += rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage).map {
                "page \(page): \($0)"
            }
        }

        #expect(
            rasterIssues.isEmpty,
            "Diagram policy raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
        )
    }

    @Test("Visual layout validator rejects overlapping words")
    func visualLayoutValidatorRejectsOverlappingWords() throws {
        let layout = try PopplerTextLayout(tsv: """
        level\tpage_num\tpar_num\tblock_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
        1\t1\t0\t0\t0\t0\t0.000000\t0.000000\t200.000000\t200.000000\t-1\t###PAGE###
        4\t1\t0\t1\t0\t0\t10.000000\t20.000000\t60.000000\t10.000000\t-1\t###LINE###
        5\t1\t0\t1\t0\t0\t10.00\t20.00\t40.00\t10.00\t100\tFirst
        5\t1\t0\t1\t0\t1\t49.00\t20.00\t30.00\t10.00\t100\tSecond
        """)

        #expect(layout.visualLayoutIssues().contains { $0.contains("overlaps") })
    }

    @Test("Visual layout validator normalizes offset Poppler page rows")
    func visualLayoutValidatorNormalizesOffsetPopplerPageRows() throws {
        let layout = try PopplerTextLayout(tsv: """
        level\tpage_num\tpar_num\tblock_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
        1\t2\t0\t0\t0\t0\t205.970000\t253.270000\t260.000000\t320.000000\t-1\t###PAGE###
        4\t2\t0\t0\t0\t0\t95.280000\t41.481600\t69.440800\t8.140000\t-1\t###LINE###
        5\t2\t0\t0\t0\t0\t95.28\t41.48\t40.59\t8.14\t100\tMarkdown
        5\t2\t0\t0\t0\t1\t138.31\t41.48\t26.41\t8.14\t100\tsource
        """)

        #expect(layout.visualLayoutIssues().isEmpty)
    }

    @Test("Visual layout validator allows table columns on the same row")
    func visualLayoutValidatorAllowsTableColumnsOnSameRow() throws {
        let layout = try PopplerTextLayout(tsv: """
        level\tpage_num\tpar_num\tblock_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
        1\t1\t0\t0\t0\t0\t0.000000\t0.000000\t220.000000\t220.000000\t-1\t###PAGE###
        4\t1\t0\t1\t0\t0\t20.000000\t60.000000\t40.000000\t10.000000\t-1\t###LINE###
        5\t1\t0\t1\t0\t0\t20.00\t60.00\t40.00\t10.00\t100\tLeft
        4\t1\t0\t1\t1\t0\t90.000000\t60.000000\t50.000000\t10.000000\t-1\t###LINE###
        5\t1\t0\t1\t1\t0\t90.00\t60.00\t50.00\t10.00\t100\tRight
        """)

        #expect(layout.visualLayoutIssues().isEmpty)
    }

    @Test("Visual layout validator rejects collisions hidden behind table columns")
    func visualLayoutValidatorRejectsCollisionsHiddenBehindTableColumns() throws {
        let layout = try PopplerTextLayout(tsv: """
        level\tpage_num\tpar_num\tblock_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
        1\t1\t0\t0\t0\t0\t0.000000\t0.000000\t220.000000\t220.000000\t-1\t###PAGE###
        4\t1\t0\t1\t0\t0\t20.000000\t60.000000\t40.000000\t20.000000\t-1\t###LINE###
        5\t1\t0\t1\t0\t0\t20.00\t60.00\t40.00\t20.00\t100\tTop
        4\t1\t0\t1\t1\t0\t90.000000\t65.000000\t50.000000\t10.000000\t-1\t###LINE###
        5\t1\t0\t1\t1\t0\t90.00\t65.00\t50.00\t10.00\t100\tSide
        4\t1\t0\t1\t2\t0\t22.000000\t70.000000\t40.000000\t10.000000\t-1\t###LINE###
        5\t1\t0\t1\t2\t0\t22.00\t70.00\t40.00\t10.00\t100\tBottom
        """)

        #expect(layout.visualLayoutIssues().contains { $0.contains("collides vertically") })
    }

    @Test("MuPDF character quad validator rejects overlapping glyphs")
    func muPDFCharacterQuadValidatorRejectsOverlappingGlyphs() throws {
        let layout = try MuPDFStructuredText(xml: """
        <?xml version="1.0"?>
        <document filename="overlap.pdf">
        <page id="page1" width="100" height="100">
        <block bbox="10 10 40 20" justify="unknown">
        <line bbox="10 10 40 20" wmode="0" dir="1 0" flags="0" text="AB">
        <font name="Helvetica" size="12">
        <char quad="10 10 20 10 10 20 20 20" x="10" y="20" c="A"/>
        <char quad="19 10 30 10 19 20 30 20" x="19" y="20" c="B"/>
        </font>
        </line>
        </block>
        </page>
        </document>
        """)

        #expect(layout.characterQuadIssues().contains { $0.contains("overlaps") })
    }

    @Test("Raster comparison rejects divergent ink bounds")
    func rasterComparisonRejectsDivergentInkBounds() throws {
        let poppler = try PNMImage(data: pnmImage(width: 20, height: 20, inkBox: 2 ... 5))
        let mupdf = try PNMImage(data: pnmImage(width: 20, height: 20, inkBox: 16 ... 19))

        #expect(rasterComparisonIssues(poppler: poppler, mupdf: mupdf).contains { $0.contains("ink bounds differ") })
    }

    private func visualValidationPDF() throws -> Data {
        let markdown = """
        # Visual validation

        This fixture checks proportional spacing, **bold spacing**, *italic spacing*,
        `monospaced spacing`, URI text, table cells, list indentation, and diagram
        labels on narrow pages. The point is to give Poppler and MuPDF enough
        material to disagree if the renderer starts placing glyphs badly.

        ## Inline stress

        A narrow paragraph mixes words with very different shapes: WWWWWW, iiiiii,
        minimum, maximum, allocation, fulfillment, and reproducibility. The line
        wrapper must keep each word separated even when punctuation, commas, and
        periods appear at the edge of the available measure.

        The same paragraph family also checks **bold words near normal words**,
        *italic words near normal words*, and `code tokens beside prose`. A later
        regression in font metrics should appear as either overlapping Poppler word
        boxes or overlapping MuPDF character quads.

        - First bullet item has enough text to wrap onto a second line while the
          marker remains separate from the body text.
        - Second bullet item includes `code`, **bold emphasis**, and iiiiii WWWWWW
          patterns to stress mixed-font cursor movement.
        - Third bullet item is deliberately ordinary so vertical spacing issues
          show up between adjacent list rows.

        | Column | Description |
        |---|---|
        | Alpha | Several words should remain separated across wrapped cell lines. |
        | Beta | Wide letters like WWWWWW and narrow letters like iiiiii both render. |
        | Gamma | Inline code, bold text, and italic text are checked beside table borders. |
        | Delta | A final row gives the table enough height to reveal cell spacing drift. |

        ## Diagram pipeline

        ```mermaid
        flowchart TD
            Source[Markdown source] -->|parse| Blocks[Block tree]
            Blocks --> Layout[PDF layout]
            Layout --> Bytes[PDF bytes]
        ```

        After the first diagram, prose resumes immediately. This catches cases
        where a diagram consumes the wrong amount of vertical space and lets the
        next paragraph collide with the diagram background or node labels.

        ## Dense article section

        The dense section repeats realistic article prose instead of isolated
        tokens. Rendering should remain stable while headings, paragraphs, tables,
        lists, and diagrams cross page boundaries. The sentences use plain ASCII
        because the public package currently targets PDF base fonts by default.

        A second paragraph adds link-shaped text without depending on network
        access: https://example.com/articles/portable-layout. The text should
        remain extractable as words and should not compress into neighboring runs.

        | Phase | Check | Expected signal |
        |---|---|---|
        | Parse | Headings, lists, tables, and Mermaid fences | Extractable labels |
        | Layout | Page breaks and table rows | Non-overlapping boxes |
        | Serialize | Streams, resources, and xref entries | Valid PDF bytes |
        | Inspect | Poppler, MuPDF, and qpdf witnesses | Actionable failures |

        More prose follows the second table so the document spans more than a
        token amount of content. The renderer should keep line spacing consistent
        after tables, before diagrams, and across new pages. If line height is too
        small, independent text extraction will flag collisions.

        ```mermaid
        graph LR
            Author[Author input] --> Parser[Swift parser]
            Parser --> Renderer[PDF renderer]
            Renderer --> Tools[Open tools]
        ```

        ## UltraPortableDeterministicHeadingAnchorWithoutSpaces

        This heading deliberately has one long token so the generated table of
        contents has to wrap it before the page number column.

        ## Closing checks

        The final section is intentionally not empty. It validates that the last
        page still has enough ink for raster comparison and that tail content is
        not clipped. Several short sentences follow. First, text extraction must
        include the closing words. Second, glyph quads must move monotonically in
        each visible run. Third, raster bounds from Poppler and MuPDF must overlap
        enough to prove both engines saw the same broad layout.

        A compact summary ends the fixture with known labels: Markdown source,
        Block tree, PDF layout, PDF bytes, Author input, Swift parser, PDF renderer,
        and Open tools.
        """

        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                tableOfContents: .enabled,
            ),
        ).render(markdown: markdown)
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        try PDFValidation.writeArtifact(data, name: "visual-layout-stress.pdf")
        return data
    }

    private func articleStressFixturePDF() throws -> Data {
        let assetsBaseURL = try TestImageAssets.directoryWithChartPNG()
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                title: "Portable Article Stress Corpus",
                tableOfContents: .enabled,
            ),
        ).render(
            markdown: fixture(named: "article-grade-stress.md"),
            assetsBaseURL: assetsBaseURL,
        )
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        return data
    }

    private func embeddedCIDTextPDF() throws -> Data {
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let metadata = try TrueTypeFontParser().parse(fontData)
        let mapper = TrueTypeGlyphMapper(
            data: fontData,
            metadata: metadata,
            missingGlyphPolicy: .useNotdef,
        )
        let resource = PDFEmbeddedFontResource(
            resourceName: "EF1",
            fontProgram: fontData,
            metadata: metadata,
        )
        let canvas = PDFPageCanvas()
        let lines = [
            "WIDE WILLIAM MINIMUM MARGIN",
            "NARROW INK MEETS WIDE WORDS",
            "LATIN CID TEXT STAYS ALIGNED",
            "WIDE LETTERS AND THIN INK",
        ]

        for (index, line) in lines.enumerated() {
            try canvas.drawCIDText(
                mapping: mapper.map(text: line, fontSize: 18),
                fontResource: resource,
                fontSize: 18,
                x: 42,
                y: 300 - Double(index) * 30,
            )
        }

        return try PDFDocumentWriter(
            pageSize: PDFOptions.PageSize(width: 440, height: 360),
            fontSet: .pdfBase,
            pages: [canvas],
            images: [],
            title: "Embedded CID Text Witness",
        ).data()
    }

    private func fixture(named name: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }

    private static let artifactManifest = """
    MarkdownPDF PDF witness artifacts

    visual-layout-stress.pdf
    Representative generated PDF used by the visual layout tests.

    visual-layout/text.txt
    Poppler pdftotext output for text extraction review.

    visual-layout/pdfinfo.txt
    Poppler pdfinfo output for page count and metadata review.

    visual-layout/poppler.tsv
    Poppler pdftotext -tsv geometry output used for word and line checks.

    visual-layout/mupdf-stext.xml
    MuPDF structured text output used for character quad checks.

    visual-layout/poppler-render.log
    Poppler raster command output.

    visual-layout/mupdf-render.log
    MuPDF raster command output.

    visual-layout-pages/poppler/
    Poppler page rasters used for raster ink bounds comparison.

    visual-layout-pages/mupdf/
    MuPDF page rasters used for raster ink bounds comparison.

    article-grade-stress.pdf
    Heavier public article fixture used by the article-grade corpus tests.

    article-stress/
    Text, geometry, structured text, and render logs for the article fixture.

    article-stress-pages/
    Poppler and MuPDF page rasters for the article fixture.

    text-encoding-profile.pdf
    One-page PDF proving the portable text encoding replacement profile.

    text-encoding/
    Text, geometry, structured text, and render logs for the text encoding fixture.

    text-encoding-pages/
    Poppler and MuPDF page rasters for the text encoding fixture.

    oversized-blocks.pdf
    PDF proving oversized block split, fallback, and image scaling policies.

    oversized-blocks/
    Text, geometry, structured text, and render logs for the oversized blocks fixture.

    oversized-blocks-pages/
    Poppler and MuPDF page rasters for the oversized blocks fixture.

    measured-tables.pdf
    PDF proving measured table column widths, mixed alignment, row splitting, and repeated headers.

    measured-tables/
    Text, geometry, structured text, and render logs for the measured table fixture.

    measured-tables-pages/
    Poppler and MuPDF page rasters for the measured table fixture.

    diagram-policy.pdf
    PDF proving edge-labeled Mermaid diagrams and unsupported chart fallback.

    diagram-policy/
    Text, geometry, structured text, and render logs for the diagram policy fixture.

    diagram-policy-pages/
    Poppler and MuPDF page rasters for the diagram policy fixture.

    embedded-cid-text.pdf
    PDF proving the opt-in embedded CID text writer with FontFile2, CIDFontType2, Type0, and ToUnicode objects.

    embedded-cid-text/
    Text, geometry, structured text, and render logs for the embedded CID text fixture.

    embedded-cid-text-pages/
    Poppler and MuPDF page rasters for the embedded CID text fixture.
    """

    private func tableRectangleWidths(in inspector: PDFInspector) -> [Double] {
        inspector.streams
            .flatMap { stream in
                stream.body
                    .split(separator: "\n")
                    .compactMap { line -> Double? in
                        let parts = line.split(separator: " ")
                        guard let rectangleIndex = parts.firstIndex(of: "re"),
                              rectangleIndex >= 2
                        else {
                            return nil
                        }
                        return Double(parts[rectangleIndex - 2])
                    }
            }
    }

    private func rasterComparisonIssues(poppler: PNMImage, mupdf: PNMImage) -> [String] {
        var issues: [String] = []
        if poppler.width != mupdf.width || poppler.height != mupdf.height {
            issues.append(
                "image dimensions differ: Poppler \(poppler.width)x\(poppler.height), "
                    + "MuPDF \(mupdf.width)x\(mupdf.height)",
            )
        }

        let popplerInk = poppler.inkMetrics()
        let mupdfInk = mupdf.inkMetrics()
        if popplerInk.nonWhitePixelCount < 1000 {
            issues.append("Poppler rendered too little ink: \(popplerInk.nonWhitePixelCount) pixels")
        }
        if mupdfInk.nonWhitePixelCount < 1000 {
            issues.append("MuPDF rendered too little ink: \(mupdfInk.nonWhitePixelCount) pixels")
        }

        guard let popplerBox = popplerInk.box,
              let mupdfBox = mupdfInk.box
        else {
            issues.append("one renderer produced a blank page")
            return issues
        }

        let overlapRatio = inkOverlapRatio(popplerBox, mupdfBox)
        if overlapRatio < 0.85 {
            issues.append("ink bounds differ: Poppler \(popplerBox), MuPDF \(mupdfBox)")
        }

        return issues
    }

    private func inkOverlapRatio(_ left: PNMImage.InkBox, _ right: PNMImage.InkBox) -> Double {
        let intersectionLeft = max(left.left, right.left)
        let intersectionTop = max(left.top, right.top)
        let intersectionRight = min(left.right, right.right)
        let intersectionBottom = min(left.bottom, right.bottom)
        guard intersectionLeft <= intersectionRight, intersectionTop <= intersectionBottom else {
            return 0
        }

        let intersectionArea = (intersectionRight - intersectionLeft + 1) * (intersectionBottom - intersectionTop + 1)
        let smallerArea = min(left.width * left.height, right.width * right.height)
        return Double(intersectionArea) / Double(smallerArea)
    }

    private func pnmImage(width: Int, height: Int, inkBox: ClosedRange<Int>) -> Data {
        var data = Data("P5\n\(width) \(height)\n255\n".utf8)
        for y in 0 ..< height {
            for x in 0 ..< width {
                data.append(inkBox.contains(x) && inkBox.contains(y) ? 0 : 255)
            }
        }
        return data
    }
}

private struct PopplerTextLayout {
    struct Box: Equatable {
        var level: Int
        var page: Int
        var paragraph: Int
        var block: Int
        var line: Int
        var word: Int
        var left: Double
        var top: Double
        var width: Double
        var height: Double
        var text: String

        var right: Double {
            left + width
        }

        var bottom: Double {
            top + height
        }
    }

    var boxes: [Box]

    var pages: [Box] {
        boxes.filter { $0.level == 1 }
    }

    var lines: [Box] {
        boxes.filter { $0.level == 4 }
    }

    var words: [Box] {
        boxes.filter { $0.level == 5 && !$0.text.isEmpty }
    }

    init(tsv: String) throws {
        boxes = try tsv
            .split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst()
            .map { line in
                try Self.parse(line: String(line))
            }
    }

    func visualLayoutIssues() -> [String] {
        var issues: [String] = []
        validateBoxesHavePositiveSize(issues: &issues)
        validateWordsFitPageBounds(issues: &issues)
        validateWordsDoNotOverlap(issues: &issues)
        validateLinesDoNotOverlap(issues: &issues)
        return issues
    }

    private func validateBoxesHavePositiveSize(issues: inout [String]) {
        for box in words + lines + pages where box.width <= 0 || box.height <= 0 {
            issues.append("\(boxDescription(box)) has non-positive size")
        }
    }

    private func validateWordsFitPageBounds(issues: inout [String]) {
        let pagesByNumber = Dictionary(uniqueKeysWithValues: pages.map { ($0.page, $0) })
        for word in words {
            guard let page = pagesByNumber[word.page] else {
                issues.append("\(boxDescription(word)) references missing page \(word.page)")
                continue
            }

            // Linux Poppler can report non-zero page-row origins on later
            // pages even when the PDF MediaBox starts at 0,0. Generated
            // MarkdownPDF pages use zero-origin MediaBoxes, so use the page
            // size row as the bounds and ignore its reported origin.
            let pageLeft = 0.0
            let pageTop = 0.0
            let pageRight = page.width
            let pageBottom = page.height

            if word.left < pageLeft - tolerance
                || word.top < pageTop - tolerance
                || word.right > pageRight + tolerance
                || word.bottom > pageBottom + tolerance
            {
                issues.append("\(boxDescription(word)) is outside page bounds")
            }
        }
    }

    private func validateWordsDoNotOverlap(issues: inout [String]) {
        for group in groupedWordsByLine() {
            let sortedWords = group.sorted { left, right in
                if left.left == right.left {
                    return left.word < right.word
                }
                return left.left < right.left
            }

            for (left, right) in zip(sortedWords, sortedWords.dropFirst()) {
                if right.left < left.right - tolerance {
                    issues.append("\(boxDescription(left)) overlaps \(boxDescription(right))")
                }
            }
        }
    }

    private func validateLinesDoNotOverlap(issues: inout [String]) {
        for group in groupedLinesByBlock() {
            let sortedLines = group.sorted { left, right in
                if left.top == right.top {
                    return left.line < right.line
                }
                return left.top < right.top
            }

            for topIndex in sortedLines.indices {
                let top = sortedLines[topIndex]
                for bottom in sortedLines.dropFirst(topIndex + 1) {
                    if bottom.top >= top.bottom - tolerance {
                        break
                    }
                    if boxesOverlapHorizontally(top, bottom) {
                        issues.append("\(boxDescription(top)) collides vertically with \(boxDescription(bottom))")
                    }
                }
            }
        }
    }

    private func boxesOverlapHorizontally(_ left: Box, _ right: Box) -> Bool {
        min(left.right, right.right) > max(left.left, right.left) + tolerance
    }

    private func groupedWordsByLine() -> [[Box]] {
        Dictionary(grouping: words) { box in
            "\(box.page):\(box.paragraph):\(box.block):\(box.line)"
        }.values.map(Array.init)
    }

    private func groupedLinesByBlock() -> [[Box]] {
        Dictionary(grouping: lines) { box in
            "\(box.page):\(box.paragraph):\(box.block)"
        }.values.map(Array.init)
    }

    private func boxDescription(_ box: Box) -> String {
        "page \(box.page) paragraph \(box.paragraph) block \(box.block) line \(box.line) word \(box.word) '\(box.text)'"
    }

    private static func parse(line: String) throws -> Box {
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard columns.count >= 12,
              let level = Int(columns[0]),
              let page = Int(columns[1]),
              let paragraph = Int(columns[2]),
              let block = Int(columns[3]),
              let lineNumber = Int(columns[4]),
              let word = Int(columns[5]),
              let left = Double(columns[6]),
              let top = Double(columns[7]),
              let width = Double(columns[8]),
              let height = Double(columns[9])
        else {
            throw PDFVisualLayoutValidationError.invalidTSVLine(line)
        }

        return Box(
            level: level,
            page: page,
            paragraph: paragraph,
            block: block,
            line: lineNumber,
            word: word,
            left: left,
            top: top,
            width: width,
            height: height,
            text: columns[11...].joined(separator: "\t"),
        )
    }

    private let tolerance = 0.5
}

private enum PDFVisualLayoutValidationError: Error {
    case invalidTSVLine(String)
}
