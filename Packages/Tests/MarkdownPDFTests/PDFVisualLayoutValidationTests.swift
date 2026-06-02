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

    @Test("Syntax-colored manuscript passes visual witness stack")
    func syntaxColoredManuscriptPassesVisualWitnessStack() throws {
        let data = try syntaxColoringManuscriptPDF()
        let url = try PDFValidation.temporaryPDF(name: "syntax-coloring-manuscript", data: data)
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")

        #expect(pageCount >= 2)
        #expect(streamText.contains("0.050 0.200 0.550 rg"))
        #expect(streamText.contains("0.280 0.380 0.280 rg"))
        try PDFValidation.writeArtifact(data, name: "syntax-coloring-manuscript.pdf")

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "syntax-coloring-manuscript/text.txt")
        let normalizedText = normalizedExtractedText(textResult.output)
        #expect(normalizedText.contains("Portable Syntax Coloring Manuscript"))
        #expect(normalizedText.contains("Source coloring must preserve extraction and spacing."))
        #expect(normalizedText.contains("TabbedSyntaxColoringWitnessLongIdent"))
        #expect(normalizedText.contains("plainUnsupported"))
        #expect(normalizedText.contains("Syntax Coloring Manuscript Exit Marker"))

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "syntax-coloring-manuscript/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()

        #expect(popplerLayout.pages.count == pageCount)
        #expect(popplerLayout.words.count > 220)
        #expect(
            popplerIssues.isEmpty,
            "Syntax-colored manuscript Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "syntax-coloring-manuscript/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()

        #expect(mupdfLayout.pages.count == pageCount)
        #expect(mupdfLayout.glyphs.count(where: { !$0.isWhitespace }) > 1200)
        #expect(
            mupdfIssues.isEmpty,
            "Syntax-colored manuscript MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "syntax-coloring-manuscript/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "syntax-coloring-manuscript/mupdf-render.log")

        var rasterIssues: [String] = []
        for page in 1 ... pageCount {
            let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
            let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
            try PDFValidation.copyArtifact(
                from: poppler.pnmURLs[page - 1],
                name: "syntax-coloring-manuscript-pages/poppler/page-\(page).ppm",
            )
            try PDFValidation.copyArtifact(
                from: mupdf.pnmURLs[page - 1],
                name: "syntax-coloring-manuscript-pages/mupdf/page-\(page).pnm",
            )
            rasterIssues += rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage).map {
                "page \(page): \($0)"
            }
        }

        #expect(
            rasterIssues.isEmpty,
            "Syntax-colored manuscript raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
        )
    }

    @Test("RTL manuscript passes visual witness stack")
    func rtlManuscriptPassesVisualWitnessStack() throws {
        let data = try rtlManuscriptPDF()
        let url = try PDFValidation.temporaryPDF(name: "rtl-manuscript", data: data)
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount
        let hebrewWord = "\u{05D0}\u{05D1}\u{05D2}\u{05D3}"
        let arabicWord = "\u{0633}\u{0644}\u{0627}\u{0645}"
        let arabicIndic12 = "\u{0661}\u{0662}"

        #expect(pageCount >= 2)
        #expect(inspector.hasValidXrefOffsets())
        #expect(inspector.streamLengthsMatch())
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "RTL manuscript PDF structure issues:\n\(inspector.canonicalStructureIssues().joined(separator: "\n"))",
        )
        #expect(inspector.text.contains("/Subtype /Type0"))
        #expect(inspector.text.contains("/Subtype /CIDFontType2"))
        #expect(inspector.text.contains("/FontFile2"))
        #expect(inspector.text.contains("/ToUnicode"))
        let mirrorCIDBase = try Int(TrueTypeFontParser()
            .parse(SyntheticTrueTypeFont.data(glyphProfile: .rtlWitness, includeGlyphOutlines: true))
            .maxp
            .numGlyphs)
        let mirroredCodes = (1 ... 8).map { mirrorCIDBase + $0 }
        for code in mirroredCodes {
            let codeHex = Self.pdfHex(code)
            #expect(
                inspector.streams.contains { $0.body.contains("\(codeHex) Tj") },
                "RTL manuscript did not emit mirrored CID \(codeHex)",
            )
        }
        #expect(inspector.text.contains("\(Self.pdfHex(mirrorCIDBase + 1)) \(Self.pdfHex(mirrorCIDBase + 2)) <0028>"))
        #expect(inspector.text.contains("\(Self.pdfHex(mirrorCIDBase + 3)) <003C>"))
        #expect(inspector.text.contains("\(Self.pdfHex(mirrorCIDBase + 4)) <003E>"))
        #expect(inspector.text.contains("\(Self.pdfHex(mirrorCIDBase + 5)) <005B>"))
        #expect(inspector.text.contains("\(Self.pdfHex(mirrorCIDBase + 6)) <005D>"))
        #expect(inspector.text.contains("\(Self.pdfHex(mirrorCIDBase + 7)) <007B>"))
        #expect(inspector.text.contains("\(Self.pdfHex(mirrorCIDBase + 8)) <007D>"))

        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        try PDFValidation.writeTextArtifact(Self.rtlManuscriptManifest, name: "rtl-manuscript/README.txt")
        try PDFValidation.writeArtifact(data, name: "rtl-manuscript.pdf")

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "rtl-manuscript/text.txt")
        let normalizedText = normalizedExtractedText(textResult.output)
        #expect(normalizedText.contains("RTLPARATOKENA"))
        #expect(normalizedText.contains("ULISTTOKENA"))
        #expect(normalizedText.contains("OLISTTOKENA"))
        #expect(normalizedText.contains("QUOTETOKENA"))
        #expect(normalizedText.contains("ROWA"))

        let rawTextResult = try PDFValidation.pdftotextRaw(url: url)
        try #require(rawTextResult.exitCode == 0, "pdftotext -raw failed:\n\(rawTextResult.output)")
        try PDFValidation.writeTextArtifact(rawTextResult.output, name: "rtl-manuscript/raw-text.txt")
        let compactRawText = compactLogicalExtractedText(rawTextResult.output)
        #expect(compactRawText.contains("\(hebrewWord)(123)CODE\(arabicWord)\(arabicIndic12)RTLPARATOKENA."))
        #expect(compactRawText.contains("\(arabicWord)[CODE]\(hebrewWord)ULISTTOKENA."))
        #expect(compactRawText.contains("\(hebrewWord)\"CODE\"\(arabicWord)OLISTTOKENA."))
        #expect(compactRawText.contains("\(arabicWord)(123)\(hebrewWord)QUOTETOKENA."))
        #expect(compactRawText.contains("\(hebrewWord)HEADER"))
        #expect(compactRawText.contains("\(arabicWord)\(arabicIndic12)ROWA"))

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "rtl-manuscript/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()

        #expect(popplerLayout.pages.count == pageCount)
        #expect(popplerLayout.words.count > 90)
        #expect(
            popplerIssues.isEmpty,
            "RTL manuscript Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "rtl-manuscript/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues(allowRightToLeftRuns: true)

        #expect(mupdfLayout.pages.count == pageCount)
        #expect(mupdfLayout.glyphs.count(where: { !$0.isWhitespace }) > 500)
        #expect(
            mupdfIssues.isEmpty,
            "RTL manuscript MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "rtl-manuscript/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "rtl-manuscript/mupdf-render.log")

        var rasterIssues: [String] = []
        for page in 1 ... pageCount {
            let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
            let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
            try PDFValidation.copyArtifact(
                from: poppler.pnmURLs[page - 1],
                name: "rtl-manuscript-pages/poppler/page-\(page).ppm",
            )
            try PDFValidation.copyArtifact(
                from: mupdf.pnmURLs[page - 1],
                name: "rtl-manuscript-pages/mupdf/page-\(page).pnm",
            )
            rasterIssues += rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage).map {
                "page \(page): \($0)"
            }
        }

        #expect(
            rasterIssues.isEmpty,
            "RTL manuscript raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
        )
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

    @Test("Hard Markdown fixture passes visual witness stack")
    func hardMarkdownFixturePassesVisualWitnessStack() throws {
        let data = try hardMarkdownFixturePDF()
        let url = try PDFValidation.temporaryPDF(name: "hard-markdown-corpus", data: data)
        let pageCount = PDFInspector(data).pageCount

        #expect(pageCount >= 8)
        try PDFValidation.writeArtifact(data, name: "hard-markdown-corpus.pdf")

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "hard-markdown-corpus/text.txt")
        let normalizedText = normalizedExtractedText(textResult.output)
        #expect(normalizedText.contains("Portable Hard Markdown Corpus"))
        #expect(normalizedText.contains("Raw HTML fallback for the hard corpus"))
        #expect(normalizedText.contains("Hard Fixture Exit Marker"))

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "hard-markdown-corpus/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()

        #expect(popplerLayout.pages.count == pageCount)
        #expect(popplerLayout.words.count > 850)
        #expect(
            popplerIssues.isEmpty,
            "Hard Markdown fixture Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "hard-markdown-corpus/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()

        #expect(mupdfLayout.pages.count == pageCount)
        #expect(mupdfLayout.glyphs.count(where: { !$0.isWhitespace }) > 4500)
        #expect(
            mupdfIssues.isEmpty,
            "Hard Markdown fixture MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "hard-markdown-corpus/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "hard-markdown-corpus/mupdf-render.log")

        var rasterIssues: [String] = []
        for page in 1 ... pageCount {
            let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
            let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
            try PDFValidation.copyArtifact(
                from: poppler.pnmURLs[page - 1],
                name: "hard-markdown-corpus-pages/poppler/page-\(page).ppm",
            )
            try PDFValidation.copyArtifact(
                from: mupdf.pnmURLs[page - 1],
                name: "hard-markdown-corpus-pages/mupdf/page-\(page).pnm",
            )
            rasterIssues += rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage).map {
                "page \(page): \($0)"
            }
        }

        #expect(
            rasterIssues.isEmpty,
            "Hard Markdown fixture raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
        )
    }

    @Test("Crazy Markdown fixture passes visual witness stack")
    func crazyMarkdownFixturePassesVisualWitnessStack() throws {
        let data = try crazyMarkdownFixturePDF()
        let url = try PDFValidation.temporaryPDF(name: "crazy-markdown-torture", data: data)
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount

        #expect(pageCount >= 6)
        try PDFValidation.writeArtifact(data, name: "crazy-markdown-torture.pdf")

        let verticalRuleLines = inspector.streams.flatMap { stream in
            verticalRuleOperatorLines(in: stream.body)
        }
        #expect(
            verticalRuleLines.isEmpty,
            "Crazy Markdown fixture emitted unexpected vertical rule operators:\n\(verticalRuleLines.joined(separator: "\n"))",
        )

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "crazy-markdown-torture/text.txt")
        let normalizedText = normalizedExtractedText(textResult.output)
        #expect(normalizedText.contains("Crazy Markdown Torture Manuscript"))
        #expect(normalizedText.contains("DeepListLevelThreeMarker"))
        #expect(normalizedText.contains("QuoteBulletTwoMarker"))
        #expect(normalizedText.contains("Crazy Torture Exit Marker"))
        #expect(normalizedText.contains("Caf?"))
        #expect(normalizedText.contains("cafe?"))

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "crazy-markdown-torture/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()

        #expect(popplerLayout.pages.count == pageCount)
        #expect(popplerLayout.words.count > 1000)
        #expect(
            popplerIssues.isEmpty,
            "Crazy Markdown fixture Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "crazy-markdown-torture/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()

        #expect(mupdfLayout.pages.count == pageCount)
        #expect(mupdfLayout.glyphs.count(where: { !$0.isWhitespace }) > 6500)
        #expect(
            mupdfIssues.isEmpty,
            "Crazy Markdown fixture MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "crazy-markdown-torture/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "crazy-markdown-torture/mupdf-render.log")

        var rasterIssues: [String] = []
        for page in 1 ... pageCount {
            let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
            let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
            try PDFValidation.copyArtifact(
                from: poppler.pnmURLs[page - 1],
                name: "crazy-markdown-torture-pages/poppler/page-\(page).ppm",
            )
            try PDFValidation.copyArtifact(
                from: mupdf.pnmURLs[page - 1],
                name: "crazy-markdown-torture-pages/mupdf/page-\(page).pnm",
            )
            rasterIssues += rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage).map {
                "page \(page): \($0)"
            }
        }

        #expect(
            rasterIssues.isEmpty,
            "Crazy Markdown fixture raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
        )
    }

    @Test("A4 manuscript fixture passes visual witness stack")
    func a4ManuscriptFixturePassesVisualWitnessStack() throws {
        let data = try a4ManuscriptFixturePDF()
        let url = try PDFValidation.temporaryPDF(name: "a4-manuscript", data: data)
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount

        #expect(pageCount >= 5)
        try PDFValidation.writeArtifact(data, name: "a4-manuscript.pdf")

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")

        let infoResult = try PDFValidation.pdfinfo(url: url)
        try #require(infoResult.exitCode == 0, "pdfinfo failed:\n\(infoResult.output)")
        try PDFValidation.writeTextArtifact(infoResult.output, name: "a4-manuscript/pdfinfo.txt")
        let info = PDFValidation.parsedInfo(from: infoResult)
        #expect(info["Pages"] == "\(pageCount)")
        #expect(info["Page size"]?.contains("595.28 x 841.89 pts") == true)

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "a4-manuscript/text.txt")
        let normalizedText = normalizedExtractedText(textResult.output)
        #expect(normalizedText.contains("Portable A4 Manuscript Fixture"))
        #expect(normalizedText.contains("Table of Contents"))
        #expect(normalizedText.contains("A4 Manuscript Exit Marker"))
        #expect(normalizedText.contains("Unsupported A4 manuscript chart"))

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "a4-manuscript/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()

        #expect(popplerLayout.pages.count == pageCount)
        #expect(popplerLayout.words.count > 1600)
        #expect(
            popplerIssues.isEmpty,
            "A4 manuscript fixture Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "a4-manuscript/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()

        #expect(mupdfLayout.pages.count == pageCount)
        #expect(mupdfLayout.glyphs.count(where: { !$0.isWhitespace }) > 9000)
        #expect(
            mupdfIssues.isEmpty,
            "A4 manuscript fixture MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "a4-manuscript/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "a4-manuscript/mupdf-render.log")

        var rasterIssues: [String] = []
        for page in 1 ... pageCount {
            let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
            let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
            try PDFValidation.copyArtifact(
                from: poppler.pnmURLs[page - 1],
                name: "a4-manuscript-pages/poppler/page-\(page).ppm",
            )
            try PDFValidation.copyArtifact(
                from: mupdf.pnmURLs[page - 1],
                name: "a4-manuscript-pages/mupdf/page-\(page).pnm",
            )
            rasterIssues += rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage).map {
                "page \(page): \($0)"
            }
        }

        #expect(
            rasterIssues.isEmpty,
            "A4 manuscript fixture raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
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
        #expect(inspector.text.contains("/CIDToGIDMap "))
        #expect(!inspector.text.contains("/CIDToGIDMap /Identity"))
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

    @Test("CJK and diacritics manuscript passes visual witness stack")
    func cjkAndDiacriticsManuscriptPassesVisualWitnessStack() throws {
        let data = try cjkDiacriticsManuscriptPDF()
        let url = try PDFValidation.temporaryPDF(name: "cjk-diacritics-manuscript", data: data)
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount

        #expect(pageCount >= 2)
        #expect(inspector.hasValidXrefOffsets())
        #expect(inspector.streamLengthsMatch())
        #expect(inspector.text.contains("/Subtype /Type0"))
        #expect(inspector.text.contains("/Subtype /CIDFontType2"))
        #expect(inspector.text.contains("/FontFile2"))
        #expect(inspector.text.contains("/ToUnicode"))
        #expect(inspector.text.contains("/CIDToGIDMap "))
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "CJK and diacritics canonical PDF structure failed:\n\(inspector.canonicalStructureReport())",
        )
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        try PDFValidation.writeArtifact(data, name: "cjk-diacritics-manuscript.pdf")

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "cjk-diacritics-manuscript/text.txt")
        let normalizedText = normalizedExtractedText(textResult.output)
        let compactText = textResult.output.filter { !$0.isWhitespace }
        #expect(normalizedText.contains("Latin text"))
        #expect(normalizedText.contains("1."))
        #expect(compactText.contains("漢字語漢字語"))
        #expect(compactText.contains("e\u{0301}"))
        #expect(compactText.contains("漢\u{0301}字語"))
        #expect(try compactText.unicodeScalars.contains(#require(UnicodeScalar(0x0301))))

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "cjk-diacritics-manuscript/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()

        #expect(popplerLayout.pages.count == pageCount)
        #expect(Set(popplerLayout.words.map(\.page)).count == pageCount)
        #expect(
            popplerIssues.isEmpty,
            "CJK and diacritics Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "cjk-diacritics-manuscript/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()

        #expect(mupdfLayout.pages.count == pageCount)
        #expect(mupdfLayout.glyphs.count(where: { !$0.isWhitespace }) > 500)
        #expect(
            mupdfIssues.isEmpty,
            "CJK and diacritics MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "cjk-diacritics-manuscript/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "cjk-diacritics-manuscript/mupdf-render.log")

        var rasterIssues: [String] = []
        for page in 1 ... pageCount {
            let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
            let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
            try PDFValidation.copyArtifact(
                from: poppler.pnmURLs[page - 1],
                name: "cjk-diacritics-manuscript-pages/poppler/page-\(page).ppm",
            )
            try PDFValidation.copyArtifact(
                from: mupdf.pnmURLs[page - 1],
                name: "cjk-diacritics-manuscript-pages/mupdf/page-\(page).pnm",
            )
            rasterIssues += rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage).map {
                "page \(page): \($0)"
            }
        }

        #expect(
            rasterIssues.isEmpty,
            "CJK and diacritics raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
        )
    }

    @Test("Embedded font public API profile passes visual witness stack")
    func embeddedFontPublicAPIProfilePassesVisualWitnessStack() throws {
        let data = try embeddedFontPublicAPIPDF()
        let url = try PDFValidation.temporaryPDF(name: "embedded-font-public-api", data: data)
        let inspector = PDFInspector(data)

        #expect(inspector.pageCount >= 2)
        #expect(inspector.text.contains("/Subtype /Type0"))
        #expect(inspector.text.contains("/Subtype /CIDFontType2"))
        #expect(inspector.text.contains("/FontFile2"))
        #expect(inspector.text.contains("/ToUnicode"))
        #expect(inspector.text.contains("/EF1"))
        #expect(inspector.text.contains("/EF2"))
        #expect(inspector.text.contains("/EF3"))
        #expect(inspector.text.contains("/EF4"))
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        try PDFValidation.writeArtifact(data, name: "embedded-font-public-api.pdf")

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "embedded-font-public-api/text.txt")
        let normalizedText = normalizedExtractedText(textResult.output)
        #expect(normalizedText.contains("PUBLIC EMBEDDED FONT PROFILE"))
        #expect(normalizedText.contains("BOLD ROLE"))
        #expect(normalizedText.contains("ITALIC ROLE"))
        #expect(normalizedText.contains("CODE ROLE"))

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "embedded-font-public-api/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()
        #expect(popplerLayout.pages.count == inspector.pageCount)
        #expect(popplerLayout.words.count > 120)
        #expect(
            popplerIssues.isEmpty,
            "Embedded font public API Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "embedded-font-public-api/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()
        #expect(mupdfLayout.pages.count == inspector.pageCount)
        #expect(mupdfLayout.glyphs.count(where: { !$0.isWhitespace }) > 700)
        #expect(
            mupdfIssues.isEmpty,
            "Embedded font public API MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: inspector.pageCount)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: inspector.pageCount)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "embedded-font-public-api/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "embedded-font-public-api/mupdf-render.log")

        var rasterIssues: [String] = []
        for page in 1 ... inspector.pageCount {
            let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
            let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
            try PDFValidation.copyArtifact(
                from: poppler.pnmURLs[page - 1],
                name: "embedded-font-public-api-pages/poppler/page-\(page).ppm",
            )
            try PDFValidation.copyArtifact(
                from: mupdf.pnmURLs[page - 1],
                name: "embedded-font-public-api-pages/mupdf/page-\(page).pnm",
            )
            rasterIssues += rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage).map {
                "page \(page): \($0)"
            }
        }

        #expect(
            rasterIssues.isEmpty,
            "Embedded font public API raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
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

    @Test("Code and quote spacing keeps following text separated")
    func codeAndQuoteSpacingKeepsFollowingTextSeparated() throws {
        let markdown = """
        # Quote Spacing Witness

        The first struct tracks surface characteristics in a single block:

        ```metal
        struct Surface {
            float3 baseColor;
            float shininess;
            float roughness;
            float emissive;
            float3 transmission;
            float indexOfRefraction;
            float CodeBlockEndToken;
        };
        ```

        > QuoteStartToken surface measurements should stay clear of the preceding code background and finish with QuoteEndToken

        AfterQuoteParagraph begins below the quote, with enough spacing to avoid a crammed transition.

        ```metal
        struct SurfaceRefraction {
            half3 transmission;
            half indexOfRefraction;
            half SecondCodeBlockEndToken;
        };
        ```

        > SecondQuoteStartToken the second quote is directly followed by a heading and ends with SecondQuoteEndToken

        ## AfterQuoteHeading

        AfterHeadingParagraph keeps normal flow below the heading.
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 420, height: 720),
                margins: PDFOptions.Margins(top: 42, right: 42, bottom: 42, left: 42),
                baseFontSize: 12,
                title: "Quote Spacing Witness",
            ),
        ).render(markdown: markdown)
        try PDFValidation.writeArtifact(data, name: "quote-spacing.pdf")

        let tsvResult = try PDFValidation.pdftotextTSV(data: data, name: "quote-spacing")
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "quote-spacing/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()

        #expect(
            popplerIssues.isEmpty,
            "Quote spacing Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let codeEnd = try word("CodeBlockEndToken;", in: popplerLayout)
        let quoteStart = try word("QuoteStartToken", in: popplerLayout)
        let quoteEnd = try word("QuoteEndToken", in: popplerLayout)
        let afterParagraph = try word("AfterQuoteParagraph", in: popplerLayout)
        let secondCodeEnd = try word("SecondCodeBlockEndToken;", in: popplerLayout)
        let secondQuoteStart = try word("SecondQuoteStartToken", in: popplerLayout)
        let secondQuoteEnd = try word("SecondQuoteEndToken", in: popplerLayout)
        let afterHeading = try word("AfterQuoteHeading", in: popplerLayout)

        #expect(quoteStart.page == codeEnd.page)
        #expect(afterParagraph.page == quoteEnd.page)
        #expect(secondQuoteStart.page == secondCodeEnd.page)
        #expect(quoteStart.top > codeEnd.bottom + 10)
        #expect(afterParagraph.top > quoteEnd.bottom + 4)
        #expect(secondQuoteStart.top > secondCodeEnd.bottom + 10)
        if afterHeading.page == secondQuoteEnd.page {
            #expect(afterHeading.top > secondQuoteEnd.bottom + 8)
        } else {
            #expect(afterHeading.page > secondQuoteEnd.page)
        }

        let structuredText = try PDFValidation.mutoolStructuredText(data: data, name: "quote-spacing-mupdf")
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "quote-spacing/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()

        #expect(
            mupdfIssues.isEmpty,
            "Quote spacing MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )
    }

    @Test("Source code witness stack catches crammed flow and glyph overlap")
    func sourceCodeWitnessStackCatchesCrammedFlowAndGlyphOverlap() throws {
        let longIdentifier = "PortableSourceCodeWitnessLongIdentifier"
            + String(repeating: "Segment", count: 14)
        let denseMetalLines = (1 ... 14).map { index in
            [
                "if ((rayMask & (1 << \(index))) != 0) {",
                "\tlet sample_\(index) = trace(payload[\(index)], \(longIdentifier)\(index))",
                "\taccumulator += sample_\(index).radiance * half3(0.125, 0.250, 0.500)",
                "}",
            ].joined(separator: "\n")
        }.joined(separator: "\n")
        let markdown = """
        # Source Code Witness

        This witness reproduces the code, quote, paragraph, and heading sequence
        that looked crammed in manual PDF artifacts.

        ```metal
        struct SurfaceWitness {
            half3 baseColor;
            half roughness;
            half metallic;
        };
        \(denseMetalLines)
        let SourceCodeEndToken = "source-code-end"
        ```

        > QuoteStartToken quoted analysis begins after the source block and must
        > not overlap the background rectangle or any glyph from the code block.
        > Quoted analysis ends before normal paragraph flow resumes QuoteEndToken

        AfterQuoteParagraph resumes normal flow after the quote with a visible gap AfterQuoteParagraphEndToken

        ## AfterQuoteHeadingToken

        AfterHeadingParagraph keeps heading flow away from the quote body.

        ```swift
        let wrappedSymbols = "\(String(repeating: "[]{}()<>+-=*/", count: 10))"
        let wrappedIdentifier = "\(longIdentifier)"
        let SecondCodeEndToken = "second-code-end"
        ```

        AfterSecondCodeParagraph resumes below the second code block.
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 360, height: 460),
                margins: PDFOptions.Margins(top: 36, right: 34, bottom: 36, left: 34),
                baseFontSize: 10,
                title: "Source Code Witness",
            ),
        ).render(markdown: markdown)
        let url = try PDFValidation.temporaryPDF(name: "source-code-spacing", data: data)
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount

        #expect(pageCount >= 4)
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        try PDFValidation.writeTextArtifact(Self.sourceCodeSpacingManifest, name: "source-code-spacing/README.txt")
        try PDFValidation.writeArtifact(data, name: "source-code-spacing.pdf")

        let verticalRuleLines = inspector.streams.flatMap { stream in
            verticalRuleOperatorLines(in: stream.body)
        }
        #expect(
            verticalRuleLines.isEmpty,
            "Source code witness emitted unexpected vertical rule operators:\n\(verticalRuleLines.joined(separator: "\n"))",
        )

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "source-code-spacing/text.txt")
        let normalizedText = normalizedExtractedText(textResult.output)
        #expect(normalizedText.contains("SourceCodeEndToken"))
        #expect(normalizedText.contains("QuoteStartToken"))
        #expect(normalizedText.contains("AfterQuoteHeadingToken"))
        #expect(normalizedText.contains("SecondCodeEndToken"))

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "source-code-spacing/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()

        #expect(popplerLayout.pages.count == pageCount)
        #expect(popplerLayout.words.count > 260)
        #expect(
            popplerIssues.isEmpty,
            "Source code spacing Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let codeEnd = try word("SourceCodeEndToken", in: popplerLayout)
        let quoteStart = try word("QuoteStartToken", in: popplerLayout)
        let quoteEnd = try word("QuoteEndToken", in: popplerLayout)
        let afterParagraph = try word("AfterQuoteParagraph", in: popplerLayout)
        let afterParagraphEnd = try word("AfterQuoteParagraphEndToken", in: popplerLayout)
        let afterHeading = try word("AfterQuoteHeadingToken", in: popplerLayout)
        let secondCodeEnd = try word("SecondCodeEndToken", in: popplerLayout)
        let afterSecondCode = try word("AfterSecondCodeParagraph", in: popplerLayout)

        expectVerticalGap(after: codeEnd, before: quoteStart, minimum: 10, context: "code block to quote")
        expectVerticalGap(after: quoteEnd, before: afterParagraph, minimum: 4, context: "quote to paragraph")
        expectVerticalGap(after: afterParagraphEnd, before: afterHeading, minimum: 8, context: "paragraph to heading")
        expectVerticalGap(after: secondCodeEnd, before: afterSecondCode, minimum: 8, context: "code block to paragraph")

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "source-code-spacing/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()

        #expect(mupdfLayout.pages.count == pageCount)
        #expect(mupdfLayout.glyphs.count(where: { !$0.isWhitespace }) > 1800)
        #expect(
            mupdfIssues.isEmpty,
            "Source code spacing MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "source-code-spacing/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "source-code-spacing/mupdf-render.log")

        var rasterIssues: [String] = []
        for page in 1 ... pageCount {
            let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
            let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
            try PDFValidation.copyArtifact(
                from: poppler.pnmURLs[page - 1],
                name: "source-code-spacing-pages/poppler/page-\(page).ppm",
            )
            try PDFValidation.copyArtifact(
                from: mupdf.pnmURLs[page - 1],
                name: "source-code-spacing-pages/mupdf/page-\(page).pnm",
            )
            rasterIssues += rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage).map {
                "page \(page): \($0)"
            }
        }

        #expect(
            rasterIssues.isEmpty,
            "Source code spacing raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
        )
    }

    @Test("Screenshot source-code regression witness covers spacing, strokes, and images")
    func screenshotSourceCodeRegressionWitnessCoversSpacingStrokesAndImages() throws {
        let assetsBaseURL = try TestImageAssets.directoryWithChartPNG()
        let longIdentifier = "ScreenshotRegressionWitnessLongIdentifier"
            + String(repeating: "Segment", count: 12)
        let repeatedRuns = (1 ... 5).map { index in
            """
            ```swift
            struct ScreenshotRegressionSection\(index) {
                let identifier = "\(longIdentifier)\(index)"
                let width = max(columnWidth, measuredGlyphAdvance + \(index))
                let ScreenshotCodeEndToken\(index) = "code-end-\(index)"
            }
            ```

            > ScreenshotQuoteStartToken\(index) quoted source analysis starts after code
            > and must remain clear of the previous code background.
            > > NestedQuoteStartToken\(index) nested quote pressure also stays indented.
            > ScreenshotQuoteEndToken\(index)

            ScreenshotAfterQuoteParagraph\(index) resumes after the quote with readable spacing.

            ### ScreenshotAfterQuoteHeadingToken\(index)

            ScreenshotAfterHeadingParagraph\(index) follows the heading without crowding.
            """
        }.joined(separator: "\n\n")
        let markdown = """
        # Screenshot Source Code Regression Witness

        This witness reproduces the screenshot-reported source-code flow with
        dense code, block quotes, headings, local figures, remote image fallback,
        and hostile reference-style image syntax.

        ```metal
        struct DirectTransition {
            float4 payload;
            float3 measuredNormal;
            let DirectCodeEndToken = "direct-code-end";
        };
        ```

        > DirectQuoteStartToken source comments must start below the code block.
        > DirectNestedQuoteToken nested source notes keep indentation only.
        > DirectQuoteEndToken

        ## DirectAfterQuoteHeadingToken

        DirectAfterHeadingParagraph begins after the quote-to-heading transition.

        \(repeatedRuns)

        ## Local and Remote Image Pressure

        The same local chart is placed twice. The PDF should reuse one image
        resource and draw it twice in normal document flow.

        ![Screenshot local chart first](local-chart.png)

        AfterFirstLocalImageParagraph proves the first image consumed vertical space.

        ![Screenshot local chart second](local-chart.png)

        AfterSecondLocalImageParagraph proves repeated image placement consumes space.

        Remote image fetching is outside the portable profile and must remain
        visible fallback text.

        ![Remote regression figure](https://example.com/source-regression.png)

        AfterRemoteImageParagraph follows the remote fallback text.

        Reference-style image syntax is hostile input for the current parser and
        must stay visible as text instead of disappearing or becoming an image.

        ![Reference style regression chart][screenshot-chart]

        [screenshot-chart]: local-chart.png "Reference style regression fallback text"

        AfterUnsupportedImageSyntaxParagraph ends the manuscript pressure case.
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 360, height: 460),
                margins: PDFOptions.Margins(top: 36, right: 34, bottom: 36, left: 34),
                baseFontSize: 10,
                title: "Screenshot Source Code Regression Witness",
            ),
        ).render(markdown: markdown, assetsBaseURL: assetsBaseURL)
        let url = try PDFValidation.temporaryPDF(name: "screenshot-source-code-regressions", data: data)
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")

        #expect(pageCount >= 5)
        #expect(inspector.hasValidXrefOffsets())
        #expect(inspector.streamLengthsMatch())
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "Screenshot source-code witness PDF structure issues:\n\(inspector.canonicalStructureIssues().joined(separator: "\n"))",
        )
        #expect(imageXObjectCount(in: inspector.text) == 1)
        #expect(imageDrawOperatorCount(in: streamText) == 2)

        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        try PDFValidation.writeTextArtifact(Self.screenshotSourceCodeRegressionManifest, name: "screenshot-source-code-regressions/README.txt")
        try PDFValidation.writeArtifact(data, name: "screenshot-source-code-regressions.pdf")

        let verticalRuleLines = inspector.streams.flatMap { stream in
            verticalRuleOperatorLines(in: stream.body)
        }
        #expect(
            verticalRuleLines.isEmpty,
            "Screenshot source-code witness emitted unexpected vertical rule operators:\n\(verticalRuleLines.joined(separator: "\n"))",
        )

        let qpdf = try PDFValidation.qpdfCheck(url: url)
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")

        let textResult = try PDFValidation.pdftotext(url: url)
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try PDFValidation.writeTextArtifact(textResult.output, name: "screenshot-source-code-regressions/text.txt")
        let normalizedText = normalizedExtractedText(textResult.output)
        #expect(normalizedText.contains("DirectCodeEndToken"))
        #expect(normalizedText.contains("DirectQuoteStartToken"))
        #expect(normalizedText.contains("DirectAfterQuoteHeadingToken"))
        #expect(normalizedText.contains("ScreenshotCodeEndToken5"))
        #expect(normalizedText.contains("ScreenshotQuoteStartToken5"))
        #expect(normalizedText.contains("ScreenshotAfterQuoteHeadingToken5"))
        #expect(normalizedText.contains("[Remote image: Remote regression figure]"))
        #expect(normalizedText.contains("Reference style regression chart"))
        #expect(normalizedText.contains("Reference style regression fallback text"))
        #expect(normalizedText.contains("AfterUnsupportedImageSyntaxParagraph"))

        let tsvResult = try PDFValidation.pdftotextTSV(url: url)
        try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed:\n\(tsvResult.output)")
        try PDFValidation.writeTextArtifact(tsvResult.output, name: "screenshot-source-code-regressions/poppler.tsv")
        let popplerLayout = try PopplerTextLayout(tsv: tsvResult.output)
        let popplerIssues = popplerLayout.visualLayoutIssues()

        #expect(popplerLayout.pages.count == pageCount)
        #expect(popplerLayout.words.count > 420)
        #expect(
            popplerIssues.isEmpty,
            "Screenshot source-code Poppler layout issues:\n\(popplerIssues.joined(separator: "\n"))",
        )

        let directCodeEnd = try word("DirectCodeEndToken", in: popplerLayout)
        let directQuoteStart = try word("DirectQuoteStartToken", in: popplerLayout)
        let directQuoteEnd = try word("DirectQuoteEndToken", in: popplerLayout)
        let directHeading = try word("DirectAfterQuoteHeadingToken", in: popplerLayout)
        let firstCodeEnd = try word("ScreenshotCodeEndToken1", in: popplerLayout)
        let firstQuoteStart = try word("ScreenshotQuoteStartToken1", in: popplerLayout)
        let firstQuoteEnd = try word("ScreenshotQuoteEndToken1", in: popplerLayout)
        let firstAfterParagraph = try word("ScreenshotAfterQuoteParagraph1", in: popplerLayout)
        let firstHeading = try word("ScreenshotAfterQuoteHeadingToken1", in: popplerLayout)
        let lastCodeEnd = try word("ScreenshotCodeEndToken5", in: popplerLayout)
        let lastQuoteStart = try word("ScreenshotQuoteStartToken5", in: popplerLayout)
        let afterRemoteImage = try word("AfterRemoteImageParagraph", in: popplerLayout)
        let afterUnsupportedImage = try word("AfterUnsupportedImageSyntaxParagraph", in: popplerLayout)

        expectVerticalGap(after: directCodeEnd, before: directQuoteStart, minimum: 10, context: "direct code block to quote")
        expectVerticalGap(after: directQuoteEnd, before: directHeading, minimum: 8, context: "direct quote to heading")
        expectVerticalGap(after: firstCodeEnd, before: firstQuoteStart, minimum: 10, context: "repeated code block to quote")
        expectVerticalGap(after: firstQuoteEnd, before: firstAfterParagraph, minimum: 4, context: "repeated quote to paragraph")
        expectVerticalGap(after: firstAfterParagraph, before: firstHeading, minimum: 8, context: "repeated paragraph to heading")
        expectVerticalGap(after: lastCodeEnd, before: lastQuoteStart, minimum: 10, context: "last code block to quote")
        expectVerticalGap(after: afterRemoteImage, before: afterUnsupportedImage, minimum: 10, context: "remote fallback to unsupported image text")

        let structuredText = try PDFValidation.mutoolStructuredText(url: url)
        try #require(structuredText.exitCode == 0, "mutool structured text failed:\n\(structuredText.output)")
        try PDFValidation.writeTextArtifact(structuredText.output, name: "screenshot-source-code-regressions/mupdf-stext.xml")
        let mupdfLayout = try MuPDFStructuredText(xml: structuredText.output)
        let mupdfIssues = mupdfLayout.characterQuadIssues()

        #expect(mupdfLayout.pages.count == pageCount)
        #expect(mupdfLayout.glyphs.count(where: { !$0.isWhitespace }) > 2600)
        #expect(
            mupdfIssues.isEmpty,
            "Screenshot source-code MuPDF layout issues:\n\(mupdfIssues.joined(separator: "\n"))",
        )

        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount)
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")
        try PDFValidation.writeTextArtifact(poppler.result.output, name: "screenshot-source-code-regressions/poppler-render.log")
        try PDFValidation.writeTextArtifact(mupdf.result.output, name: "screenshot-source-code-regressions/mupdf-render.log")

        var rasterIssues: [String] = []
        for page in 1 ... pageCount {
            let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
            let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
            try PDFValidation.copyArtifact(
                from: poppler.pnmURLs[page - 1],
                name: "screenshot-source-code-regressions-pages/poppler/page-\(page).ppm",
            )
            try PDFValidation.copyArtifact(
                from: mupdf.pnmURLs[page - 1],
                name: "screenshot-source-code-regressions-pages/mupdf/page-\(page).pnm",
            )
            rasterIssues += rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage).map {
                "page \(page): \($0)"
            }
        }

        #expect(
            rasterIssues.isEmpty,
            "Screenshot source-code raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
        )
    }

    @Test("Screenshot source-code regression witness rejects mutated failures")
    func screenshotSourceCodeRegressionWitnessRejectsMutatedFailures() throws {
        let strokeMutation = """
        52 720 m
        52 660 l
        S
        """
        #expect(!verticalRuleOperatorLines(in: strokeMutation).isEmpty)

        let mutatedLayout = try PopplerTextLayout(tsv: """
        level\tpage_num\tpar_num\tblock_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
        1\t1\t0\t0\t0\t0\t0.000000\t0.000000\t220.000000\t220.000000\t-1\t###PAGE###
        4\t1\t0\t1\t0\t0\t10.000000\t90.000000\t120.000000\t10.000000\t-1\t###LINE###
        5\t1\t0\t1\t0\t0\t10.00\t90.00\t80.00\t10.00\t100\tDirectCodeEndToken
        4\t1\t0\t1\t1\t0\t10.000000\t94.000000\t130.000000\t10.000000\t-1\t###LINE###
        5\t1\t0\t1\t1\t0\t10.00\t94.00\t120.00\t10.00\t100\tDirectQuoteStartToken
        4\t1\t0\t1\t2\t0\t10.000000\t130.000000\t120.000000\t10.000000\t-1\t###LINE###
        5\t1\t0\t1\t2\t0\t10.00\t130.00\t60.00\t10.00\t100\tOverlapLeft
        5\t1\t0\t1\t2\t1\t50.00\t130.00\t60.00\t10.00\t100\tOverlapRight
        """)
        let mutatedCodeEnd = try word("DirectCodeEndToken", in: mutatedLayout)
        let mutatedQuoteStart = try word("DirectQuoteStartToken", in: mutatedLayout)
        let mutatedStructuredText = try MuPDFStructuredText(xml: """
        <?xml version="1.0"?>
        <document filename="mutated-source-code-witness.pdf">
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
        let mutatedPopplerRaster = try PNMImage(data: pnmImage(width: 20, height: 20, inkBox: 2 ... 5))
        let mutatedMuPDFRaster = try PNMImage(data: pnmImage(width: 20, height: 20, inkBox: 16 ... 19))

        #expect(mutatedLayout.visualLayoutIssues().contains { $0.contains("overlaps") })
        #expect(mutatedStructuredText.characterQuadIssues().contains { $0.contains("overlaps") })
        #expect(
            rasterComparisonIssues(poppler: mutatedPopplerRaster, mupdf: mutatedMuPDFRaster)
                .contains { $0.contains("ink bounds differ") },
        )
        #expect(
            verticalGapIssue(
                after: mutatedCodeEnd,
                before: mutatedQuoteStart,
                minimum: 10,
                context: "mutated code block to quote",
            ) != nil,
        )
        #expect(imageXObjectCount(in: "") != 1)
        #expect(imageDrawOperatorCount(in: "/Im1 Do") != 2)

        let mutatedText = normalizedExtractedText("DirectCodeEndToken DirectQuoteStartToken")
        #expect(!mutatedText.contains("[Remote image: Remote regression figure]"))
        #expect(!mutatedText.contains("Reference style regression fallback text"))
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

    @Test("MuPDF character quad validator allows ToUnicode expansion continuations")
    func muPDFCharacterQuadValidatorAllowsToUnicodeExpansionContinuations() throws {
        let layout = try MuPDFStructuredText(xml: """
        <?xml version="1.0"?>
        <document filename="ligature.pdf">
        <page id="page1" width="100" height="100">
        <block bbox="10 10 40 24" justify="unknown">
        <line bbox="10 10 40 24" wmode="0" dir="1 0" flags="0" text="file">
        <font name="Ligature" size="12">
        <char quad="10 12 20 12 10 22 20 22" x="10" y="22" c="f"/>
        <char quad="20 10 20 10 20 24 20 24" x="20" y="22" c="i"/>
        <char quad="20 12 25 12 20 22 25 22" x="20" y="22" c="l"/>
        <char quad="25 12 34 12 25 22 34 22" x="25" y="22" c="e"/>
        </font>
        </line>
        </block>
        </page>
        </document>
        """)

        #expect(layout.characterQuadIssues().isEmpty)
    }

    @Test("MuPDF character quad validator rejects isolated zero-width glyphs")
    func muPDFCharacterQuadValidatorRejectsIsolatedZeroWidthGlyphs() throws {
        let layout = try MuPDFStructuredText(xml: """
        <?xml version="1.0"?>
        <document filename="zero-width.pdf">
        <page id="page1" width="100" height="100">
        <block bbox="10 10 40 24" justify="unknown">
        <line bbox="10 10 40 24" wmode="0" dir="1 0" flags="0" text="A">
        <font name="Broken" size="12">
        <char quad="15 12 15 12 15 22 15 22" x="15" y="22" c="A"/>
        </font>
        </line>
        </block>
        </page>
        </document>
        """)

        #expect(layout.characterQuadIssues().contains { $0.contains("non-positive size") })
    }

    @Test("Source code witness rule detector rejects stroked and filled vertical rules")
    func sourceCodeWitnessRuleDetectorRejectsStrokedAndFilledVerticalRules() {
        let stream = """
        q
        54 700 m
        54 620 l
        S
        54 620 1.5 80 re
        f
        Q
        """

        #expect(verticalRuleOperatorLines(in: stream) == ["S", "54 620 1.5 80 re"])
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

    private func hardMarkdownFixturePDF() throws -> Data {
        let assetsBaseURL = try TestImageAssets.directoryWithChartPNG()
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                title: "Portable Hard Markdown Corpus",
                tableOfContents: .enabled,
            ),
        ).render(
            markdown: fixture(named: "hard-markdown-corpus.md"),
            assetsBaseURL: assetsBaseURL,
        )
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        return data
    }

    private func crazyMarkdownFixturePDF() throws -> Data {
        let assetsBaseURL = try TestImageAssets.directoryWithChartPNG()
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                title: "Crazy Markdown Torture Manuscript",
                tableOfContents: .enabled,
            ),
        ).render(
            markdown: fixture(named: "crazy-markdown-torture.md"),
            assetsBaseURL: assetsBaseURL,
        )
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        return data
    }

    private func syntaxColoringManuscriptPDF() throws -> Data {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                title: "Portable Syntax Coloring Manuscript",
                codeSyntaxHighlighting: .enabled,
            ),
        ).render(markdown: fixture(named: "syntax-coloring-manuscript.md"))
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        return data
    }

    private func rtlManuscriptPDF() throws -> Data {
        let hebrewWord = "\u{05D0}\u{05D1}\u{05D2}\u{05D3}"
        let hebrewPair = "\u{05D0}\u{05D1}"
        let arabicWord = "\u{0633}\u{0644}\u{0627}\u{0645}"
        let arabicIndic12 = "\u{0661}\u{0662}"
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .rtlWitness, includeGlyphOutlines: true)
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "MarkdownPDF RTL Witness")
        let repeatedParagraphs = ["A", "B", "C", "D", "E", "F", "G", "H"].map { suffix in
            "\(hebrewWord) (123) CODE \(arabicWord) \(arabicIndic12) RTLPARATOKEN\(suffix)."
        }.joined(separator: "\n\n")
        let markdown = """
        # \(hebrewWord) RTL MANUSCRIPT

        ## \(arabicWord) CODE 123 \(hebrewWord)

        \(repeatedParagraphs)

        - \(arabicWord) [CODE] \(hebrewWord) ULISTTOKENA.
        - \(hebrewWord) {CODE} \(arabicWord) ULISTTOKENB.

        1. \(hebrewWord) "CODE" \(arabicWord) OLISTTOKENA.
        2. \(arabicWord) <CODE> \(hebrewPair) OLISTTOKENB.

        > \(arabicWord) (123) \(hebrewWord) QUOTETOKENA.
        > \(hebrewWord) '\(arabicWord)' QUOTETOKENB.

        | \(hebrewWord) HEADER | \(arabicWord) HEADER |
        |---|---|
        | \(hebrewWord) (123) CODE | \(arabicWord) \(arabicIndic12) ROWA |
        | \(arabicWord) [CODE] | \(hebrewWord) 123 ROWB |
        | \(hebrewPair) {CODE} | \(arabicWord) 123 ROWC |

        \(arabicWord) (123) \(hebrewWord) RTLMIRRORTOKEN.
        """

        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 300, height: 360),
                margins: PDFOptions.Margins(top: 28, right: 28, bottom: 28, left: 28),
                baseFontSize: 10,
                embeddedFonts: .allRoles(source),
                title: "RTL Manuscript Witness",
            ),
        ).render(markdown: markdown)
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        return data
    }

    private func a4ManuscriptFixturePDF() throws -> Data {
        let assetsBaseURL = try TestImageAssets.directoryWithChartPNG()
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: .a4,
                margins: PDFOptions.Margins(top: 56, right: 54, bottom: 56, left: 54),
                baseFontSize: 11,
                title: "Portable A4 Manuscript Fixture",
                tableOfContents: .enabled,
            ),
        ).render(
            markdown: fixture(named: "a4-manuscript.md"),
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

    private func embeddedFontPublicAPIPDF() throws -> Data {
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "MarkdownPDF Public Fixture")
        let denseParagraphs = Array(
            repeating: "WIDE WILLIAM MINIMUM MARGIN ALPHA BETA GAMMA DELTA VECTOR SPACE CID TEXT STAYS ALIGNED",
            count: 18,
        ).joined(separator: "\n\n")
        let markdown = """
        # PUBLIC EMBEDDED FONT PROFILE

        \(denseParagraphs)

        ## STYLE ROLES

        PLAIN ROLE **BOLD ROLE** *ITALIC ROLE* `CODE ROLE`

        [OPEN FONT](https://example.com/fonts) LINK TEXT STAYS ALIGNED

        | AREA | VALUE |
        |---|---|
        | WIDTH | WIDE WILLIAM MINIMUM MARGIN |
        | CID | TEXT STAYS ALIGNED |
        | RASTER | WITNESS STACK |

        ```text
        CODE ROLE WIDE WILLIAM
        MONO SPACE TEST
        ```

        ```mermaid
        flowchart TD
        A[PUBLIC FONT] --> B[CID TEXT]
        B --> C[RASTER WITNESS]
        ```
        """

        return try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                embeddedFonts: .allRoles(source),
                title: "Embedded Font Public API Witness",
            ),
        ).render(markdown: markdown)
    }

    private func cjkDiacriticsManuscriptPDF() throws -> Data {
        let fontData = SyntheticTrueTypeFont.data(
            cmapFormat: 12,
            glyphProfile: .cjkDiacriticWitness,
            includeGlyphOutlines: true,
        )
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "MarkdownPDF CJK Diacritic Fixture")

        return try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                embeddedFonts: .allRoles(source),
                title: "CJK Diacritics Manuscript Witness",
            ),
        ).render(markdown: fixture(named: "cjk-diacritics-manuscript.md"))
    }

    private func fixture(named name: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }

    private func word(_ text: String, in layout: PopplerTextLayout) throws -> PopplerTextLayout.Box {
        try #require(layout.words.first { $0.text == text }, "Missing extracted word \(text)")
    }

    private func expectVerticalGap(
        after upper: PopplerTextLayout.Box,
        before lower: PopplerTextLayout.Box,
        minimum: Double,
        context: String,
    ) {
        let issue = verticalGapIssue(after: upper, before: lower, minimum: minimum, context: context)
        #expect(issue == nil, "\(issue ?? "")")
    }

    private func verticalGapIssue(
        after upper: PopplerTextLayout.Box,
        before lower: PopplerTextLayout.Box,
        minimum: Double,
        context: String,
    ) -> String? {
        if lower.page == upper.page {
            return lower.top > upper.bottom + minimum
                ? nil
                : "\(context) gap was too small: \(lower.top - upper.bottom)"
        }

        return lower.page > upper.page ? nil : "\(context) moved backward across pages"
    }

    private func imageXObjectCount(in pdfText: String) -> Int {
        pdfText.components(separatedBy: "/Subtype /Image").count - 1
    }

    private func imageDrawOperatorCount(in streamText: String) -> Int {
        streamText.components(separatedBy: " Do").count - 1
    }

    private func verticalRuleOperatorLines(in stream: String) -> [String] {
        let lines = stream
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var matches: [String] = []
        var pendingMove: (x: Double, y: Double)?
        var pendingLine: (x1: Double, y1: Double, x2: Double, y2: Double)?

        for line in lines {
            if isSkinnyVerticalRectangleOperator(line) {
                matches.append(line)
                continue
            }

            if isInlineSkinnyVerticalPathStroke(line) {
                matches.append(line)
                continue
            }

            if let move = moveOperatorPoint(line) {
                pendingMove = move
                pendingLine = nil
                continue
            }

            if let linePoint = lineOperatorPoint(line),
               let move = pendingMove
            {
                pendingLine = (move.x, move.y, linePoint.x, linePoint.y)
                continue
            }

            if isStrokeOperator(line) {
                if let pendingLine, isSkinnyVerticalPath(pendingLine) {
                    matches.append(line)
                }
                pendingMove = nil
                pendingLine = nil
                continue
            }

            pendingMove = nil
            pendingLine = nil
        }

        return matches
    }

    private func isSkinnyVerticalRectangleOperator(_ line: String) -> Bool {
        let parts = line.split(separator: " ")
        guard parts.count >= 5,
              parts.last == "re",
              let width = Double(parts[parts.count - 3]),
              let height = Double(parts[parts.count - 2])
        else {
            return false
        }

        return abs(width) <= 3 && abs(height) >= 16
    }

    private func isInlineSkinnyVerticalPathStroke(_ line: String) -> Bool {
        let parts = line.split(separator: " ").map(String.init)
        guard let moveIndex = parts.firstIndex(of: "m"),
              let lineIndex = parts.firstIndex(of: "l"),
              parts.suffix(2).contains(where: { $0 == "S" || $0 == "s" }),
              moveIndex >= 2,
              lineIndex >= moveIndex + 3,
              let x1 = Double(parts[moveIndex - 2]),
              let y1 = Double(parts[moveIndex - 1]),
              let x2 = Double(parts[lineIndex - 2]),
              let y2 = Double(parts[lineIndex - 1])
        else {
            return false
        }

        return isSkinnyVerticalPath((x1, y1, x2, y2))
    }

    private func moveOperatorPoint(_ line: String) -> (x: Double, y: Double)? {
        let parts = line.split(separator: " ")
        guard parts.count == 3,
              parts[2] == "m",
              let x = Double(parts[0]),
              let y = Double(parts[1])
        else {
            return nil
        }

        return (x, y)
    }

    private func lineOperatorPoint(_ line: String) -> (x: Double, y: Double)? {
        let parts = line.split(separator: " ")
        guard parts.count == 3,
              parts[2] == "l",
              let x = Double(parts[0]),
              let y = Double(parts[1])
        else {
            return nil
        }

        return (x, y)
    }

    private func isStrokeOperator(_ line: String) -> Bool {
        line == "S" || line == "s"
    }

    private func isSkinnyVerticalPath(_ path: (x1: Double, y1: Double, x2: Double, y2: Double)) -> Bool {
        let width = abs(path.x2 - path.x1)
        let height = abs(path.y2 - path.y1)
        return width <= 3 && height >= 16
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

    hard-markdown-corpus.pdf
    Hard public Markdown fixture with duplicate headings, links, nested quotes, tables, images, raw HTML, code, and Mermaid.

    hard-markdown-corpus/
    Text, geometry, structured text, and render logs for the hard Markdown fixture.

    hard-markdown-corpus-pages/
    Poppler and MuPDF page rasters for the hard Markdown fixture.

    crazy-markdown-torture.pdf
    Crazy public Markdown fixture with dense lists, several code languages, tables, local and remote images, reference-style image syntax, raw HTML, footnote-like notes, non-ASCII replacement, and Mermaid.

    crazy-markdown-torture/
    Text, geometry, structured text, and render logs for the crazy Markdown fixture.

    crazy-markdown-torture-pages/
    Poppler and MuPDF page rasters for the crazy Markdown fixture.

    a4-manuscript.pdf
    A4 manuscript-style fixture with sustained prose, tables, figures, code, and Mermaid blocks.

    a4-manuscript/
    Text, pdfinfo, geometry, structured text, and render logs for the A4 manuscript fixture.

    a4-manuscript-pages/
    Poppler and MuPDF page rasters for the A4 manuscript fixture.

    quote-spacing.pdf
    Focused witness for code block, block quote, paragraph, and heading spacing.

    quote-spacing/
    Poppler TSV geometry and MuPDF structured text for the quote spacing witness.

    source-code-spacing.pdf
    Focused source-code witness for dense code, block quote, paragraph, heading, wrapping, and glyph spacing regressions.

    source-code-spacing/README.txt
    Manifest for source-code witness tokens, expected image count, and expected stroke behavior.

    source-code-spacing/
    Text, geometry, structured text, and render logs for the source-code witness.

    source-code-spacing-pages/
    Poppler and MuPDF page rasters for the source-code witness.

    screenshot-source-code-regressions.pdf
    Focused screenshot-regression witness for source-code, quotes, headings, local images, remote fallback, and unsupported image syntax.

    screenshot-source-code-regressions/README.txt
    Manifest for screenshot source-code witness tokens, expected image reuse, fallback text, and expected stroke behavior.

    screenshot-source-code-regressions/
    Text, geometry, structured text, and render logs for the screenshot source-code witness.

    screenshot-source-code-regressions-pages/
    Poppler and MuPDF page rasters for the screenshot source-code witness.

    syntax-coloring-manuscript.pdf
    Focused manuscript proving opt-in syntax coloring without extraction,
    geometry, or raster regressions.

    syntax-coloring-manuscript/
    Text, geometry, structured text, and render logs for the syntax-coloring
    manuscript.

    syntax-coloring-manuscript-pages/
    Poppler and MuPDF page rasters for the syntax-coloring manuscript.

    rtl-manuscript.pdf
    Focused manuscript proving Arabic and Hebrew bidi ordering with embedded fonts, logical ToUnicode extraction, bracket mirroring, and geometry witnesses.

    rtl-manuscript/README.txt
    Manifest for the RTL manuscript witness tokens, extraction expectations, and artifact paths.

    rtl-manuscript/
    Text, geometry, structured text, and render logs for the RTL manuscript.

    rtl-manuscript-pages/
    Poppler and MuPDF page rasters for the RTL manuscript.

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

    cjk-diacritics-manuscript.pdf
    PDF proving manuscript-scale CJK line breaking, embedded CID text, and combining diacritic extraction.

    cjk-diacritics-manuscript/
    Text, geometry, structured text, and render logs for the CJK and diacritics manuscript fixture.

    cjk-diacritics-manuscript-pages/
    Poppler and MuPDF page rasters for the CJK and diacritics manuscript fixture.

    embedded-font-public-api.pdf
    PDF proving the public PDFOptions embedded-font role mapping through MarkdownPDFRenderer.

    embedded-font-public-api/
    Text, geometry, structured text, and render logs for the public embedded-font fixture.

    embedded-font-public-api-pages/
    Poppler and MuPDF page rasters for the public embedded-font fixture.
    """

    private static let sourceCodeSpacingManifest = """
    Source code spacing witness

    Expected image references: 0.
    Expected portable block quote strokes: 0.

    Required extracted tokens:
    - SourceCodeEndToken
    - QuoteStartToken
    - QuoteEndToken
    - AfterQuoteParagraph
    - AfterQuoteParagraphEndToken
    - AfterQuoteHeadingToken
    - SecondCodeEndToken
    - AfterSecondCodeParagraph

    Required artifacts:
    - source-code-spacing.pdf
    - source-code-spacing/text.txt
    - source-code-spacing/poppler.tsv
    - source-code-spacing/mupdf-stext.xml
    - source-code-spacing/poppler-render.log
    - source-code-spacing/mupdf-render.log
    - source-code-spacing-pages/poppler/
    - source-code-spacing-pages/mupdf/
    """

    private static let screenshotSourceCodeRegressionManifest = """
    Screenshot source-code regression witness

    Expected image XObjects: 1.
    Expected image draw operators: 2.
    Expected remote image fallback text: [Remote image: Remote regression figure].
    Expected unsupported reference-style image behavior: visible text, no image XObject.
    Expected portable block quote strokes: 0.

    Required extracted tokens:
    - DirectCodeEndToken
    - DirectQuoteStartToken
    - DirectQuoteEndToken
    - DirectAfterQuoteHeadingToken
    - ScreenshotCodeEndToken1
    - ScreenshotQuoteStartToken1
    - ScreenshotQuoteEndToken1
    - ScreenshotAfterQuoteParagraph1
    - ScreenshotAfterQuoteHeadingToken1
    - ScreenshotCodeEndToken5
    - ScreenshotQuoteStartToken5
    - AfterRemoteImageParagraph
    - Reference style regression chart
    - Reference style regression fallback text
    - AfterUnsupportedImageSyntaxParagraph

    Required artifacts:
    - screenshot-source-code-regressions.pdf
    - screenshot-source-code-regressions/text.txt
    - screenshot-source-code-regressions/poppler.tsv
    - screenshot-source-code-regressions/mupdf-stext.xml
    - screenshot-source-code-regressions/poppler-render.log
    - screenshot-source-code-regressions/mupdf-render.log
    - screenshot-source-code-regressions-pages/poppler/
    - screenshot-source-code-regressions-pages/mupdf/
    """

    private static let rtlManuscriptManifest = """
    RTL manuscript witness

    Expected embedded font resources: Type0, CIDFontType2, FontFile2, ToUnicode.
    Expected extraction policy: content is emitted in logical source order with ToUnicode mappings while glyphs are positioned in visual order.
    Expected visual policy: RTL visual runs are reordered and paired punctuation is mirrored before drawing.

    Required extracted tokens:
    - RTLPARATOKENA
    - ULISTTOKENA
    - OLISTTOKENA
    - QUOTETOKENA
    - HEADER
    - ROWA
    - RTLMIRRORTOKEN

    Required artifacts:
    - rtl-manuscript.pdf
    - rtl-manuscript/text.txt
    - rtl-manuscript/raw-text.txt
    - rtl-manuscript/poppler.tsv
    - rtl-manuscript/mupdf-stext.xml
    - rtl-manuscript/poppler-render.log
    - rtl-manuscript/mupdf-render.log
    - rtl-manuscript-pages/poppler/
    - rtl-manuscript-pages/mupdf/
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

    private func normalizedExtractedText(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func compactLogicalExtractedText(_ text: String) -> String {
        text.unicodeScalars
            .filter { scalar in
                !CharacterSet.whitespacesAndNewlines.contains(scalar)
                    && !isBidiFormattingScalar(scalar)
            }
            .map(String.init)
            .joined()
    }

    private func isBidiFormattingScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x061C,
             0x200E ... 0x200F,
             0x202A ... 0x202E,
             0x2066 ... 0x2069:
            true
        default:
            false
        }
    }

    private static func pdfHex(_ value: Int) -> String {
        String(format: "<%04X>", locale: Locale(identifier: "en_US_POSIX"), value)
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
