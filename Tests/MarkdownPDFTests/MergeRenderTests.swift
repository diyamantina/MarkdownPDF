import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: merged output is compared with what the single-document renderer gives
/// for each source, and with values known by construction: image colours, heading
/// destination names, footnote numbers, and which page each source starts on.
@Suite("Merging sources")
struct MergeRenderTests {
    private func solidPNG(red: Int, green: Int, blue: Int) -> Data {
        TestPNGEncoder(
            width: 4,
            height: 4,
            colorType: 6,
            bitDepth: 8,
            sample: { _, _, channel in [red, green, blue, 255][channel] },
        ).encode()
    }

    private func folder(with png: Data) throws -> URL {
        let directory = try PDFValidation.temporaryDirectory()
        try png.write(to: directory.appendingPathComponent("fig.png"))
        return directory
    }

    private func pageTexts(_ pdf: Data, name: String) throws -> [String] {
        let result = try PDFValidation.pdftotext(data: pdf, name: name)
        try #require(result.exitCode == 0, "pdftotext failed:\n\(result.output)")
        var pages = result.output.components(separatedBy: "\u{0C}")
        if pages.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            pages.removeLast()
        }
        return pages
    }

    @Test("Each source resolves its own relative images")
    func perSourceImageBases() throws {
        let red = try folder(with: solidPNG(red: 200, green: 10, blue: 20))
        let blue = try folder(with: solidPNG(red: 10, green: 20, blue: 220))
        let pdf = try MarkdownPDFRenderer().render(sources: [
            MarkdownSource(markdown: "# A\n\n![same path](fig.png)", assetsBaseURL: red, name: "a.md"),
            MarkdownSource(markdown: "# B\n\n![same path](fig.png)", assetsBaseURL: blue, name: "b.md"),
        ])

        let images = PDFImageObjects(pdf: pdf).images
        try #require(images.count == 2, "the two files share a spelling but are different images")
        let first = try images[0].decodedSamples()
        let second = try images[1].decodedSamples()
        #expect(Array(first.prefix(3)) == [200, 10, 20])
        #expect(Array(second.prefix(3)) == [10, 20, 220])
        let text = try pageTexts(pdf, name: "merge-images").joined()
        #expect(!text.contains("[Image:"))
    }

    @Test("The same heading in two sources gets two distinct destinations")
    func headingDestinationsDoNotCollide() throws {
        let pdf = try MarkdownPDFRenderer().render(sources: [
            MarkdownSource(markdown: "# Overview\n\n[jump](#overview)"),
            MarkdownSource(markdown: "# Overview\n\n[jump](#overview-2)"),
        ])
        let inspector = PDFInspector(pdf)
        #expect(inspector.canonicalStructureIssues().isEmpty, "\(inspector.canonicalStructureReport())")
        #expect(inspector.text.contains("overview-2"))
        let titles = inspector.text.components(separatedBy: "/Title (Overview)").count - 1
        #expect(titles == 2, "both headings reach the outline")
    }

    @Test("Footnote labels repeat across sources without clashing")
    func footnotesAreNamespaced() throws {
        let pdf = try MarkdownPDFRenderer().render(sources: [
            MarkdownSource(markdown: "First[^1] and again[^a].\n\n[^1]: Note one of A.\n\n[^a]: Note a of A."),
            MarkdownSource(markdown: "Second[^1].\n\n[^1]: Note one of B."),
        ])
        let inspector = PDFInspector(pdf)
        #expect(inspector.canonicalStructureIssues().isEmpty, "\(inspector.canonicalStructureReport())")
        let text = try pageTexts(pdf, name: "merge-footnotes").joined(separator: "\n")
        #expect(text.contains("Note one of A."))
        #expect(text.contains("Note a of A."))
        #expect(text.contains("Note one of B."))
        // Three distinct footnotes, numbered 1 to 3 in reference order.
        let geometry = ContentStreamGeometry(pdf: pdf)
        let numbers = geometry.pages.flatMap(\.texts).filter { $0.string.hasSuffix(".") && Int($0.string.dropLast()) != nil }.map(\.string)
        #expect(numbers == ["1.", "2.", "3."])
    }

    @Test("A source with a footnote reference but no definition in its own file does not borrow another's")
    func footnoteScopeIsPerSource() throws {
        let pdf = try MarkdownPDFRenderer().render(sources: [
            MarkdownSource(markdown: "Defined here.\n\n[^x]: Only A defines x."),
            MarkdownSource(markdown: "B refers to x[^x] but never defines it."),
        ])
        let text = try pageTexts(pdf, name: "merge-footnote-scope").joined(separator: "\n")
        #expect(text.contains("[^x]"), "the unresolved reference stays literal")
        #expect(!text.contains("Only A defines x."), "A's definition is not rendered as a footnote of B")
    }

    @Test("Sources start on new pages by default and share a page when asked")
    func pageBreakBetweenSources() throws {
        let sources = [
            MarkdownSource(markdown: "# First\n\nShort."),
            MarkdownSource(markdown: "# Second\n\nShort."),
            MarkdownSource(markdown: "# Third\n\nShort."),
        ]
        let broken = try MarkdownPDFRenderer().render(sources: sources)
        let pages = try pageTexts(broken, name: "merge-breaks")
        #expect(pages.count == 3)
        #expect(pages[1].contains("Second"))

        let joined = try MarkdownPDFRenderer().render(sources: sources, startsEachSourceOnNewPage: false)
        let joinedPages = try pageTexts(joined, name: "merge-joined")
        #expect(joinedPages.count == 1)
    }

    @Test("A source that ends on a fresh page leaves no blank page")
    func noBlankPageBetweenSources() throws {
        let pdf = try MarkdownPDFRenderer().render(sources: [
            MarkdownSource(markdown: "# A\n\n<!-- pagebreak -->\n\n# B"),
            MarkdownSource(markdown: "# C"),
        ])
        #expect(ContentStreamGeometry(pdf: pdf).pages.count == 3)
    }

    @Test("One source renders byte-identically to the single-document call")
    func singleSourceMatchesSingleDocument() throws {
        let markdown = "# Title\n\nParagraph with a note[^1].\n\n[^1]: The note.\n\n```\ncode\n```\n"
        let options = PDFOptions(title: "T", tableOfContents: .enabled)
        let single = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
        let merged = try MarkdownPDFRenderer(options: options).render(sources: [MarkdownSource(markdown: markdown)])
        #expect(single == merged)
    }

    @Test("The PDF title comes from the options and the table of contents spans all sources")
    func titleAndContents() throws {
        let options = PDFOptions(title: "Merged Title", tableOfContents: .enabled)
        let pdf = try MarkdownPDFRenderer(options: options).render(sources: [
            MarkdownSource(markdown: "# Book\n\n## One"),
            MarkdownSource(markdown: "## Two\n\n### Deeper"),
        ])
        let inspector = PDFInspector(pdf)
        #expect(inspector.text.contains("/Title (Merged Title)"))
        let text = try pageTexts(pdf, name: "merge-contents").joined(separator: "\n")
        for heading in ["One", "Two", "Deeper"] {
            #expect(text.contains(heading))
        }
        #expect(inspector.canonicalStructureIssues().isEmpty, "\(inspector.canonicalStructureReport())")
    }

    @Test("No sources render an empty one-page document")
    func noSources() throws {
        let pdf = try MarkdownPDFRenderer().render(sources: [])
        #expect(ContentStreamGeometry(pdf: pdf).pages.isEmpty)
        let inspector = PDFInspector(pdf)
        #expect(inspector.canonicalStructureIssues().isEmpty, "\(inspector.canonicalStructureReport())")
        #expect(inspector.text.contains("/Count 1"))
    }

    @Test("Index and page numbers span merged sources")
    func indexAcrossSources() throws {
        let options = PDFOptions(
            pageNumbers: .enabled,
            index: PDFOptions.Index(isEnabled: true, terms: ["shared"]),
        )
        let pdf = try MarkdownPDFRenderer(options: options).render(sources: [
            MarkdownSource(markdown: "# A\n\nA shared word."),
            MarkdownSource(markdown: "# B\n\nNothing."),
            MarkdownSource(markdown: "# C\n\nAnother shared word."),
        ])
        let pages = try pageTexts(pdf, name: "merge-index")
        #expect(pages.count == 4)
        #expect(pages[3].contains("shared, 1, 3"))
        #expect(pages[2].contains("3"))
    }
}
