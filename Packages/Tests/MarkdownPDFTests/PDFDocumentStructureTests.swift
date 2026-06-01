import Foundation
@testable import MarkdownPDF
import Testing

@Suite("PDF document structure")
struct PDFDocumentStructureTests {
    @Test("Serializes catalog dictionary")
    func serializesCatalogDictionary() {
        let catalog = PDFDocumentCatalog(
            pages: PDFSyntax.Reference(objectNumber: 2),
            displayDocumentTitle: true,
        )

        #expect(
            catalog.pdfDictionary.serialized()
                == "<< /Type /Catalog /Pages 2 0 R /ViewerPreferences << /DisplayDocTitle true >> >>",
        )
    }

    @Test("Serializes flat page tree")
    func serializesFlatPageTree() {
        let pageTree = PDFDocumentPageTree(kids: [
            PDFSyntax.Reference(objectNumber: 5),
            PDFSyntax.Reference(objectNumber: 6),
        ])

        #expect(pageTree.pdfDictionary.serialized() == "<< /Type /Pages /Kids [5 0 R 6 0 R] /Count 2 >>")
    }

    @Test("Serializes page dictionary with canonical keys")
    func serializesPageDictionaryWithCanonicalKeys() {
        let page = PDFPageDictionary(
            parent: PDFSyntax.Reference(objectNumber: 2),
            mediaBox: PDFOptions.PageSize(width: 300, height: 400),
            resources: PDFSyntax.Dictionary([
                .init(
                    "Font",
                    .pdfDictionary([
                        .init("F1", .reference(PDFSyntax.Reference(objectNumber: 3))),
                    ]),
                ),
            ]),
            contents: PDFSyntax.Reference(objectNumber: 4),
            annotations: [PDFSyntax.Reference(objectNumber: 5)],
        )

        #expect(
            page.pdfDictionary.serialized(style: .multiline)
                == """
                << /Type /Page
                /Parent 2 0 R
                /MediaBox [0 0 300 400]
                /Resources << /Font << /F1 3 0 R >> >>
                /Contents 4 0 R
                /Annots [5 0 R] >>
                """,
        )
    }

    @Test("Omits empty annotation array")
    func omitsEmptyAnnotationArray() {
        let page = PDFPageDictionary(
            parent: PDFSyntax.Reference(objectNumber: 2),
            mediaBox: PDFOptions.PageSize(width: 300, height: 400),
            resources: PDFSyntax.Dictionary(),
            contents: PDFSyntax.Reference(objectNumber: 4),
            annotations: [],
        )

        #expect(!page.pdfDictionary.serialized(style: .multiline).contains("/Annots"))
    }

    @Test("Renderer keeps deterministic document spine object order")
    func rendererKeepsDeterministicDocumentSpineObjectOrder() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Hello from MarkdownPDF.")
        let objects = PDFInspector(data).indirectObjects

        #expect(objects.map(\.number) == [1, 2, 3, 4, 5])
        let catalog = try #require(objects.first { $0.number == 1 })
        let pages = try #require(objects.first { $0.number == 2 })
        let font = try #require(objects.first { $0.number == 3 })
        let content = try #require(objects.first { $0.number == 4 })
        let page = try #require(objects.first { $0.number == 5 })

        #expect(catalog.content == "<< /Type /Catalog /Pages 2 0 R >>")
        #expect(pages.content == "<< /Type /Pages /Kids [5 0 R] /Count 1 >>")
        #expect(font.content.contains("/Type /Font"))
        #expect(content.isStream)
        #expect(page.content.contains("<< /Type /Page\n"))
    }
}
