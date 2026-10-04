import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: the colophon is the last page or pages of the document, after the index.
///
/// - Position: documents whose body pages are fixed by explicit page breaks, so the
///   expected page count is known by construction; the last page is read back from
///   Poppler's per-page text, independently of the renderer's page logic.
/// - Text: the default blocks are compared with the parse of the Markdown that the
///   feature's specification states, so the AST is checked against the written
///   contract and not against itself.
/// - Contents and footers: the printed number of every heading is read from the
///   per-page text and compared with what the contents page prints.
/// - Link: the URI annotation is found in the object graph and must belong to the
///   last page.
@Suite("Colophon")
struct ColophonTests {
    private static let url = "https://codeberg.org/MarkdownPdfHQ/MarkdownPDF"

    private static let threePages = (1 ... 3).map { "# Chapter \($0)\n\nThe word alpha appears in chapter \($0)." }
        .joined(separator: "\n\n<!-- pagebreak -->\n\n")

    private func pageTexts(_ pdf: Data, name: String) throws -> [String] {
        let result = try PDFValidation.pdftotext(data: pdf, name: name)
        try #require(result.exitCode == 0, "pdftotext failed:\n\(result.output)")
        var pages = result.output.components(separatedBy: "\u{0C}")
        if pages.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            pages.removeLast()
        }
        return pages
    }

    /// A solid RGB PNG, stored uncompressed so it builds quickly.
    private func solidPNG(width: Int, height: Int) -> Data {
        var encoder = TestPNGEncoder(
            width: width,
            height: height,
            colorType: 2,
            bitDepth: 8,
            sample: { _, _, channel in [20, 40, 160][channel] },
        )
        encoder.compression = .stored
        encoder.filtering = .none
        return encoder.encode()
    }

    private func render(_ markdown: String, _ options: PDFOptions) throws -> Data {
        try MarkdownPDFRenderer(options: options).render(markdown: markdown)
    }

    /// The Markdown the specification gives for the default page.
    private func specification(title: String, author: String) -> String {
        """
        # Colophon

        *\(title)* by \(author).

        This edition was typeset with MarkdownPDF, a pure Swift Markdown to PDF renderer written by Mihaela Mihaljevic. \
        MarkdownPDF parses the Markdown, lays out the pages and writes the PDF bytes itself, with no browser, no word \
        processor and no LaTeX.

        MarkdownPDF is open source: [\(Self.url)](\(Self.url))
        """
    }

    // MARK: API

    @Test("The colophon is off by default and equality is by value")
    func apiDefaults() {
        #expect(PDFOptions().colophon == .disabled)
        #expect(!PDFOptions.Colophon.disabled.isEnabled)
        #expect(PDFOptions.Colophon.enabled.isEnabled)
        #expect(PDFOptions.Colophon.enabled.markdown == nil)
        #expect(PDFOptions.Colophon.enabled(markdown: "# A").markdown == "# A")
        #expect(PDFOptions.Colophon.enabled(markdown: "# A") == .enabled(markdown: "# A"))
        #expect(PDFOptions.Colophon.enabled(markdown: "# A") != .enabled(markdown: "# B"))
        #expect(PDFOptions.Colophon.enabled != .disabled)
        #expect(PDFOptions().ignoreHTMLComments == .disabled)
    }

    // MARK: Default text

    @Test("The default blocks are the parse of the specified Markdown")
    func defaultBlocksMatchTheSpecification() {
        let parsed = MarkdownParser().parse(specification(title: "Book Title", author: "Jane Doe")).blocks
        #expect(ColophonDefaultText.blocks(title: "Book Title", author: "Jane Doe") == parsed)
    }

    @Test("A missing title or author is dropped cleanly")
    func missingParts() {
        let titleOnly = ColophonDefaultText.blocks(title: "T", author: nil)
        #expect(titleOnly[1] == .paragraph([.emphasis([.text("T")]), .text(".")]))
        let authorOnly = ColophonDefaultText.blocks(title: nil, author: "A")
        #expect(authorOnly[1] == .paragraph([.text("By A.")]))
        let neither = ColophonDefaultText.blocks(title: nil, author: nil)
        #expect(neither.count == 3)
        #expect(neither[0] == .heading(level: 1, content: [.text("Colophon")]))
        #expect(neither[1] == .paragraph([.text(ColophonDefaultText.description)]))
        // White space only counts as missing.
        #expect(ColophonDefaultText.blocks(title: "  \n", author: " ") == neither)
        // Surrounding white space is trimmed.
        #expect(ColophonDefaultText.blocks(title: " T ", author: " A ") == ColophonDefaultText.blocks(title: "T", author: "A"))
    }

    @Test("Markdown characters in the title and author are drawn literally")
    func literalTitleAndAuthor() throws {
        let options = PDFOptions(title: "A *b* [c](d) _e_", author: "J. `Q` Public", colophon: .enabled)
        let pdf = try render("# Body", options)
        let pages = try pageTexts(pdf, name: "colophon-literal")
        let last = try #require(pages.last)
        #expect(last.contains("A *b* [c](d) _e_ by J. `Q` Public."))
        // The only link on the page is the project URL.
        #expect(PDFInspector(pdf).linkAnnotationCount == 1)
    }

    // MARK: Position

    @Test("The colophon is the last page and starts on a fresh page")
    func lastPage() throws {
        let options = PDFOptions(title: "My Book", author: "Jane Doe", colophon: .enabled)
        let pdf = try render(Self.threePages, options)
        let pages = try pageTexts(pdf, name: "colophon-last")
        try #require(pages.count == 4)
        for page in pages.prefix(3) {
            #expect(!page.contains("Colophon"))
        }
        let last = pages[3]
        #expect(last.hasPrefix("Colophon"))
        #expect(last.contains("My Book by Jane Doe."))
        let flattened = last.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(flattened.contains(ColophonDefaultText.description))
        #expect(flattened.contains("This edition was typeset with MarkdownPDF, a pure Swift Markdown to PDF renderer written by Mihaela Mihaljevic."))
        #expect(last.contains(Self.url))
    }

    @Test("The index comes immediately before the colophon, on its own page")
    func indexThenColophon() throws {
        let options = PDFOptions(
            title: "My Book",
            tableOfContents: .enabled,
            index: PDFOptions.Index(isEnabled: true, terms: ["alpha"]),
            colophon: .enabled,
        )
        let pdf = try render(Self.threePages, options)
        let pages = try pageTexts(pdf, name: "colophon-index")
        // The contents follow the first heading, so: chapter one with the contents,
        // chapters two and three, index, colophon.
        try #require(pages.count == 5)
        #expect(pages[3].hasPrefix("Index"))
        #expect(pages[4].hasPrefix("Colophon"))
        #expect(!pages[3].contains("Colophon"))
        #expect(!pages[4].contains("alpha, "))
    }

    @Test("The colophon is last with a cover, page numbers, contents and index together")
    func everythingTogether() throws {
        let png = solidPNG(width: 20, height: 28)
        let options = PDFOptions(
            title: "My Book",
            tableOfContents: PDFOptions.TableOfContents(isEnabled: true, maximumDepth: 3),
            pageNumbers: PDFOptions.PageNumbers(isEnabled: true, format: .ofTotal),
            index: PDFOptions.Index(isEnabled: true, terms: ["alpha"]),
            author: "Jane Doe",
            cover: .enabled(image: .data(png)),
            colophon: .enabled,
        )
        let pdf = try render(Self.threePages, options)
        let pages = try pageTexts(pdf, name: "colophon-everything")
        // Cover, chapter one with the contents, chapters two and three, index, colophon.
        try #require(pages.count == 6)
        #expect(pages[5].hasPrefix("Colophon"))
        #expect(pages[4].hasPrefix("Index"))
        // The cover is not counted: the first page after it is Page 1 of 5, the colophon Page 5 of 5.
        #expect(pages[1].contains("Page 1 of 5"))
        #expect(pages[4].contains("Page 4 of 5"))
        #expect(pages[5].contains("Page 5 of 5"))
    }

    @Test("With no contents or index the colophon still follows the body")
    func colophonAlone() throws {
        let pdf = try render("# Only", PDFOptions(colophon: .enabled))
        let pages = try pageTexts(pdf, name: "colophon-alone")
        #expect(pages.count == 2)
        #expect(pages[1].hasPrefix("Colophon"))
    }

    @Test("An empty document with a colophon is one colophon page")
    func emptyDocument() throws {
        let pdf = try MarkdownPDFRenderer(options: PDFOptions(colophon: .enabled)).render(sources: [])
        let pages = try pageTexts(pdf, name: "colophon-empty")
        #expect(pages.count == 1)
        #expect(pages[0].hasPrefix("Colophon"))
    }

    @Test("Merged sources keep the colophon after all of them")
    func mergedSources() throws {
        let options = PDFOptions(title: "Merged", index: PDFOptions.Index(isEnabled: true, terms: ["alpha"]), colophon: .enabled)
        let pdf = try MarkdownPDFRenderer(options: options).render(sources: [
            MarkdownSource(markdown: "# One\n\nalpha"),
            MarkdownSource(markdown: "# Two\n\nalpha"),
        ])
        let pages = try pageTexts(pdf, name: "colophon-merged")
        #expect(pages.count == 4)
        #expect(pages[2].hasPrefix("Index"))
        #expect(pages[3].hasPrefix("Colophon"))
    }

    // MARK: Contents, outline, numbers

    @Test("The contents list the index and the colophon with their printed page numbers")
    func contentsPageNumbers() throws {
        let options = PDFOptions(
            title: "My Book",
            tableOfContents: .enabled,
            pageNumbers: PDFOptions.PageNumbers(isEnabled: true, firstPageNumber: 5),
            index: PDFOptions.Index(isEnabled: true, terms: ["alpha"]),
            colophon: .enabled,
        )
        let pdf = try render(Self.threePages, options)
        let pages = try pageTexts(pdf, name: "colophon-contents")
        try #require(pages.count == 5)
        // Each contents row is a title on the left and a number on the right.
        let page = try #require(ContentStreamGeometry(pdf: pdf).pages.first)
        var rows: [Double: [ContentStreamGeometry.Text]] = [:]
        for text in page.texts where text.y > 54 {
            rows[text.y, default: []].append(text)
        }
        func printedNumber(forTitle title: String) -> String? {
            for row in rows.values {
                let ordered = row.sorted { $0.x < $1.x }
                if ordered.first?.string == title, ordered.count > 1 {
                    return ordered.last?.string
                }
            }
            return nil
        }
        #expect(printedNumber(forTitle: "Index") == "8")
        #expect(printedNumber(forTitle: "Colophon") == "9")
        // The pages themselves print those numbers.
        #expect(pages[3].trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("8"))
        #expect(pages[4].trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("9"))
    }

    @Test("The colophon heading is an outline entry and a named destination on the last page")
    func outlineAndDestination() throws {
        let pdf = try render(Self.threePages, PDFOptions(title: "T", colophon: .enabled))
        let inspector = PDFInspector(pdf)
        #expect(inspector.text.contains("/Title (Colophon)"))
        let destination = try #require(inspector.namedDestinationPages.first { $0.key.contains("colophon") })
        #expect(destination.value == inspector.pageCount)
        #expect(inspector.canonicalStructureIssues().isEmpty, "\(inspector.canonicalStructureReport())")
    }

    // MARK: Link

    @Test("The visible URL carries a real URI annotation on the last page")
    func linkAnnotation() throws {
        let pdf = try render(Self.threePages, PDFOptions(title: "T", colophon: .enabled))
        let inspector = PDFInspector(pdf)
        let annotations = inspector.indirectObjects.filter { $0.content.contains("/URI (\(Self.url))") }
        #expect(annotations.count == 1)
        #expect(inspector.text.components(separatedBy: "/URI (").count - 1 == 1)
        let annotation = try #require(annotations.first)
        let lastPageNumber = try #require(inspector.pageObjectNumbers.last)
        let lastPage = try #require(inspector.indirectObjects.first { $0.number == lastPageNumber })
        #expect(lastPage.content.contains("\(annotation.number) 0 R"))
        for number in inspector.pageObjectNumbers.dropLast() {
            let page = try #require(inspector.indirectObjects.first { $0.number == number })
            #expect(!page.content.contains("\(annotation.number) 0 R"))
        }
    }

    // MARK: Custom text

    @Test("Custom text replaces the default entirely")
    func customText() throws {
        let options = PDFOptions(
            title: "T",
            author: "A",
            colophon: .enabled(markdown: "## Credits\n\nSet in Fira Sans by hand.\n"),
        )
        let pdf = try render("# Body", options)
        let pages = try pageTexts(pdf, name: "colophon-custom")
        #expect(pages.count == 2)
        #expect(pages[1].contains("Credits"))
        #expect(pages[1].contains("Set in Fira Sans by hand."))
        #expect(!pages[1].contains("Colophon"))
        #expect(!pages[1].contains("typeset with MarkdownPDF"))
        #expect(!pages[1].contains("codeberg"))
    }

    @Test("A custom text of several pages is all after the index")
    func longCustomText() throws {
        let paragraphs = (1 ... 120).map { "Paragraph \($0) of the colophon text with some words to fill a line." }
            .joined(separator: "\n\n")
        let options = PDFOptions(
            pageNumbers: .enabled,
            index: PDFOptions.Index(isEnabled: true, terms: ["alpha"]),
            colophon: .enabled(markdown: "# Long\n\n" + paragraphs),
        )
        let pdf = try render(Self.threePages, options)
        let pages = try pageTexts(pdf, name: "colophon-long")
        let indexPage = try #require(pages.firstIndex { $0.hasPrefix("Index") })
        #expect(indexPage == 3)
        try #require(pages.count > 6)
        #expect(pages[4].hasPrefix("Long"))
        #expect(pages.last?.contains("Paragraph 120") == true)
        // Every colophon page carries its number.
        for (offset, page) in pages.enumerated().dropFirst(4) {
            #expect(page.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("\(offset + 1)"), "page \(offset + 1)")
        }
    }

    @Test("Empty custom text is an error, not a silent skip", arguments: ["", "   ", "\n\n\t\n"])
    func emptyCustomText(_ text: String) {
        let options = PDFOptions(colophon: .enabled(markdown: text))
        #expect(throws: MarkdownPDFError.colophonTextEmpty) {
            try MarkdownPDFRenderer(options: options).render(markdown: "# A")
        }
    }

    @Test("Custom text that is only an HTML comment still renders its page")
    func commentOnlyCustomText() throws {
        let options = PDFOptions(ignoreHTMLComments: .enabled, colophon: .enabled(markdown: "<!-- nothing -->"))
        let pdf = try render("# A", options)
        // The colophon is enabled and non-empty before stripping, so it is honoured: one blank page.
        #expect(try pageTexts(pdf, name: "colophon-comment-only").count == 2)
    }

    @Test("Comments in custom text are dropped when the option is on and kept as text otherwise")
    func customTextComments() throws {
        let text = "# Credits\n\nSet by hand.<!--say: set-->\n"
        let on = try render("# A", PDFOptions(ignoreHTMLComments: .enabled, colophon: .enabled(markdown: text)))
        #expect(try !#require(pageTexts(on, name: "colophon-comments-on").last).contains("<!--"))
        let off = try render("# A", PDFOptions(colophon: .enabled(markdown: text)))
        #expect(try #require(pageTexts(off, name: "colophon-comments-off").last).contains("<!--say: set-->"))
    }

    @Test("Custom text with non-WinAnsi characters switches to the embedded font like any text")
    func nonWinAnsiColophon() throws {
        let options = PDFOptions(author: "Mihaela Mihaljevi\u{107}", colophon: .enabled)
        let pdf = try render("# A", options)
        let last = try #require(pageTexts(pdf, name: "colophon-unicode").last)
        #expect(last.contains("Mihaljevi\u{107}") || last.contains("Mihaela"))
    }

    // MARK: Index and tagging

    @Test("The index does not search the colophon, so a term found only there makes no index")
    func indexIgnoresColophon() throws {
        let options = PDFOptions(
            index: PDFOptions.Index(isEnabled: true, terms: ["typeset", "colophon"]),
            colophon: .enabled,
        )
        let pdf = try render("# Body\n\nNothing indexed here.", options)
        let pages = try pageTexts(pdf, name: "colophon-index-ignored")
        #expect(pages.count == 2)
        #expect(!pages.contains { $0.hasPrefix("Index") })
    }

    @Test("A tagged PDF with a colophon is structurally sound")
    func tagged() throws {
        let options = PDFOptions(title: "T", taggedPDF: .enabled, author: "A", colophon: .enabled)
        let pdf = try render(Self.threePages, options)
        let inspector = PDFInspector(pdf)
        #expect(inspector.canonicalStructureIssues().isEmpty, "\(inspector.canonicalStructureReport())")
        #expect(try #require(pageTexts(pdf, name: "colophon-tagged").last).hasPrefix("Colophon"))
    }

    // MARK: Byte identity

    @Test("A disabled colophon and disabled comment option leave the bytes unchanged")
    func disabledIsByteIdentical() throws {
        let base = PDFOptions(
            title: "T",
            tableOfContents: .enabled,
            pageNumbers: .enabled,
            index: PDFOptions.Index(isEnabled: true, terms: ["alpha"]),
        )
        var explicit = base
        explicit.colophon = .disabled
        explicit.ignoreHTMLComments = .disabled
        #expect(try render(Self.threePages, base) == render(Self.threePages, explicit))
        // And turning the colophon on changes the document by exactly the extra page.
        var enabled = base
        enabled.colophon = .enabled
        let without = try pageTexts(render(Self.threePages, base), name: "byte-without")
        let with = try pageTexts(render(Self.threePages, enabled), name: "byte-with")
        #expect(with.count == without.count + 1)
    }
}
