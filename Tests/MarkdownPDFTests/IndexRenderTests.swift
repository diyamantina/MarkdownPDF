import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: documents whose pages are fixed by explicit page breaks, so the pages a
/// term lands on are known by construction; and a long document whose term pages
/// are read back independently from Poppler's per-page text.
@Suite("Index rendering")
struct IndexRenderTests {
    private static let sixPages = [
        "# One\n\nAlpha is here. {{index: gamma}}",
        "Beta is here.",
        "alpha and BETA together, plus `alpha` in code.\n\n```\nalpha in a block\n```",
        "{{index: delta}}\n\nPlain text.",
        "{{index: delta}}\n\nPage five text.",
        "{{index: delta > sub item}} Page six text.",
    ].joined(separator: "\n\n<!-- pagebreak -->\n\n")

    private func render(_ markdown: String, _ options: PDFOptions) throws -> Data {
        try MarkdownPDFRenderer(options: options).render(markdown: markdown)
    }

    /// The rows of a page: fragments sharing a baseline, joined left to right.
    private func rows(of page: ContentStreamGeometry.Page) -> [(text: String, x: Double)] {
        var byBaseline: [Double: [ContentStreamGeometry.Text]] = [:]
        for text in page.texts where text.y > 54 {
            byBaseline[text.y, default: []].append(text)
        }
        return byBaseline.keys.sorted(by: >).map { y in
            let row = byBaseline[y, default: []].sorted { $0.x < $1.x }
            return (row.map(\.string).joined(), row.first?.x ?? 0)
        }
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

    @Test("Markers and term-list matches land on the right pages, sorted and grouped")
    func entriesPagesAndLayout() throws {
        let options = PDFOptions(index: PDFOptions.Index(isEnabled: true, terms: ["alpha", "beta"]))
        let pdf = try render(Self.sixPages, options)
        let geometry = ContentStreamGeometry(pdf: pdf)
        try #require(geometry.pages.count == 7)

        let rows = rows(of: geometry.pages[6])
        #expect(rows.map(\.text) == [
            "Index", "A", "alpha, 1, 3", "B", "beta, 2-3", "D", "delta, 4-5", "sub item, 6", "G", "gamma, 1",
        ])
        // Sub-entries are indented relative to their main entry.
        let delta = try #require(rows.first { $0.text == "delta, 4-5" })
        let sub = try #require(rows.first { $0.text == "sub item, 6" })
        #expect(sub.x - delta.x >= 15)

        // Nothing from the markers reached the body.
        for page in geometry.pages.prefix(6) {
            for text in page.texts {
                #expect(!text.string.contains("{{"))
                #expect(!text.string.contains("index:"))
            }
        }

