import Foundation
import MarkdownPDF
import Testing

/// The checks the other suites lean on, held to a minimal document: the structure
/// check accepts a sound file and names what is wrong with a damaged one, and the
/// reader gives back the version, the page count, the title and the text.
@Suite("PDF read-back validation")
struct PDFReadBackValidationTests {
    private let minimalMarkdown = "Hello from MarkdownPDF."

    @Test("The structure check accepts a minimal PDF")
    func structureCheckAcceptsMinimalPDF() throws {
        #expect(try PDFValidation.structureIssues(minimalPDF) == [])
    }

    @Test("The structure check reports a truncated PDF")
    func structureCheckReportsTruncatedPDF() throws {
        let data = try minimalPDF
        let issues = PDFValidation.structureIssues(data.prefix(data.count / 2), name: "minimal-truncated")

        // The cross-reference table is gone with the second half, and the byte
        // inspector, which shares no code with the reader, misses it too.
        #expect(issues.first == "minimal-truncated: the PDF is malformed: the file has no startxref")
        #expect(issues.contains("minimal-truncated: inspector: the cross-reference table has offsets that do not point to matching objects"))
    }

    @Test("The structure check reports a PDF whose objects moved under its cross-reference table")
    func structureCheckReportsShiftedObjects() throws {
        // One byte added after the header: every offset in the table is now one short.
        var bytes = try Array(minimalPDF)
        let lineEnd = try #require(bytes.firstIndex(of: 0x0A))
        bytes.insert(0x20, at: lineEnd)
        let issues = PDFValidation.structureIssues(bytes)

        #expect(issues.contains("object 1: the cross-reference table points at something that is not this object"))
        #expect(issues.contains("inspector: the cross-reference table has offsets that do not point to matching objects"))
    }

    @Test("The reader reports the minimal PDF version and page count")
    func readerReportsMinimalPDFMetadata() throws {
        // An encrypted file is refused by the reader, so reading it at all says it is not encrypted.
        let document = try PDFDocumentReader(data: minimalPDF)

        #expect(document.version == "1.4")
        #expect(document.pageCount == 1)
        // A document with no title and no author carries no Info dictionary.
        #expect(document.producer == nil)
        #expect(document.title == nil)
        #expect(document.pages[0].size == PDFOptions().pageSize)
    }

    @Test("The reader reports deterministic document title metadata")
    func readerReportsDeterministicDocumentTitleMetadata() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(title: "Navigation Article"),
        ).render(markdown: "# Intro\n\nBody.")
        let document = try PDFDocumentReader(data: data)

        #expect(document.title == "Navigation Article")
        #expect(document.producer == "MarkdownPDF")
        #expect(document.pageCount == 1)
        #expect(document.outline.map(\.title) == ["Intro"])
    }

    @Test("The reader extracts minimal PDF text")
    func readerExtractsMinimalPDFText() throws {
        #expect(try PDFValidation.text(minimalPDF) == minimalMarkdown)
    }

    @Test("The minimal PDF page shows its text inside the page")
    func minimalPDFPageShowsItsText() throws {
        let document = try PDFDocumentReader(data: minimalPDF)
        PDFValidation.expectFirstPageHasContent(document, name: "minimal")
        let layout = ReaderTextLayout(document)
        #expect(layout.words.map(\.text) == ["Hello", "from", "MarkdownPDF."])
        #expect(layout.visualLayoutIssues() == [])
    }

    @Test(
        "A rasterizer renders the minimal PDF page",
        .disabled("not verified: needs a rasterizer inside MarkdownPDF, see Docs/NOT-VERIFIED.md"),
    )
    func rasterizerRendersMinimalPDFPage() {
        PDFValidation.notVerified("the raster of the minimal page")
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

        // A name that would leave the directory is refused.
        #expect(throws: CocoaError.self) {
            try PDFValidation.writeTextArtifact("escape", name: "../outside.txt", root: explicitDirectory)
        }
    }

    private var minimalPDF: Data {
        get throws {
            try MarkdownPDFRenderer().render(markdown: minimalMarkdown)
        }
    }
}
