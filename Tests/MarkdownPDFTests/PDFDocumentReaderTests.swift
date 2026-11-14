import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: files whose content is known before the reader sees them. One is written
/// out by hand in this file, byte by byte, so the reader is not only checked against
/// the engine that shares its author; the others are rendered from Markdown whose
/// words, headings and links are the expected answer.
@Suite("PDF document reader")
struct PDFDocumentReaderTests {
    /// A two page PDF written by hand: a literal string with escapes, a hexadecimal
    /// string, a second page that inherits its media box, a link, an outline of two
    /// levels, an Info dictionary with one WinAnsi and one UTF-16BE string, and a
    /// `/Length` given by reference.
    private static func handWritten() -> Data {
        let objects: [String] = [
            "<< /Type /Catalog /Pages 2 0 R /Outlines 9 0 R >>",
            "<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 /MediaBox [0 0 200 300] /Resources << /Font << /F1 5 0 R >> >> >>",
            "<< /Type /Page /Parent 2 0 R /Contents 4 0 R /Annots [8 0 R] >>",
            "STREAM:BT /F1 12 Tf 20 250 Td (Hello \\(wor\\154d\\) ) Tj ET\nBT /F1 12 Tf 90 250 Td <4142> Tj ET\nBT /F1 12 Tf 20 230 Td (caf\\351) Tj ET",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 150] /Contents 7 0 R >>",
            "STREAM:BT /F1 9 Tf 10 100 Td (Second) Tj ET",
            "<< /Type /Annot /Subtype /Link /Rect [20 245 80 262] /A << /S /URI /URI (https://example.com/a) >> >>",
            "<< /Type /Outlines /First 10 0 R /Last 10 0 R /Count 2 >>",
            "<< /Title (Top) /Parent 9 0 R /First 11 0 R /Last 11 0 R /Count 1 /Dest (top) >>",
            "<< /Title <FEFF010C00610073> /Parent 10 0 R /A << /S /GoTo /D (inner) >> >>",
            "<< /Title (Report) /Author <FEFF004A0061006B00690107> >>",
        ]
        var text = "%PDF-1.4\n"
        var offsets: [Int] = []
        var lengthObjects: [(number: Int, length: Int)] = []
        var nextNumber = objects.count + 1
        for (index, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            if object.hasPrefix("STREAM:") {
                let body = String(object.dropFirst(7))
                // The first stream names its length directly, the second by reference.
                if lengthObjects.isEmpty, index != 3 {
                    lengthObjects.append((nextNumber, body.utf8.count))
                    text += "\(index + 1) 0 obj\n<< /Length \(nextNumber) 0 R >>\nstream\n\(body)\nendstream\nendobj\n"
                    nextNumber += 1
                } else {
                    text += "\(index + 1) 0 obj\n<< /Length \(body.utf8.count) >>\nstream\n\(body)\nendstream\nendobj\n"
                }
            } else {
                text += "\(index + 1) 0 obj\n\(object)\nendobj\n"
            }
        }
        for entry in lengthObjects {
            offsets.append(text.utf8.count)
            text += "\(entry.number) 0 obj\n\(entry.length)\nendobj\n"
        }
        let xref = text.utf8.count
        text += "xref\n0 \(offsets.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            text += String(repeating: "0", count: 10 - String(offset).count) + "\(offset) 00000 n \n"
        }
        text += "trailer\n<< /Size \(offsets.count + 1) /Root 1 0 R /Info 12 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(text.utf8)
    }

    @Test("A PDF written by hand reads back as what was typed into it")
    func handWrittenFile() throws {
        let document = try PDFDocumentReader(data: Self.handWritten())

        #expect(document.pageCount == 2)
        #expect(document.pages.map(\.size) == [PDFOptions.PageSize(width: 200, height: 300), PDFOptions.PageSize(width: 100, height: 150)])
        #expect(document.pages[0].lines == ["Hello (world) AB", "caf\u{E9}"])
        #expect(document.pages[1].lines == ["Second"])
        #expect(document.text == "Hello (world) AB\ncaf\u{E9}\u{0C}Second")
        // Helvetica declares no widths in the file; the advance is the standard table's:
        // "Hello (world) " is 722+556+222+222+556+278+333+722+556+333+222+556+333+278 = 5889
        // thousandths of 12 pt in the Adobe metrics.
        #expect(document.pages[0].runs.first == PDFDocumentReader.TextRun(x: 20, y: 250, width: 5889 * 12 / 1000, fontSize: 12, fontName: "Helvetica", text: "Hello (world) "))
        #expect(document.links == [PDFDocumentReader.Link(x: 20, y: 245, width: 60, height: 17, target: .uri("https://example.com/a"))])
        #expect(document.title == "Report")
        #expect(document.author == "Jaki\u{107}")
        #expect(document.outline == [
            PDFDocumentReader.OutlineItem(title: "Top", level: 1, destination: "top", pageIndex: nil),
            PDFDocumentReader.OutlineItem(title: "\u{10C}as", level: 2, destination: "inner", pageIndex: nil),
        ])
    }

    @Test("What is not a PDF this reader reads is refused, never read wrongly")
    func refusals() {
        func error(_ data: Data) -> PDFDocumentReader.ReadError? {
            do {
                _ = try PDFDocumentReader(data: data)
                return nil
            } catch {
                return error as? PDFDocumentReader.ReadError
            }
        }
        let good = String(decoding: Self.handWritten(), as: UTF8.self)

        #expect(error(Data()) == .malformed("the file does not start with %PDF-"))
        #expect(error(Data("hello".utf8)) == .malformed("the file does not start with %PDF-"))
        #expect(error(Data("%PDF-1.4\nnothing".utf8)) == .malformed("the file has no startxref"))
        #expect(error(Data(good.replacingOccurrences(of: "xref\n0 ", with: "xrex\n0 ").utf8)) == .unsupported("a cross-reference stream"))
        #expect(error(Data(good.replacingOccurrences(of: "/Root 1 0 R", with: "/Root 1 0 R /Encrypt 5 0 R").utf8)) == .unsupported("an encrypted file"))
        #expect(error(Data(good.replacingOccurrences(of: "/Root 1 0 R", with: "/Root 99 0 R").utf8)) == .malformed("the catalog is missing or is not a dictionary"))
        #expect(error(Data(good.replacingOccurrences(of: "/F1 9 Tf", with: "/F7 9 Tf").utf8)) == .malformed("the font /F7 is not in the page resources"))
        // A truncated file loses its cross-reference table.
        #expect(error(Data(good.utf8.prefix(300))) != nil)
    }

    @Test("A rendered document reads back: pages, size, words, headings, links, title and author", arguments: [false, true])
    func renderedDocument(compressed: Bool) throws {
        let markdown = """
        # Report

        Plain words and **bold words** and *italic words* and `code words`.

        ## Second part

        - one item
        - [a link](https://example.com/page)

        See [the start](#report).
        """
        var options = PDFOptions(title: "The Title", author: "A. Writer")
        options.pageSize = .a5
        options.streamCompression = compressed ? .enabled : .disabled
        let document = try PDFDocumentReader(data: MarkdownPDFRenderer(options: options).render(markdown: markdown))

        #expect(document.pageCount == 1)
        #expect(document.pages[0].size == PDFOptions.PageSize.a5)
        #expect(document.title == "The Title")
        #expect(document.author == "A. Writer")
        #expect(document.outline.map(\.title) == ["Report", "Second part"])
        #expect(document.outline.map(\.level) == [1, 2])
        #expect(document.pages[0].lines == [
            "Report",
            "Plain words and bold words and italic words and code words.",
            "Second part",
            "\u{2022} one item",
            "\u{2022} a link",
            "See the start.",
        ])
        #expect(document.outline.map(\.pageIndex) == [0, 0])
        // Each word of a link is its own rectangle.
        #expect(document.links.map(\.target) == [
            .uri("https://example.com/page"), .uri("https://example.com/page"), .destination("report"), .destination("report"),
        ])
        // The link rectangle sits on the words it belongs to.
        let linked = try #require(document.pages[0].runs.first { $0.text.hasPrefix("a ") })
        let link = try #require(document.links.first)
        #expect(abs(link.x - linked.x) < 0.01)
        #expect(link.y < linked.y && linked.y < link.y + link.height)
        #expect(Set(document.pages[0].runs.map(\.fontName)) == ["Helvetica", "Helvetica-Bold", "Helvetica-Oblique", "Courier"])
    }

    @Test("Every word of a long document comes back in order, on the page count the file declares")
    func longDocumentRoundTrip() throws {
        let words = (1 ... 3000).map { "w\($0)" }
        let markdown = stride(from: 0, to: words.count, by: 100).map { words[$0 ..< $0 + 100].joined(separator: " ") }.joined(separator: "\n\n")
        let pdf = try MarkdownPDFRenderer().render(markdown: markdown)
        let document = try PDFDocumentReader(data: pdf)

        #expect(document.pageCount == PDFInspector(pdf).pageCount)
        #expect(document.pageCount > 1)
        let read = document.pages.flatMap(\.lines).flatMap { $0.split(separator: " ").map(String.init) }
        #expect(read == words)
    }

    @Test("Text in an embedded font is read through its ToUnicode map, plain or compressed", arguments: [false, true])
    func embeddedFontText(compressed: Bool) throws {
        try #require(PDFOptions.EmbeddedFonts.dejaVu != .disabled)
        var options = PDFOptions(embeddedFonts: .dejaVu)
        options.streamCompression = compressed ? .enabled : .disabled
        let text = "Greek \u{3B1}\u{3B2}\u{3B3}, Cyrillic \u{41F}\u{440}\u{438}\u{432}\u{435}\u{442}, ligatures office affine."
        let document = try PDFDocumentReader(data: MarkdownPDFRenderer(options: options).render(markdown: text))

        #expect(document.pages[0].lines == [text])
        #expect(document.pages[0].runs.allSatisfy { $0.fontName.hasSuffix("DejaVuSans") })
        #expect(document.fonts.count == 1)
        #expect(document.fonts.allSatisfy { $0.isEmbedded && $0.name.hasSuffix("DejaVuSans") })
    }

    @Test("The fonts and the tagged flag are the ones the options asked for")
    func fontsAndTagging() throws {
        let markdown = "Plain, **bold** and `code`."
        let plain = try PDFDocumentReader(data: MarkdownPDFRenderer().render(markdown: markdown))
        #expect(plain.fonts == [
            PDFDocumentReader.Font(name: "Courier", isEmbedded: false),
            PDFDocumentReader.Font(name: "Helvetica", isEmbedded: false),
            PDFDocumentReader.Font(name: "Helvetica-Bold", isEmbedded: false),
        ])
        #expect(!plain.isTagged)

        let tagged = try PDFDocumentReader(data: MarkdownPDFRenderer(options: PDFOptions(taggedPDF: .enabled)).render(markdown: markdown))
        #expect(tagged.isTagged)
        #expect(tagged.pages[0].lines == ["Plain, bold and code."])
    }

    @Test("A run's width is the advance the layout measured, in a base font and in an embedded one", arguments: [false, true])
    func runWidths(embedded: Bool) throws {
        try #require(PDFOptions.EmbeddedFonts.dejaVu != .disabled)
        let options = PDFOptions(embeddedFonts: embedded ? .dejaVu : .disabled)
        let document = try PDFDocumentReader(data: MarkdownPDFRenderer(options: options).render(markdown: "alpha beta gamma delta"))
        let runs = document.pages[0].runs
        try #require(runs.map(\.text) == ["alpha ", "beta ", "gamma ", "delta"])

        // Each word starts where the one before it ends. An embedded font declares whole
        // thousandths of an em for each glyph, so a word can be a few hundredths of a point off.
        for (run, next) in zip(runs, runs.dropFirst()) {
            #expect(abs(run.x + run.width - next.x) < 0.05, "\(run.text) ends at \(run.x + run.width), \(next.text) starts at \(next.x)")
        }
        if !embedded {
            let expected = StandardFont.helvetica.width(of: "alpha ", size: 11, fontSet: .pdfBase)
            #expect(abs(runs[0].width - expected) < 0.001)
        }
    }

    @Test("Cells of a table row read as separate words")
    func tableCellsAreSeparated() throws {
        let document = try PDFDocumentReader(data: MarkdownPDFRenderer().render(markdown: "| City | County |\n|---|---|\n| Split | Dalmatia |\n"))
        #expect(document.pages[0].lines == ["City County", "Split Dalmatia"])
    }

    @Test("The reader agrees with the structure the engine's own inspector finds", arguments: ["technical-report", "showcase/01-combined-showcase", "democv"])
    func agreesWithTheInspector(fixture: String) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(fixture).md")
        let markdown = try String(contentsOf: url, encoding: .utf8)
        let options = PDFOptions(title: "Fixture")
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: markdown, assetsBaseURL: url.deletingLastPathComponent())
        let inspector = PDFInspector(pdf)
        let document = try PDFDocumentReader(data: pdf)

        #expect(document.pageCount == inspector.pageCount)
        #expect(document.links.count == inspector.linkAnnotationCount)
        #expect(document.outline.count == inspector.outlineItemCount)
        #expect(document.title == "Fixture")
        #expect(document.pages.allSatisfy { !$0.runs.isEmpty })
    }
}