        // Poppler reads the same index.
        let pages = try pageTexts(pdf, name: "index-layout")
        #expect(pages.count == 7)
        #expect(pages[6].contains("alpha, 1, 3"))
    }

    @Test("Page references are internal links to the page and the document stays well formed")
    func linksTargetPages() throws {
        let options = PDFOptions(index: PDFOptions.Index(isEnabled: true, terms: ["alpha", "beta"]))
        let pdf = try render(Self.sixPages, options)
        let inspector = PDFInspector(pdf)

        #expect(inspector.canonicalStructureIssues().isEmpty, "\(inspector.canonicalStructureReport())")
        // One link per printed reference, aimed at its first page: the ranges 2-3 and
        // 4-5 link to pages 2 and 4, so pages 5 and 7 have no link.
        for page in [1, 2, 3, 4, 6] {
            #expect(inspector.text.contains("mdpdf-page-\(page)"), "no link to page \(page)")
        }
        #expect(!inspector.text.contains("mdpdf-page-5"))
        #expect(!inspector.text.contains("mdpdf-page-7"))
        let qpdf = try PDFValidation.qpdfCheck(data: pdf, name: "index-links")
        try #require(qpdf.exitCode == 0, "qpdf failed:\n\(qpdf.output)")
    }

    @Test("The index heading is in the outline and in the table of contents with its page number")
    func headingInOutlineAndContents() throws {
        let options = PDFOptions(
            tableOfContents: .enabled,
            index: PDFOptions.Index(isEnabled: true, title: "Back Index", terms: ["alpha"]),
        )
        let pdf = try render(Self.sixPages, options)
        let geometry = ContentStreamGeometry(pdf: pdf)
        let pageCount = geometry.pages.count

        #expect(PDFInspector(pdf).text.contains("/Title (Back Index)"))
        let firstRows = rows(of: geometry.pages[0])
        let contents = try #require(firstRows.first { $0.text.hasPrefix("Back Index") && $0.text != "Back Index" })
        #expect(contents.text == "Back Index\(pageCount)")
        #expect(rows(of: geometry.pages[pageCount - 1]).first?.text == "Back Index")
    }

    @Test("Custom page numbers drive the index references")
    func customLabels() throws {
        let options = PDFOptions(
            pageNumbers: PDFOptions.PageNumbers(isEnabled: true, format: .romanLowercase, firstPageNumber: 2),
            index: PDFOptions.Index(isEnabled: true, terms: ["alpha", "beta"]),
        )
        let geometry = try ContentStreamGeometry(pdf: render(Self.sixPages, options))
        let texts = rows(of: geometry.pages[6]).map(\.text)
        // Physical pages 1 and 3 print as ii and iv; pages 2-3 as iii-iv.
        #expect(texts.contains("alpha, ii, iv"))
        #expect(texts.contains("beta, iii-iv"))
        #expect(texts.contains("delta, v-vi"))
    }

    @Test("With nothing found there is no index page and no heading")
    func nothingFound() throws {
        let enabled = PDFOptions(index: PDFOptions.Index(isEnabled: true, terms: ["absent"]))
        let pdf = try render("# Title\n\nSome text.", enabled)
        #expect(ContentStreamGeometry(pdf: pdf).pages.count == 1)
        #expect(!PDFInspector(pdf).text.contains("/Title (Index)"))
    }

    @Test("A disabled index leaves marker text alone and draws nothing extra")
    func disabledLeavesMarkersLiteral() throws {
        let pdf = try render("Text {{index: layer}} end.", PDFOptions())
        let text = try #require(pageTexts(pdf, name: "index-disabled").first)
        #expect(text.contains("{{index: layer}}"))
    }

    @Test("Code, inline code, math and link destinations are never searched")
    func excludedContexts() throws {
        let markdown = """
        Plain zeta here.

        `zeta` inline code and $zeta + 1$ math.

        [a link](https://example.com/zeta) with no hit in its destination.

        ```
        zeta in a block
        ```
        """
        let options = PDFOptions(mathTypesetting: .enabled, index: PDFOptions.Index(isEnabled: true, terms: ["zeta"]))
        let geometry = try ContentStreamGeometry(pdf: render(markdown, options))
        // One page of body, and an index page listing zeta once, on page 1: the
        // single page-1 hit is the plain paragraph.
        let indexRows = rows(of: geometry.pages[geometry.pages.count - 1]).map(\.text)
        #expect(indexRows == ["Index", "Z", "zeta, 1"])
    }

    @Test("Table cells, list items, quotes and headings are searched")
    func includedContexts() throws {
        let pages = [
            "# Heading about zeta",
            "- list item about zeta",
            "> quoted zeta",
            "| a | b |\n|---|---|\n| zeta | x |",
            "no hit here",
        ].joined(separator: "\n\n<!-- pagebreak -->\n\n")
        let options = PDFOptions(index: PDFOptions.Index(isEnabled: true, terms: ["zeta"]))
        let geometry = try ContentStreamGeometry(pdf: render(pages, options))
        let texts = rows(of: geometry.pages[geometry.pages.count - 1]).map(\.text)
        #expect(texts == ["Index", "Z", "zeta, 1-4"])
    }

    @Test("A marker whose term is empty renders nothing and records nothing")
    func emptyMarker() throws {
        let options = PDFOptions(index: PDFOptions.Index(isEnabled: true))
        let pdf = try render("Text {{index:}} and {{index:   }} end.", options)
        let geometry = ContentStreamGeometry(pdf: pdf)
        #expect(geometry.pages.count == 1)
        let text = try #require(pageTexts(pdf, name: "empty-marker").first)
        #expect(text.contains("Text and end."))
    }

    @Test("A long run of references wraps with a hanging indent and never starts a line with a comma")
    func longEntryWraps() throws {
        let pages = (1 ... 150).map { $0.isMultiple(of: 2) ? "Even page \($0)." : "Odd page \($0). {{index: wide entry}}" }
            .joined(separator: "\n\n<!-- pagebreak -->\n\n")
        let options = PDFOptions(index: PDFOptions.Index(isEnabled: true))
        let geometry = try ContentStreamGeometry(pdf: render(pages, options))
        let rows = rows(of: geometry.pages[geometry.pages.count - 1])
        let entry = try #require(rows.firstIndex { $0.text.hasPrefix("wide entry,") })
        let wrapped = Array(rows[entry...])
        try #require(wrapped.count >= 3, "the 75 references should need several lines")

        var listed: [Int] = []
        for (position, row) in wrapped.enumerated() {
            #expect(!row.text.hasPrefix(","), "line \(position) starts with a comma: \(row.text)")
            if position > 0 {
                #expect(row.x - wrapped[0].x >= 13, "continuation line is not indented")
            }
            let numbers = row.text.replacingOccurrences(of: "wide entry,", with: "")
            listed.append(contentsOf: numbers.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
        }
        #expect(listed == Array(stride(from: 1, through: 149, by: 2)))
    }

    @Test("A markers-only paragraph before a page break attaches to the next line drawn")
    func markersOnlyParagraphAttachesForward() throws {
        let filler = (1 ... 70).map { "Filler line \($0)." }.joined(separator: "\n\n")
        let options = PDFOptions(index: PDFOptions.Index(isEnabled: true))
        let pdf = try render("\(filler)\n\n{{index: marked}}\n\nAfter the marker.", options)
        let geometry = ContentStreamGeometry(pdf: pdf)
        let pageOfAfter = try #require(geometry.pages.firstIndex { page in page.texts.contains { $0.string.hasPrefix("After") } })
        let indexRows = rows(of: geometry.pages[geometry.pages.count - 1]).map(\.text)
        #expect(indexRows == ["Index", "M", "marked, \(pageOfAfter + 1)"])
    }

    @Test("Table of contents, page numbers and index converge, and every index page really holds the term")
    func convergesAndAgreesWithPoppler() throws {
        var sections: [String] = []
        let zetaSections: Set = [3, 17, 18, 19, 33]
        for number in 1 ... 40 {
            var body = "## Chapter \(number)\n\n"
            body += (1 ... 6).map { "Paragraph \($0) of chapter \(number) with ordinary filler words to take up room on the page." }
                .joined(separator: "\n\n")
            if zetaSections.contains(number) {
                body += "\n\nThe rare word ZETA appears here in chapter \(number)."
            }
            sections.append(body)
        }
        let markdown = "# Big Book\n\n" + sections.joined(separator: "\n\n")
        let options = PDFOptions(
            tableOfContents: .enabled,
            pageNumbers: PDFOptions.PageNumbers(isEnabled: true, firstPageNumber: 3),
            index: PDFOptions.Index(isEnabled: true, terms: ["zeta"]),
        )
        let pdf = try render(markdown, options)
        let pages = try pageTexts(pdf, name: "index-converges")
        let indexPage = pages.count - 1

        // Independent oracle: the pages (printed labels) whose Poppler text holds ZETA.
        let expected = pages.indices.filter { $0 != indexPage && pages[$0].contains("ZETA") }.map { $0 + 3 }
        // Several of the chapters share a page, so there are fewer pages than chapters.
        #expect(expected.count >= 3 && expected.count <= zetaSections.count)

        // Parse "zeta, a, b-c" from the index page.
        let line = try #require(
            pages[indexPage].components(separatedBy: "\n").first { $0.hasPrefix("zeta,") }
                ?? pages[indexPage].components(separatedBy: "\n").first { $0.contains("zeta") },
        )
        let references = line.replacingOccurrences(of: "zeta,", with: "").split(separator: ",")
        var listed: [Int] = []
        for reference in references {
            let parts = reference.trimmingCharacters(in: .whitespaces).split(separator: "-").compactMap { Int($0) }
            if parts.count == 2 {
                listed.append(contentsOf: parts[0] ... parts[1])
            } else if let single = parts.first {
                listed.append(single)
            }
        }
        #expect(listed == expected, "index lists \(listed), Poppler finds \(expected)")

        // The contents entry for the index carries the index page's printed label.
        let contents = pages[0] + pages[1]
        #expect(contents.contains("Index"))
        let geometry = ContentStreamGeometry(pdf: pdf)
        let indexRow = rows(of: geometry.pages[0]).first { $0.text.hasPrefix("Index") }
        #expect(indexRow?.text == "Index\(indexPage + 3)")
    }
}
