import Foundation
import MarkdownPDF
import Testing

@Suite("PDF tool validation")
struct PDFToolValidationTests {
    private let minimalMarkdown = "Hello from MarkdownPDF."

    @Test("qpdf validates minimal PDF structure")
    func qpdfValidatesMinimalPDFStructure() throws {
        let result = try PDFValidation.qpdfCheck(
            data: minimalPDF,
            name: "minimal-valid",
        )

        #expect(result.exitCode == 0, "qpdf --check failed:\n\(result.output)")
    }

    @Test("qpdf reports damaged PDF structure")
    func qpdfReportsDamagedPDFStructure() throws {
        let data = try minimalPDF
        let result = try PDFValidation.qpdfCheck(
            data: data.prefix(data.count / 2),
            name: "minimal-truncated",
        )

        #expect(result.exitCode == 2 || result.exitCode == 3, "qpdf unexpectedly accepted damaged PDF:\n\(result.output)")
        #expect(result.output.contains("WARNING") || result.output.contains("ERROR") || result.output.contains("qpdf:"))
    }

    @Test("pdfinfo reports minimal PDF version and page count")
    func pdfinfoReportsMinimalPDFMetadata() throws {
        let result = try PDFValidation.pdfinfo(data: minimalPDF, name: "minimal-info")
        let info = PDFValidation.parsedInfo(from: result)

        #expect(result.exitCode == 0, "pdfinfo failed:\n\(result.output)")
        #expect(info["PDF version"] == "1.4", "Unexpected pdfinfo output:\n\(result.output)")
        #expect(info["Pages"] == "1", "Unexpected pdfinfo output:\n\(result.output)")
        #expect(info["Encrypted"] == "no", "Unexpected pdfinfo output:\n\(result.output)")
    }

    @Test("pdfinfo reports deterministic document title metadata")
    func pdfinfoReportsDeterministicDocumentTitleMetadata() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(title: "Navigation Article"),
        ).render(markdown: "# Intro\n\nBody.")
        let result = try PDFValidation.pdfinfo(data: data, name: "navigation-title")
        let info = PDFValidation.parsedInfo(from: result)

        #expect(result.exitCode == 0, "pdfinfo failed:\n\(result.output)")
        #expect(info["Title"] == "Navigation Article", "Unexpected pdfinfo output:\n\(result.output)")
        #expect(info["Pages"] == "1", "Unexpected pdfinfo output:\n\(result.output)")
    }

    @Test("pdftotext extracts minimal PDF text")
    func pdftotextExtractsMinimalPDFText() throws {
        let result = try PDFValidation.pdftotext(data: minimalPDF, name: "minimal-text")

        #expect(result.exitCode == 0, "pdftotext failed:\n\(result.output)")
        #expect(result.output.contains(minimalMarkdown), "Unexpected pdftotext output:\n\(result.output)")
    }

    @Test("pdftoppm renders minimal PDF page")
    func pdftoppmRendersMinimalPDFPage() throws {
        let render = try PDFValidation.pdftoppmPNG(data: minimalPDF, name: "minimal-render")
        let pngData = try? Data(contentsOf: render.pngURL)
        let dimensions = PDFValidation.pngDimensions(in: pngData)

        #expect(render.result.exitCode == 0, "pdftoppm failed:\n\(render.result.output)")
        #expect(dimensions != nil)
        #expect((dimensions?.width ?? 0) > 0)
        #expect((dimensions?.height ?? 0) > 0)
    }

    @Test("Artifact directory is opt in and writes nested files")
    func artifactDirectoryIsOptInAndWritesNestedFiles() throws {
        let root = try PDFValidation.temporaryDirectory()
        let explicitDirectory = PDFValidation.artifactDirectory(
            environment: [PDFValidation.artifactDirectoryEnvironmentKey: root.path],
        )

        #expect(PDFValidation.artifactDirectory(environment: [:]) == nil)
        #expect(explicitDirectory?.standardizedFileURL.path == root.standardizedFileURL.path)

        try PDFValidation.writeTextArtifact(
            "artifact text",
            name: "nested/sample.txt",
            root: explicitDirectory,
        )

        let text = try String(
            contentsOf: root.appendingPathComponent("nested/sample.txt"),
            encoding: .utf8,
        )
        #expect(text == "artifact text")

        let source = root.appendingPathComponent("source.txt")
        try Data("copy text".utf8).write(to: source)
        try PDFValidation.copyArtifact(
            from: source,
            name: "copies/source.txt",
            root: explicitDirectory,
        )

        let copiedText = try String(
            contentsOf: root.appendingPathComponent("copies/source.txt"),
            encoding: .utf8,
        )
        #expect(copiedText == "copy text")
    }

    private var minimalPDF: Data {
        get throws {
            try MarkdownPDFRenderer().render(markdown: minimalMarkdown)
        }
    }
}
