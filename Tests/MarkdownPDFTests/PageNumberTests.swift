import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: the footer of page `i` (zero based) must read the printed label of number
/// `firstPageNumber + i`, computed here by an independent reference (a lookup of
/// Roman numerals, plain decimal), at the x the position rule gives, inside the
/// bottom margin and clear of every body line. Geometry comes from the content
/// stream; text comes from Poppler.
@Suite("Page numbers")
struct PageNumberTests {
    /// Five pages of body text separated by explicit page breaks.
    private static let fivePages = (1 ... 5).map { "# Section \($0)\n\nBody of page \($0)." }
        .joined(separator: "\n\n<!-- pagebreak -->\n\n")

    private static let roman = ["", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii"]

    private func geometryOf(_ markdown: String, _ options: PDFOptions) throws -> ContentStreamGeometry {
        try ContentStreamGeometry(pdf: MarkdownPDFRenderer(options: options).render(markdown: markdown))
    }

    private func footer(of page: ContentStreamGeometry.Page, margin: Double = 54) -> ContentStreamGeometry.Text? {
        page.texts.first { $0.y < margin }
    }

    private func footerWidth(_ text: ContentStreamGeometry.Text) -> Double {
        PDFTextRun(text: text.string, font: .helvetica, size: text.size).width(fontSet: .pdfBase)
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

    @Test("Plain format prints 1 ... N, in the bottom margin, below all body text")
    func plainFormat() throws {
        let options = PDFOptions(pageNumbers: .enabled)
        let geometry = try geometryOf(Self.fivePages, options)
        #expect(geometry.pages.count == 5)

        for (index, page) in geometry.pages.enumerated() {
            let footer = try #require(footer(of: page), "page \(index + 1) has no footer")
            #expect(footer.string == "\(index + 1)")
            #expect(abs(footer.size - 11 * 0.8) < 0.001)
            // The footer lies wholly inside the margin band, with a gap above it.
            #expect(footer.top < options.margins.bottom - 4)
            #expect(footer.bottom > 0)
            for body in page.texts where body != footer {
                #expect(body.bottom >= options.margins.bottom, "body line '\(body.string)' dips into the margin")
            }
            // Centred on the content area.
            let centre = footer.x + footerWidth(footer) / 2
            #expect(abs(centre - options.pageSize.width / 2) < 0.01)
        }
    }

    @Test("Default options draw no footer")
    func disabledByDefault() throws {
        let geometry = try geometryOf(Self.fivePages, PDFOptions())
        for page in geometry.pages {
            #expect(footer(of: page) == nil)
        }
        let plain = try MarkdownPDFRenderer().render(markdown: Self.fivePages)
        let explicit = try MarkdownPDFRenderer(options: PDFOptions(pageNumbers: .disabled)).render(markdown: Self.fivePages)
        #expect(plain == explicit)
    }

    @Test("Page N of M counts to the printed number of the last page", arguments: [1, 5, 40])
    func ofTotal(first: Int) throws {
        let options = PDFOptions(pageNumbers: PDFOptions.PageNumbers(isEnabled: true, format: .ofTotal, firstPageNumber: first))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: Self.fivePages)
        let geometry = ContentStreamGeometry(pdf: pdf)
        let last = first + 4
        for (index, page) in geometry.pages.enumerated() {
            let footer = try #require(footer(of: page))
            #expect(footer.string == "Page \(first + index) of \(last)")
        }
        // Poppler reads the same words.
        let pages = try pageTexts(pdf, name: "of-total-\(first)")
        #expect(pages.count == 5)
        #expect(pages[4].contains("Page \(last) of \(last)"))
    }

    @Test("Roman lowercase for front matter, decimal outside 1 to 3999")
    func romanLowercase() throws {
        let options = PDFOptions(pageNumbers: PDFOptions.PageNumbers(isEnabled: true, format: .romanLowercase))
        let geometry = try geometryOf(Self.fivePages, options)
        for (index, page) in geometry.pages.enumerated() {
            #expect(try #require(footer(of: page)).string == Self.roman[index + 1])
        }
        // A first number of 0 has no Roman form: decimal for that page, Roman after.
        let zero = PDFOptions(pageNumbers: PDFOptions.PageNumbers(isEnabled: true, format: .romanLowercase, firstPageNumber: 0))
        let zeroGeometry = try geometryOf(Self.fivePages, zero)
        #expect(zeroGeometry.pages.compactMap { footer(of: $0)?.string } == ["0", "i", "ii", "iii", "iv"])
        #expect(PDFPageLabel.roman(3999) == "mmmcmxcix")
        #expect(PDFPageLabel.roman(1994) == "mcmxciv")
        #expect(PDFPageLabel.roman(4000) == nil)
        #expect(PDFPageLabel.roman(0) == nil)
    }

    @Test("A first page number and skipping the first page")
    func firstNumberAndSkip() throws {
        let options = PDFOptions(
            pageNumbers: PDFOptions.PageNumbers(isEnabled: true, firstPageNumber: 7, skipsFirstPage: true),
        )
        let geometry = try geometryOf(Self.fivePages, options)
        let labels = geometry.pages.map { footer(of: $0)?.string }
        // The cover counts as page 7 but prints nothing.
        #expect(labels == [nil, "8", "9", "10", "11"])
    }

    @Test("Outside position alternates by printed parity; right aligns to the margin")
    func positions() throws {
        let pageWidth = PDFOptions().pageSize.width
        let margin = 54.0
        let outside = try geometryOf(
            Self.fivePages,
            PDFOptions(pageNumbers: PDFOptions.PageNumbers(isEnabled: true, position: .bottomOutside, firstPageNumber: 2)),
        )
        for (index, page) in outside.pages.enumerated() {
            let footer = try #require(footer(of: page))
            let number = 2 + index
            if number.isMultiple(of: 2) {
                #expect(abs(footer.x - margin) < 0.01, "even page \(number) belongs on the left")
            } else {
                #expect(abs(footer.x + footerWidth(footer) - (pageWidth - margin)) < 0.01, "odd page \(number) belongs on the right")
            }
        }

        let right = try geometryOf(Self.fivePages, PDFOptions(pageNumbers: PDFOptions.PageNumbers(isEnabled: true, position: .bottomRight)))
        for page in right.pages {
            let footer = try #require(footer(of: page))
            #expect(abs(footer.x + footerWidth(footer) - (pageWidth - margin)) < 0.01)
        }
    }

    @Test("A bottom margin too small for the footer is an error")
    func marginTooSmall() {
        let options = PDFOptions(
            margins: PDFOptions.Margins(top: 54, right: 54, bottom: 10, left: 54),
            pageNumbers: .enabled,
        )
        #expect(throws: MarkdownPDFError.pageNumbersNeedBottomMargin(minimum: 17.6, actual: 10)) {
            try MarkdownPDFRenderer(options: options).render(markdown: "# Hi")
        }
    }

