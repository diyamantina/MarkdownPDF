import Foundation
@testable import MarkdownPDF
import Testing

@Suite("PDF structural validation")
struct PDFStructuralValidationTests {
    @Test("Validates canonical structure for feature coverage PDF")
    func validatesCanonicalStructureForFeatureCoveragePDF() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownPDFStructuralTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageURL = directory.appendingPathComponent("image.jpg")
        try minimalJPEG().write(to: imageURL)

        let body = Array(
            repeating: "This paragraph forces more than one page while keeping text extractable.",
            count: 18,
        ).joined(separator: "\n\n")
        let markdown = """
        # Validation fixture

        [Docs](https://example.com/docs)

        | Feature | Covered |
        |---|---:|
        | Tables | 1 |
        | Links | 1 |

        ![pixel](image.jpg)

        \(body)
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 220),
                margins: PDFOptions.Margins(top: 20, right: 20, bottom: 20, left: 20),
                baseFontSize: 10,
            ),
        ).render(markdown: markdown, assetsBaseURL: directory)
        let inspector = PDFInspector(data)

        #expect(inspector.pageCount > 1)
        #expect(inspector.linkAnnotationCount == 1)
        #expect(inspector.text.contains("/Subtype /Image"))
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "Canonical PDF structure failed:\n\(inspector.canonicalStructureReport())",
        )
    }

    @Test("Rejects broken xref offsets")
    func rejectsBrokenXrefOffsets() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Hello from MarkdownPDF.")
        let damaged = replaceFirst("1 0 obj\n", with: "9 0 obj\n", in: data)
        let issues = PDFInspector(damaged).canonicalStructureIssues()

        #expect(issues.contains { $0.contains("xref table has offsets") })
    }

    @Test("Rejects wrong stream length")
    func rejectsWrongStreamLength() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Hello from MarkdownPDF.")
        let length = try #require(PDFInspector(data).streams.first?.declaredLength)
        let damaged = replaceFirst("/Length \(length)", with: "/Length \(length + 1)", in: data)
        let issues = PDFInspector(damaged).canonicalStructureIssues()

        #expect(issues.contains { $0.contains("stream lengths") })
    }

    @Test("Rejects missing page keys")
    func rejectsMissingPageKeys() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(pageSize: PDFOptions.PageSize(width: 300, height: 300)),
        ).render(markdown: "Hello from MarkdownPDF.")
        let damaged = replaceFirst("/MediaBox [0 0 300 300]\n", with: "", in: data)
        let issues = PDFInspector(damaged).canonicalStructureIssues()

        #expect(issues.contains { $0.contains("missing /MediaBox") })
    }

    @Test("Rejects wrong page type token")
    func rejectsWrongPageTypeToken() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Hello from MarkdownPDF.")
        let damaged = replaceFirst("<< /Type /Page\n", with: "<< /Type /Pages\n", in: data)
        let issues = PDFInspector(damaged).canonicalStructureIssues()

        #expect(issues.contains { $0.contains("missing /Type /Page") })
    }

    @Test("Rejects xref without free object zero")
    func rejectsXrefWithoutFreeObjectZero() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Hello from MarkdownPDF.")
        let damaged = replaceFirst(
            "xref\n0 6\n0000000000 65535 f \n",
            with: "xref\n1 5\n",
            in: data,
        )
        let issues = PDFInspector(damaged).canonicalStructureIssues()

        #expect(issues.contains { $0.contains("missing canonical free object 0") })
    }

    @Test("Rejects undeclared resource usage")
    func rejectsUndeclaredResourceUsage() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Hello from MarkdownPDF.")
        let damaged = replaceFirst("/F1 3 0 R", with: "", in: data)
        let issues = PDFInspector(damaged).canonicalStructureIssues()

        #expect(issues.contains { $0.contains("uses undeclared font /F1") })
    }

    @Test("Rejects undeclared image XObject usage")
    func rejectsUndeclaredImageXObjectUsage() {
        let data = xObjectFixturePDF()
        let damaged = replaceFirst(matching: #"/Im1 \d+ 0 R"#, with: "", in: data)
        let issues = PDFInspector(damaged).canonicalStructureIssues()

        #expect(issues.contains { $0.contains("uses undeclared XObject /Im1") })
    }

    @Test("Rejects missing page resources")
    func rejectsMissingPageResources() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Hello from MarkdownPDF.")
        let damaged = replaceFirst("/Resources << /Font << /F1 3 0 R >> >>\n", with: "", in: data)
        let issues = PDFInspector(damaged).canonicalStructureIssues()

        #expect(issues.contains { $0.contains("missing /Resources") })
    }

    @Test("Rejects declared resource references that are missing")
    func rejectsDeclaredResourceReferencesThatAreMissing() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Hello from MarkdownPDF.")
        let damaged = replaceFirst("/F1 3 0 R", with: "/F1 99 0 R", in: data)
        let issues = PDFInspector(damaged).canonicalStructureIssues()

        #expect(issues.contains { $0.contains("font resource /F1 references missing object 99") })
    }

    @Test("Rejects declared image XObject references that are missing")
    func rejectsDeclaredImageXObjectReferencesThatAreMissing() {
        let data = xObjectFixturePDF()
        let damaged = replaceFirst(matching: #"/Im1 \d+ 0 R"#, with: "/Im1 99 0 R", in: data)
        let issues = PDFInspector(damaged).canonicalStructureIssues()

        #expect(issues.contains { $0.contains("XObject resource /Im1 references missing object 99") })
    }

    @Test("Rejects missing object references")
    func rejectsMissingObjectReferences() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Hello from MarkdownPDF.")
        let damaged = replaceFirst(matching: #"/Contents \d+ 0 R"#, with: "/Contents 99 0 R", in: data)
        let issues = PDFInspector(damaged).canonicalStructureIssues()

        #expect(issues.contains { $0.contains("references missing content object 99") })
    }

    @Test("Rejects link annotations that point at unknown named destinations")
    func rejectsLinkAnnotationsThatPointAtUnknownNamedDestinations() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        # Target

        [Jump](#target)
        """)
        let damaged = replaceFirst("(target) [", with: "(missng) [", in: data)
        let issues = PDFInspector(damaged).canonicalStructureIssues()

        #expect(issues.contains { $0.contains("unknown destination target") })
    }

    @Test("Rejects link annotations when catalog names are missing")
    func rejectsLinkAnnotationsWhenCatalogNamesAreMissing() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        # Target

        [Jump](#target)
        """)
        let damaged = replaceAll("/Names", with: "/Xames", in: data)
        let issues = PDFInspector(damaged).canonicalStructureIssues()

        #expect(issues.contains { $0.contains("destination target but catalog /Names is missing") })
    }

    private func replaceFirst(_ needle: String, with replacement: String, in data: Data) -> Data {
        let text = String(decoding: data, as: UTF8.self)
        guard let range = text.range(of: needle) else {
            return data
        }

        return Data(text.replacingCharacters(in: range, with: replacement).utf8)
    }

    private func replaceFirst(matching pattern: String, with replacement: String, in data: Data) -> Data {
        let text = String(decoding: data, as: UTF8.self)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex ..< text.endIndex, in: text),
              ),
              let range = Range(match.range, in: text)
        else {
            return data
        }

        return Data(text.replacingCharacters(in: range, with: replacement).utf8)
    }

    private func replaceAll(_ needle: String, with replacement: String, in data: Data) -> Data {
        Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: needle, with: replacement).utf8)
    }

    private func xObjectFixturePDF() -> Data {
        var registry = PDFObjectRegistry()
        let catalogRef = registry.reserve()
        let pagesRef = registry.reserve()
        let imageRef = registry.add(Data(PDFSyntax.Dictionary([
            .init("Type", .pdfName("XObject")),
            .init("Subtype", .pdfName("Image")),
        ]).serialized().utf8))
        let contentRef = registry.add(PDFSyntax.Stream(
            dictionary: PDFSyntax.Dictionary(),
            data: Data("q /Im1 Do Q\n".utf8),
        ).serialized)
        let pageRef = registry.add(Data(PDFPageDictionary(
            parent: pagesRef,
            mediaBox: PDFOptions.PageSize(width: 300, height: 300),
            resources: PDFPageResources(
                imageXObjects: [
                    PDFXObjectResource(name: "Im1", objectRef: imageRef, kind: .image),
                ],
            ).pdfDictionary,
            contents: contentRef,
            annotations: [],
        ).pdfDictionary.serialized(style: .multiline).utf8))

        registry.set(
            pagesRef,
            body: Data(PDFDocumentPageTree(kids: [pageRef]).pdfDictionary.serialized().utf8),
        )
        registry.set(
            catalogRef,
            body: Data(PDFDocumentCatalog(pages: pagesRef, displayDocumentTitle: false).pdfDictionary.serialized().utf8),
        )

        return registry.serializedFile(root: catalogRef)
    }

    private func minimalJPEG() -> Data {
        Data([
            0xFF, 0xD8,
            0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
            0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x01, 0x00, 0x01, 0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00,
            0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00,
            0x00,
            0xFF, 0xD9,
        ])
    }
}
