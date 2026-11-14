import Foundation
@testable import MarkdownPDF
import Testing

@Suite("Bundled fonts")
struct BundledFontsTests {
    @Test("DejaVu loads every Markdown text role")
    func loadsEveryRole() throws {
        let fonts = PDFOptions.EmbeddedFonts.dejaVu

        #expect(try #require(fonts.regular).data.count > 0)
        #expect(try #require(fonts.bold).data.count > 0)
        #expect(try #require(fonts.italic).data.count > 0)
        #expect(try #require(fonts.monospaced).data.count > 0)
    }

    @Test("DejaVu preserves technical symbols in rendered text")
    func preservesTechnicalSymbols() throws {
        let markdown = "Tree: ├\n\nStar: ★\n\nArrow: →"
        let options = PDFOptions(embeddedFonts: .dejaVu)
        let data = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
        let text = try PDFValidation.text(data)

        #expect(text.contains("├"))
        #expect(text.contains("★"))
        #expect(text.contains("→"))
        #expect(!text.contains("?"))
        #expect(!text.contains("Tree: +"))
        #expect(!text.contains("Star: *"))
        #expect(!text.contains("Arrow: >"))
    }

    @Test("Default WinAnsi documents retain base fonts")
    func defaultWinAnsiRetainsBaseFonts() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Lean café, curly “quotes”, and £12.")
        let inspector = PDFInspector(data)

        #expect(inspector.text.contains("/BaseFont /Helvetica"))
        #expect(!inspector.text.contains("/FontFile2"))
        #expect(!inspector.text.contains("/ToUnicode"))
    }

    @Test("Default technical symbols select subsetted DejaVu roles")
    func defaultTechnicalSymbolsSelectDejaVu() throws {
        let markdown = """
        Plain ★

        **Bold →**

        *Italic ♥*

        `Code ├`
        """
        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let inspector = PDFInspector(data)
        let streams = inspector.streams.map(\.body).joined(separator: "\n")
        let extracted = try PDFValidation.text(data)

        #expect(inspector.text.contains("/FontFile2"))
        #expect(inspector.text.contains("/ToUnicode"))
        for subsetBaseName in [
            "AAAAAA+DejaVuSans",
            "AAAAAB+DejaVuSans-Bold",
            "AAAAAC+DejaVuSans-Oblique",
            "AAAAAD+DejaVuSansMono",
        ] {
            #expect(inspector.text.contains("/BaseFont /\(subsetBaseName)"))
            #expect(inspector.text.contains("/FontName /\(subsetBaseName)"))
        }
        for resourceName in ["EF1", "EF2", "EF3", "EF4"] {
            #expect(streams.contains("/\(resourceName)"))
        }
        for text in ["Plain ★", "Bold →", "Italic ♥", "Code ├"] {
            #expect(extracted.contains(text), "Missing \(text) in:\n\(extracted)")
        }
        #expect(!extracted.contains("?"))
    }

    @Test("Nested parsed content participates in automatic selection")
    func nestedContentParticipatesInSelection() throws {
        let markdown = """
        > | Column |
        > |---|
        > | ★ |
        """
        let data = try MarkdownPDFRenderer().render(markdown: markdown)

        #expect(PDFInspector(data).text.contains("/FontFile2"))
    }

    private func automaticDejaVuConformancePDF() throws -> Data {
        let options = PDFOptions(
            title: "Automatic DejaVu Conformance",
            conformance: .pdfUA1AndPDFA2A,
        )
        return try MarkdownPDFRenderer(options: options).render(markdown: "# Faithful ★\n\nRoute → destination.")
    }

    @Test("Automatic DejaVu keeps what PDF/UA-1 and PDF/A-2a require of the file")
    func automaticDejaVuKeepsConformancePrerequisites() throws {
        let data = try automaticDejaVuConformancePDF()

        PDFValidation.expectSoundStructure(data, name: "automatic-dejavu-conformance")
        try PDFValidation.expectConformancePrerequisites(data, profiles: [.pdfA2A, .pdfUA1])
        // The symbols select the bundled faces, so no base font is left unembedded.
        let fonts = try PDFDocumentReader(data: data).fonts
        #expect(!fonts.isEmpty)
        #expect(fonts.allSatisfy { $0.isEmbedded && $0.name.contains("DejaVuSans") })
    }

    @Test(
        "Automatic DejaVu preserves PDF/UA-1 and PDF/A-2a conformance",
        .disabled("not verified: needs a PDF/A and PDF/UA validator inside MarkdownPDF, see Docs/NOT-VERIFIED.md"),
    )
    func automaticDejaVuPreservesConformance() throws {
        _ = try automaticDejaVuConformancePDF()
        PDFValidation.notVerified("a full PDF/A-2a and PDF/UA-1 conformance run")
    }
}
