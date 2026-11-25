import Foundation
@testable import MarkdownPDF
import Testing

/// A picture with an empty text alternative and the title `decorative` is decoration, not content (WCAG 2.2, 1.1.1,
/// and PDF/UA-1, 7.3): in a tagged PDF it is an artifact, so a screen reader skips it, and it is still drawn. The
/// answer key is the library's own reader, which parses the structure tree, plus the marked-content operators.
@Suite("Decorative images in tagged PDF")
struct PDFDecorativeImageTests {
    private func render(_ markdown: String, tagged: Bool = true) throws -> Data {
        let directory = try TestImageAssets.directoryWithChartPNG()
        defer {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                Issue.record("the fixture could not be removed: \(error)")
            }
        }
        let options = PDFOptions(taggedPDF: tagged ? .enabled : .disabled)
        return try MarkdownPDFRenderer(options: options).render(markdown: markdown, assetsBaseURL: directory)
    }

    private func figures(_ data: Data) throws -> [PDFDocumentReader.StructureElement] {
        try PDFDocumentReader(data: data).structure.flatMap(\.flattened).filter { $0.type == "Figure" }
    }

    @Test("a picture with empty text and the title decorative is an artifact: drawn, with no figure")
    func decorativePictureIsAnArtifact() throws {
        let data = try render("# T\n\n![](local-chart.png \"decorative\")\n")
        let inspector = PDFInspector(data)

        #expect(try figures(data).isEmpty)
        #expect(inspector.text.contains("/Subtype /Image"), "the picture is still drawn")
        try PDFValidation.requireSoundStructure(data, name: "decorative-image")
    }

    @Test("a picture with text is a figure that carries it, whatever its title")
    func describedPictureStaysAFigure() throws {
        let data = try render("![A bar chart](local-chart.png \"decorative\")\n")

        #expect(try figures(data).map(\.alternateText) == ["A bar chart"])
    }

    @Test("a picture with empty text and no marker is still a figure, so nothing is hidden by accident")
    func undeclaredEmptyTextStaysAFigure() throws {
        let data = try render("![](local-chart.png)\n")

        #expect(try figures(data).count == 1)
    }

    @Test("the marker is case sensitive and exact: a title that only contains the word does not hide the picture")
    func markerIsExact() throws {
        let data = try render("![](local-chart.png \"a decorative frame\")\n")

        #expect(try figures(data).count == 1)
    }

    @Test("an untagged PDF is unchanged: the marker only decides how a tagged PDF is structured")
    func untaggedRenderStillDrawsThePicture() throws {
        let data = try render("![](local-chart.png \"decorative\")\n", tagged: false)

        #expect(PDFInspector(data).text.contains("/Subtype /Image"))
    }
}
