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
        let textResult = try PDFValidation.pdftotext(data: data, name: "bundled-dejavu-symbols")

        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        #expect(textResult.output.contains("├"))
        #expect(textResult.output.contains("★"))
        #expect(textResult.output.contains("→"))
        #expect(!textResult.output.contains("?"))
        #expect(!textResult.output.contains("Tree: +"))
        #expect(!textResult.output.contains("Star: *"))
        #expect(!textResult.output.contains("Arrow: >"))
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
        let textResult = try PDFValidation.pdftotext(data: data, name: "automatic-dejavu-symbols")

        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
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
            #expect(textResult.output.contains(text), "Missing \(text) in:\n\(textResult.output)")
        }
        #expect(!textResult.output.contains("?"))
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

    @Test("Automatic DejaVu preserves PDF/UA-1 and PDF/A-2a conformance")
    func automaticDejaVuPreservesConformance() throws {
        let options = PDFOptions(
            title: "Automatic DejaVu Conformance",
            conformance: .pdfUA1AndPDFA2A,
        )
        let data = try MarkdownPDFRenderer(options: options).render(markdown: "# Faithful ★\n\nRoute → destination.")
        let pdfA = try PDFValidation.veraPDF(data: data, name: "automatic-dejavu-pdfa", flavour: "2a")
        let pdfUA = try PDFValidation.veraPDF(data: data, name: "automatic-dejavu-pdfua", flavour: "ua1")

        try #require(pdfA.exitCode == 0, "veraPDF PDF/A-2a failed:\n\(pdfA.output)")
        try #require(pdfUA.exitCode == 0, "veraPDF PDF/UA-1 failed:\n\(pdfUA.output)")
        #expect(pdfA.output.contains("\"compliant\" : true"))
        #expect(pdfUA.output.contains("\"compliant\" : true"))
    }
}
