import Foundation
@testable import MarkdownPDF
import Testing

@Suite("Large document fixtures")
struct LargeDocumentFixtureTests {
    @Test("Large handbook renders multi-page at A3")
    func largeHandbookRendersAtA3() throws {
        try assertLargeDocument(
            fixture: "big-engine-handbook.md",
            pageSize: .a3,
            artifact: "big-engine-handbook",
            mediaBoxNumbers: ["841.89", "1190.55"],
            distinctiveText: "Handbook",
        )
    }

    @Test("Large specification renders multi-page at US Legal")
    func largeSpecificationRendersAtLegal() throws {
        try assertLargeDocument(
            fixture: "big-platform-specification.md",
            pageSize: .legal,
            artifact: "big-platform-specification",
            mediaBoxNumbers: ["612", "1008"],
            distinctiveText: "Specification",
        )
    }

    @Test("Large report renders multi-page at Tabloid")
    func largeReportRendersAtTabloid() throws {
        try assertLargeDocument(
            fixture: "big-operations-report.md",
            pageSize: .tabloid,
            artifact: "big-operations-report",
            mediaBoxNumbers: ["792", "1224"],
            distinctiveText: "Observability",
        )
    }

    @Test("Large reference renders many pages at A5")
    func largeReferenceRendersAtA5() throws {
        try assertLargeDocument(
            fixture: "big-pocket-reference.md",
            pageSize: .a5,
            artifact: "big-pocket-reference",
            mediaBoxNumbers: ["419.53", "595.28"],
            distinctiveText: "Reference",
            minimumPageCount: 8,
        )
    }

    private func assertLargeDocument(
        fixture: String,
        pageSize: PDFOptions.PageSize,
        artifact: String,
        mediaBoxNumbers: [String],
        distinctiveText: String,
        minimumPageCount: Int = 4,
    ) throws {
        let markdown = try loadFixture(fixture)
        #expect(markdown.count > 30000, "Expected a large fixture for \(fixture)")
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(pageSize: pageSize, title: distinctiveText),
        ).render(markdown: markdown)
        try PDFValidation.writeArtifact(data, name: "\(artifact).pdf")
        let inspector = PDFInspector(data)

        for number in mediaBoxNumbers {
            #expect(inspector.text.contains(number), "MediaBox missing \(number) for \(fixture)")
        }
        #expect(inspector.pageCount >= minimumPageCount, "Only \(inspector.pageCount) pages for \(fixture)")
        #expect(inspector.hasValidXrefOffsets())
        #expect(inspector.streamLengthsMatch())

        let qpdf = try PDFValidation.qpdfCheck(data: data, name: artifact)
        #expect(qpdf.exitCode == 0, "qpdf --check failed for \(fixture):\n\(qpdf.output)")
        let infoResult = try PDFValidation.pdfinfo(data: data, name: artifact)
        let info = PDFValidation.parsedInfo(from: infoResult)
        #expect(info["Pages"] == "\(inspector.pageCount)", "pdfinfo page count mismatch for \(fixture)")
        let textResult = try PDFValidation.pdftotext(data: data, name: "\(artifact)-text")
        #expect(textResult.exitCode == 0, "pdftotext failed for \(fixture):\n\(textResult.output)")
        #expect(textResult.output.contains(distinctiveText), "Missing \(distinctiveText) in \(fixture) extraction")
    }

    private func loadFixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