    @Test("Footers are artifacts when the document is tagged, and the PDF stays well formed")
    func taggedFootersAreArtifacts() throws {
        let options = PDFOptions(taggedPDF: .enabled, pageNumbers: .enabled)
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: Self.fivePages)
        let inspector = PDFInspector(pdf)
        let streams = inspector.streams.map(\.body).filter { $0.contains("Tf") }
        try #require(streams.count == 5)
        for (index, stream) in streams.enumerated() {
            // The footer is the last thing on the page: an artifact, a fill colour, then
            // the text, then the end of the artifact.
            let footer = "/Artifact BMC\n0 0 0 rg\nBT /F1 8.800 Tf 0 0 Td (\(index + 1)) Tj ET\nEMC\n"
            let pattern = try Regex(NSRegularExpression.escapedPattern(for: footer).replacingOccurrences(of: "0 0 Td", with: "[0-9.]+ [0-9.]+ Td"))
            #expect(stream.hasSuffix(footer) || stream.firstMatch(of: pattern) != nil, "page \(index + 1) footer is not wrapped as an artifact")
        }
        #expect(inspector.canonicalStructureIssues().isEmpty, "\(inspector.canonicalStructureReport())")
        let qpdf = try PDFValidation.qpdfCheck(data: pdf, name: "tagged-page-numbers")
        try #require(qpdf.exitCode == 0, "qpdf failed:\n\(qpdf.output)")
    }

    @Test("Embedded-font documents draw the footer in the document font")
    func embeddedFontDocument() throws {
        let markdown = Self.fivePages + "\n\nGreek \u{3B1}\u{3B2}\u{3B3}."
        let options = PDFOptions(pageNumbers: PDFOptions.PageNumbers(isEnabled: true, format: .ofTotal))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
        let pages = try pageTexts(pdf, name: "embedded-page-numbers")
        #expect(pages.count == 5)
        #expect(pages[0].contains("Page 1 of 5"))
        #expect(pages[4].contains("Page 5 of 5"))
        let inspector = PDFInspector(pdf)
        #expect(inspector.text.contains("/Subtype /Type0"), "the body should have selected the bundled DejaVu faces")
    }

    @Test("PDF/UA-1 and PDF/A-2a output with page numbers validates")
    func conformanceWithPageNumbers() throws {
        let options = PDFOptions(
            embeddedFonts: .dejaVu,
            title: "Conformance Book",
            conformance: .pdfUA1AndPDFA2A,
            pageNumbers: PDFOptions.PageNumbers(isEnabled: true, format: .ofTotal),
        )
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: Self.fivePages)
        let ua1 = try PDFValidation.veraPDF(data: pdf, name: "page-numbers-ua1", flavour: "ua1")
        #expect(ua1.exitCode == 0, "veraPDF ua1 failed:\n\(ua1.output)")
        #expect(ua1.output.contains("\"compliant\" : true"))
        let a2a = try PDFValidation.veraPDF(data: pdf, name: "page-numbers-2a", flavour: "2a")
        #expect(a2a.exitCode == 0, "veraPDF 2a failed:\n\(a2a.output)")
        #expect(a2a.output.contains("\"compliant\" : true"))
    }

    @Test("A conformance profile with base fonts refuses page numbers like any other text")
    func conformanceWithBaseFontsIsRefused() {
        let options = PDFOptions(
            title: "Conformance Book",
            conformance: .pdfA2A,
            pageNumbers: .enabled,
        )
        #expect(throws: MarkdownPDFError.self) {
            try MarkdownPDFRenderer(options: options).render(markdown: "# Hi")
        }
    }

    @Test("Table of contents and footers agree, with a custom first number and Roman format")
    func tableOfContentsAgreesWithFooters() throws {
        let options = PDFOptions(
            tableOfContents: .enabled,
            pageNumbers: PDFOptions.PageNumbers(isEnabled: true, format: .romanLowercase, firstPageNumber: 3),
        )
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: Self.fivePages)
        let pages = try pageTexts(pdf, name: "toc-agrees")
        let geometry = ContentStreamGeometry(pdf: pdf)
        let labels = ["iii", "iv", "v", "vi", "vii", "viii"]
        // A contents row is the words of a title followed by its number at one
        // baseline, drawn smaller than body text.
        var rows: [Double: [ContentStreamGeometry.Text]] = [:]
        for text in geometry.pages[0].texts where text.size < 11 && text.y > options.margins.bottom {
            rows[text.y, default: []].append(text)
        }
        var contentsRows: [Int: String] = [:]
        for row in rows.values {
            let ordered = row.sorted { $0.x < $1.x }
            let title = ordered.dropLast().map(\.string).joined().trimmingCharacters(in: .whitespaces)
            if title.hasPrefix("Section "), let section = Int(title.dropFirst("Section ".count)), let last = ordered.last {
                contentsRows[section] = last.string
            }
        }
        // The contents sit on the first page, after "Section 1". Each contents row
        // is a title and a number at the same baseline; the number must equal the
        // footer of the physical page whose text holds that section's body line.
        for section in 1 ... 5 {
            let physical = try #require(pages.firstIndex { $0.contains("Body of page \(section).") })
            let number = try #require(contentsRows[section], "no contents row for Section \(section)")
            #expect(number == labels[physical], "contents says \(number) for Section \(section), footer says \(labels[physical])")
        }
    }
}
