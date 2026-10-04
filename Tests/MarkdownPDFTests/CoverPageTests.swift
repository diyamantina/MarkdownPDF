import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: the cover is physical page 1 and nothing else. The question each test asks
/// has an answer known without running the renderer's own page logic.
///
/// - Placement: a closed form. `scale = min(W / w, H / h)`, the image is centred, and
///   an image whose aspect ratio is within 0.1% of the page's fills it exactly.
/// - Numbering: the page after the cover is printed page `firstPageNumber`, so the
///   footer of physical page `p` reads `firstPageNumber + p - 2`. The physical page
///   of every heading is read back independently from Poppler's per-page text.
/// - Links: destinations and the outline name physical pages, never printed ones.
/// - Pixels: Poppler and MuPDF rasters of page 1 are compared with the image colours
///   and with white bars, computed from the same closed form.
@Suite("Cover page")
struct CoverPageTests {
    /// A solid RGB PNG, stored uncompressed so it builds quickly.
    private func solidPNG(width: Int, height: Int, color: [Int] = [20, 40, 160]) -> Data {
        var encoder = TestPNGEncoder(
            width: width,
            height: height,
            colorType: 2,
            bitDepth: 8,
            sample: { _, _, channel in color[channel] },
        )
        encoder.compression = .stored
        encoder.filtering = .none
        return encoder.encode()
    }

    private func cover(_ png: Data) -> PDFOptions.Cover {
        .enabled(image: .data(png))
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

    struct Placement: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// The matrix of the first `/Im1 Do` in the page content streams: `w 0 0 h x y cm`.
    private func coverPlacement(_ pdf: Data) throws -> Placement {
        let stream = try #require(PDFInspector(pdf).streams.first { $0.body.contains("/Im1 Do") })
        let number = #"(-?[0-9]+(?:\.[0-9]+)?)"#
        let regex = try Regex("\(number) 0 0 \(number) \(number) \(number) cm /Im1 Do")
        let match = try #require(stream.body.firstMatch(of: regex))
        let values = (1 ... 4).compactMap { match[$0].substring.flatMap { Double($0) } }
        try #require(values.count == 4)
        // Capture order is a, d, e, f of `a 0 0 d e f cm`.
        return Placement(x: values[2], y: values[3], width: values[0], height: values[1])
    }

    private func expectPlacement(
        _ actual: Placement,
        _ expected: Placement,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) {
        // The content stream writes numbers with 4 decimals at most.
        #expect(abs(actual.x - expected.x) < 0.001, "x \(actual.x) vs \(expected.x)", sourceLocation: sourceLocation)
        #expect(abs(actual.y - expected.y) < 0.001, "y \(actual.y) vs \(expected.y)", sourceLocation: sourceLocation)
        #expect(abs(actual.width - expected.width) < 0.001, "w \(actual.width) vs \(expected.width)", sourceLocation: sourceLocation)
        #expect(abs(actual.height - expected.height) < 0.001, "h \(actual.height) vs \(expected.height)", sourceLocation: sourceLocation)
    }

    private static let sections = (1 ... 4).map { "# Section \($0)\n\nBody of section \($0)." }
        .joined(separator: "\n\n<!-- pagebreak -->\n\n")

    // MARK: API

    @Test("The cover is off by default and equality is by value")
    func apiDefaults() {
        #expect(PDFOptions().cover == .disabled)
        #expect(PDFOptions().author == nil)
        #expect(!PDFOptions.Cover.disabled.isEnabled)
        let png = solidPNG(width: 2, height: 2)
        #expect(PDFOptions.Cover.enabled(image: .data(png)).isEnabled)
        #expect(PDFOptions.Cover.enabled(image: .data(png)) == .enabled(image: .data(png)))
        #expect(PDFOptions.Cover.enabled(image: .data(png)) != .enabled(image: .file("a.png")))
        #expect(PDFOptions.Cover.enabled(image: .file("a.png")) != .enabled(image: .file("b.png")))
    }

    // MARK: Placement

    @Test("An image of the page's own aspect ratio fills the page exactly")
    func exactAspectFillsPage() throws {
        let page = PDFOptions.PageSize(width: 100, height: 200)
        let options = PDFOptions(pageSize: page, cover: cover(solidPNG(width: 50, height: 100)))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "Body.")
        try expectPlacement(coverPlacement(pdf), Placement(x: 0, y: 0, width: 100, height: 200))
    }

    @Test("A 1 to 1.4142 image fills an A4 page: the 0.1% snap absorbs the rounded ratio")
    func a4RatioFillsPage() throws {
        // 500 x 707 is 1 : 1.414, 0.015% away from A4's 1 : 1.41421.
        let options = PDFOptions(cover: cover(solidPNG(width: 500, height: 707)))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "Body.")
        let a4 = PDFOptions.PageSize.a4
        try expectPlacement(coverPlacement(pdf), Placement(x: 0, y: 0, width: a4.width, height: a4.height))
    }

    @Test("A landscape image is fitted to the width and centred with equal bars above and below")
    func landscapeIsLetterboxed() throws {
        let a4 = PDFOptions.PageSize.a4
        let options = PDFOptions(cover: cover(solidPNG(width: 160, height: 90)))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "Body.")
        let height = a4.width * 90 / 160
        try expectPlacement(
            coverPlacement(pdf),
            Placement(x: 0, y: (a4.height - height) / 2, width: a4.width, height: height),
        )
    }

    @Test("A narrow image is fitted to the height and centred with equal bars left and right")
    func narrowIsPillarboxed() throws {
        let a4 = PDFOptions.PageSize.a4
        let options = PDFOptions(cover: cover(solidPNG(width: 10, height: 20)))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "Body.")
        let width = a4.height * 10 / 20
        try expectPlacement(
            coverPlacement(pdf),
            Placement(x: (a4.width - width) / 2, y: 0, width: width, height: a4.height),
        )
    }

    @Test("A small image is scaled up to the page: the fit has no native-size cap")
    func smallImageScalesUp() throws {
        let options = PDFOptions(pageSize: .init(width: 400, height: 400), cover: cover(solidPNG(width: 2, height: 1)))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "Body.")
        try expectPlacement(coverPlacement(pdf), Placement(x: 0, y: 100, width: 400, height: 200))
    }

    @Test("Placement ignores the margins and the image height cap")
    func marginsDoNotApply() throws {
        var options = PDFOptions(
            margins: .init(top: 90, right: 80, bottom: 70, left: 60),
            cover: cover(solidPNG(width: 50, height: 100)),
        )
        options.pageSize = .init(width: 100, height: 200)
        options.imageMaxHeightFraction = 0.1
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "Body.")
        try expectPlacement(coverPlacement(pdf), Placement(x: 0, y: 0, width: 100, height: 200))
    }

    // MARK: Page structure and numbering

    @Test("Page 1 carries the image and no text, page 2 starts the body, and the count is body plus one")
    func coverIsPageOneAlone() throws {
        let options = PDFOptions(pageNumbers: .enabled, cover: cover(solidPNG(width: 500, height: 707)))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: Self.sections)
        let geometry = ContentStreamGeometry(pdf: pdf)
        try #require(geometry.pages.count == 5, "cover plus four sections")
        #expect(geometry.pages[0].texts.isEmpty, "no footer or content on the cover")
        #expect(geometry.pages[0].rects == [ContentStreamGeometry.Rect(x: 0, y: 0, width: 595.28, height: 841.89)])

        let texts = try pageTexts(pdf, name: "cover-page-one")
        #expect(texts.count == 5)
        #expect(texts[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(texts[1].contains("Section 1"))
    }

    @Test("The first page after the cover prints page 1, and Page N of M excludes the cover")
    func footersExcludeCover() throws {
        let options = PDFOptions(
            pageNumbers: PDFOptions.PageNumbers(isEnabled: true, format: .ofTotal),
            cover: cover(solidPNG(width: 500, height: 707)),
        )
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: Self.sections)
        let geometry = ContentStreamGeometry(pdf: pdf)
        try #require(geometry.pages.count == 5)
        for physical in 2 ... 5 {
            let footer = try #require(geometry.pages[physical - 1].texts.first { $0.y < 54 })
            #expect(footer.string == "Page \(physical - 1) of 4")
        }
        let texts = try pageTexts(pdf, name: "cover-footers")
        #expect(texts[1].contains("Page 1 of 4"))
        #expect(texts[4].contains("Page 4 of 4"))
    }

    @Test("firstPageNumber and roman numbering start after the cover")
    func customFirstNumberAndRoman() throws {
        let image = solidPNG(width: 500, height: 707)
        let start = PDFOptions(
            pageNumbers: PDFOptions.PageNumbers(isEnabled: true, firstPageNumber: 7),
            cover: cover(image),
        )
        let startGeometry = try ContentStreamGeometry(pdf: MarkdownPDFRenderer(options: start).render(markdown: Self.sections))
        #expect(startGeometry.pages.dropFirst().compactMap { $0.texts.first { $0.y < 54 }?.string } == ["7", "8", "9", "10"])

        let roman = PDFOptions(
            pageNumbers: PDFOptions.PageNumbers(isEnabled: true, format: .romanLowercase),
            cover: cover(image),
        )
        let romanGeometry = try ContentStreamGeometry(pdf: MarkdownPDFRenderer(options: roman).render(markdown: Self.sections))
        #expect(romanGeometry.pages.dropFirst().compactMap { $0.texts.first { $0.y < 54 }?.string } == ["i", "ii", "iii", "iv"])
    }

    @Test("skipsFirstPage applies to the first page after the cover, which still counts as page 1")
    func skipFirstPageAfterCover() throws {
        let options = PDFOptions(
            pageNumbers: PDFOptions.PageNumbers(isEnabled: true, skipsFirstPage: true),
            cover: cover(solidPNG(width: 500, height: 707)),
        )
        let geometry = try ContentStreamGeometry(pdf: MarkdownPDFRenderer(options: options).render(markdown: Self.sections))
        let footers = geometry.pages.map { $0.texts.first { $0.y < 54 }?.string }
        #expect(footers == [nil, nil, "2", "3", "4"])
    }

    @Test("Without page numbers the cover still takes physical page 1 and nothing is drawn on it")
    func noPageNumbers() throws {
        let options = PDFOptions(cover: cover(solidPNG(width: 500, height: 707)))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: Self.sections)
        let geometry = ContentStreamGeometry(pdf: pdf)
        #expect(geometry.pages.count == 5)
        #expect(geometry.pages.allSatisfy { page in !page.texts.contains { $0.y < 54 } })
    }

    @Test("An empty document still gets its cover and one body page")
    func emptyDocument() throws {
        let options = PDFOptions(cover: cover(solidPNG(width: 500, height: 707)))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "")
        #expect(PDFInspector(pdf).pageCount == 2)
        try expectPlacement(coverPlacement(pdf), Placement(x: 0, y: 0, width: 595.28, height: 841.89))
    }

    // MARK: Table of contents, index, links

    /// The rows of a body page above the footer band: fragments sharing a baseline.
    private func rows(of page: ContentStreamGeometry.Page) -> [(y: Double, fragments: [ContentStreamGeometry.Text])] {
        var byBaseline: [Double: [ContentStreamGeometry.Text]] = [:]
        for text in page.texts where text.y > 54 {
            byBaseline[text.y, default: []].append(text)
        }
        return byBaseline.keys.sorted(by: >).map { y in
            (y, (byBaseline[y] ?? []).sorted { $0.x < $1.x })
        }
    }

    /// The physical page (1 based) each "Section k" heading is on, read from Poppler.
    /// A contents row: the title the fragments to the left spell, and the number at the
    /// right edge.
    private func contentsRow(
        _ page: ContentStreamGeometry.Page,
        title: String,
    ) -> (title: String, printed: Int)? {
        for row in rows(of: page) where row.fragments.count > 1 {
            let spelled = row.fragments.dropLast().map(\.string).joined().replacingOccurrences(of: "  ", with: " ")
            if spelled == title, let printed = row.fragments.last.flatMap({ Int($0.string) }) {
                return (spelled, printed)
            }
        }
        return nil
    }

    private func physicalPages(_ pdf: Data, name: String) throws -> [Int: Int] {
        var result: [Int: Int] = [:]
        for (index, text) in try pageTexts(pdf, name: name).enumerated() {
            for section in 1 ... 4 where text.contains("Body of section \(section).") {
                result[section] = index + 1
            }
        }
        return result
    }

    @Test("The table of contents prints printed numbers, and its links and the outline use physical pages")
    func tableOfContentsAndLinks() throws {
        let options = PDFOptions(
            tableOfContents: .init(isEnabled: true, title: "Contents"),
            pageNumbers: .enabled,
            cover: cover(solidPNG(width: 500, height: 707)),
        )
        let markdown = "Intro paragraph.\n\n" + Self.sections
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
        let geometry = ContentStreamGeometry(pdf: pdf)
        let physical = try physicalPages(pdf, name: "cover-toc")
        try #require(physical.count == 4)

        // The contents start on physical page 2, directly after the cover.
        let tocPage = geometry.pages[1]
        #expect(tocPage.texts.contains { $0.string == "Contents" })
        for section in 1 ... 4 {
            let row = try #require(contentsRow(tocPage, title: "Section \(section)"), "no contents row for section \(section)")
            #expect(row.printed == (physical[section] ?? 0) - 1, "section \(section) is on physical page \(physical[section] ?? 0)")
        }

        // Named destinations (what the links and outline resolve to) are physical.
        let destinations = PDFInspector(pdf).namedDestinationPages
        for section in 1 ... 4 {
            #expect(destinations["section-\(section)"] == physical[section])
        }
        #expect(destinations["mdpdf-cover"] == 1)
    }

    @Test("Without page numbers the table of contents prints physical numbers")
    func tableOfContentsWithoutPageNumbers() throws {
        let options = PDFOptions(
            tableOfContents: .init(isEnabled: true, title: "Contents"),
            cover: cover(solidPNG(width: 500, height: 707)),
        )
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "Intro.\n\n" + Self.sections)
        let geometry = ContentStreamGeometry(pdf: pdf)
        let physical = try physicalPages(pdf, name: "cover-toc-plain")
        for section in 1 ... 4 {
            let row = try #require(contentsRow(geometry.pages[1], title: "Section \(section)"))
            #expect(row.printed == physical[section])
        }
    }

    @Test("The cover is not a table of contents entry but is the first outline item")
    func coverIsOutlineOnly() throws {
        let options = PDFOptions(
            tableOfContents: .init(isEnabled: true, title: "Contents"),
            pageNumbers: .enabled,
            cover: cover(solidPNG(width: 500, height: 707)),
        )
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "Intro.\n\n" + Self.sections)
        let geometry = ContentStreamGeometry(pdf: pdf)
        #expect(!geometry.pages[1].texts.contains { $0.string == "Cover" })

        let text = PDFInspector(pdf).text
        let cover = try #require(text.range(of: "/Title (Cover)"))
        let first = try #require(text.range(of: "/Title (Section 1)"))
        #expect(cover.lowerBound < first.lowerBound)
        // The outline is a flat list of level-one headings: a later level-two heading
        // must not become a child of the cover.
        let nested = try MarkdownPDFRenderer(options: options).render(markdown: "## Subsection\n\nText.\n\n# Chapter")
        let nestedText = PDFInspector(nested).text
        #expect(nestedText.contains("/Title (Cover)"))
        let coverObject = try #require(PDFInspector(nested).indirectObjects.first { $0.content.contains("/Title (Cover)") })
        #expect(!coverObject.content.contains("/First "), "the cover has no children")
    }

    @Test("Index references print printed numbers and link to physical pages")
    func indexReferences() throws {
        let options = PDFOptions(
            pageNumbers: .enabled,
            index: .enabled,
            cover: cover(solidPNG(width: 500, height: 707)),
        )
        let markdown = Self.sections.replacingOccurrences(of: "Body of section 3.", with: "Body of section 3. {{index: zebra}}")
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
        let physical = try physicalPages(pdf, name: "cover-index")
        let page = try #require(physical[3])

        let geometry = ContentStreamGeometry(pdf: pdf)
        let indexRows = try rows(of: #require(geometry.pages.last)).map { $0.fragments.map(\.string).joined() }
        #expect(indexRows.contains("zebra, \(page - 1)"), "rows: \(indexRows)")
        #expect(PDFInspector(pdf).namedDestinationPages["mdpdf-page-\(page)"] == page)
    }

    @Test("Merged sources keep the cover first and number from the page after it")
    func mergedSources() throws {
        let options = PDFOptions(
            tableOfContents: .init(isEnabled: true, title: "Contents"),
            pageNumbers: PDFOptions.PageNumbers(isEnabled: true, format: .ofTotal),
            cover: cover(solidPNG(width: 500, height: 707)),
        )
        let sources = (1 ... 3).map { MarkdownSource(markdown: "# Chapter \($0)\n\nText of chapter \($0).", name: "c\($0).md") }
        let pdf = try MarkdownPDFRenderer(options: options).render(sources: sources)
        let texts = try pageTexts(pdf, name: "cover-merge")
        // Cover, contents page, then one page per source.
        try #require(texts.count >= 4)
        #expect(texts[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let geometry = ContentStreamGeometry(pdf: pdf)
        let last = geometry.pages.count - 1
        for physical in 2 ... geometry.pages.count {
            let footer = try #require(geometry.pages[physical - 1].texts.first { $0.y < 54 })
            #expect(footer.string == "Page \(physical - 1) of \(last)")
        }
        let destinations = PDFInspector(pdf).namedDestinationPages
        for chapter in 1 ... 3 {
            let page = texts.firstIndex { $0.contains("Text of chapter \(chapter).") }
            #expect(destinations["chapter-\(chapter)"] == page.map { $0 + 1 })
        }
    }

    // MARK: Images

    @Test("A cover image is decoded like a body image: an RGBA PNG gets a soft mask")
    func rgbaCoverHasSoftMask() throws {
        let rgba = TestPNGEncoder(
            width: 4,
            height: 4,
            colorType: 6,
            bitDepth: 8,
            sample: { _, _, channel in [200, 30, 40, 128][channel] },
        ).encode()
        let pdf = try MarkdownPDFRenderer(options: PDFOptions(cover: cover(rgba))).render(markdown: "Body.")
        let objects = PDFImageObjects(pdf: pdf)
        let image = try #require(objects.images.first { $0.softMaskObjectNumber != nil })
        #expect(try Array(image.decodedSamples().prefix(3)) == [200, 30, 40])
    }

    @Test("A JPEG cover is passed through as DCT data")
    func jpegCover() throws {
        // A 1 x 1 baseline JPEG, enough for the header the placement reads.
        let jpeg = Data([
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
            0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x03, 0x00, 0x02, 0x01, 0x01, 0x11, 0x00,
            0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x00, 0xFF, 0xD9,
        ])
        let pdf = try MarkdownPDFRenderer(options: PDFOptions(pageSize: .init(width: 200, height: 300), cover: cover(jpeg)))
            .render(markdown: "Body.")
        #expect(PDFInspector(pdf).text.contains("/Filter /DCTDecode"))
        // 2 wide, 3 high: the page's own 2 : 3.
        try expectPlacement(coverPlacement(pdf), Placement(x: 0, y: 0, width: 200, height: 300))
    }

    @Test("A file cover resolves against its own base URL")
    func fileCover() throws {
        let directory = try PDFValidation.temporaryDirectory()
        try solidPNG(width: 500, height: 707).write(to: directory.appendingPathComponent("front.png"))
        let options = PDFOptions(cover: .enabled(image: .file("front.png", relativeTo: directory)))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "Body.")
        try expectPlacement(coverPlacement(pdf), Placement(x: 0, y: 0, width: 595.28, height: 841.89))
    }

    @Test("A body image after the cover does not reuse the cover's resource name")
    func bodyImagesStayDistinct() throws {
        let directory = try PDFValidation.temporaryDirectory()
        // RGBA, so both images decode to plain samples.
        let body = TestPNGEncoder(width: 4, height: 4, colorType: 6, bitDepth: 8, sample: { _, _, channel in [200, 10, 10, 255][channel] })
        try body.encode().write(to: directory.appendingPathComponent("fig.png"))
        let coverImage = TestPNGEncoder(width: 5, height: 7, colorType: 6, bitDepth: 8, sample: { _, _, channel in [10, 10, 200, 255][channel] })
        let options = PDFOptions(cover: cover(coverImage.encode()))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "![fig](fig.png)", assetsBaseURL: directory)
        let images = PDFImageObjects(pdf: pdf).images
        try #require(images.count == 2)
        let colours = try images.map { try Array($0.decodedSamples().prefix(3)) }
        #expect(colours.contains([10, 10, 200]) && colours.contains([200, 10, 10]))
    }

    // MARK: Errors

    @Test("A missing cover file throws a typed error naming the path")
    func missingFile() throws {
        let options = PDFOptions(cover: .enabled(image: .file("no-such-cover.png", relativeTo: URL(fileURLWithPath: "/nonexistent-dir"))))
        #expect(throws: MarkdownPDFError.coverImageUnreadable("no-such-cover.png")) {
            try MarkdownPDFRenderer(options: options).render(markdown: "Body.")
        }
    }

    @Test("Undecodable cover data throws instead of dropping the cover", arguments: [
        Data(),
        Data("not an image".utf8),
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]),
    ])
    func undecodable(data: Data) throws {
        let options = PDFOptions(cover: cover(data))
        #expect(throws: MarkdownPDFError.coverImageUnsupported("cover image data")) {
            try MarkdownPDFRenderer(options: options).render(markdown: "Body.")
        }
        let toc = PDFOptions(tableOfContents: .enabled, index: .enabled, cover: cover(data))
        #expect(throws: MarkdownPDFError.coverImageUnsupported("cover image data")) {
            try MarkdownPDFRenderer(options: toc).render(markdown: "# A\n\nB")
        }
    }

    @Test("The cover errors describe the failure and a recovery")
    func errorText() {
        let errors: [MarkdownPDFError] = [.coverImageUnreadable("c.png"), .coverImageUnsupported("c.png")]
        for error in errors {
            #expect(error.errorDescription?.contains("c.png") == true)
            #expect(error.recoverySuggestion?.isEmpty == false)
        }
    }

    // MARK: Metadata, tagging, conformance

    @Test("The author reaches the Info dictionary and the XMP packet, escaped")
    func authorMetadata() throws {
        let options = PDFOptions(title: "T (1)", author: "Mihaela <M> & (Co)", cover: cover(solidPNG(width: 500, height: 707)))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "Body.")
        let text = PDFInspector(pdf).text
        #expect(text.contains("/Author (Mihaela <M> & \\(Co\\))"))
        #expect(text.contains("<dc:creator><rdf:Seq><rdf:li>Mihaela &lt;M&gt; &amp; (Co)</rdf:li></rdf:Seq></dc:creator>"))

        let info = try PDFValidation.parsedInfo(from: PDFValidation.pdfinfo(data: pdf, name: "cover-author"))
        #expect(info["Author"] == "Mihaela <M> & (Co)")
        #expect(info["Title"] == "T (1)")
        #expect(info["Pages"] == "2")
    }

    @Test("The author is metadata on its own, with or without a cover or a title")
    func authorWithoutCover() throws {
        let pdf = try MarkdownPDFRenderer(options: PDFOptions(author: "A. Writer")).render(markdown: "Body.")
        let info = try PDFValidation.parsedInfo(from: PDFValidation.pdfinfo(data: pdf, name: "author-only"))
        #expect(info["Author"] == "A. Writer")
        #expect(info["Title"] == nil)

        for blank in ["", "   ", "\n"] {
            let none = try MarkdownPDFRenderer(options: PDFOptions(author: blank)).render(markdown: "Body.")
            #expect(!PDFInspector(none).text.contains("/Author"))
        }
    }

    @Test("Tagged output wraps the cover in a Figure whose alt text names the title and author")
    func taggedCover() throws {
        let options = PDFOptions(
            title: "The Book",
            taggedPDF: .init(isEnabled: true),
            author: "A. Writer",
            cover: cover(solidPNG(width: 500, height: 707)),
        )
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "# Heading\n\nBody.")
        let text = PDFInspector(pdf).text
        #expect(text.contains("/S /Figure"))
        #expect(text.contains("/Alt (Cover of The Book by A. Writer)"))
        let inspector = PDFInspector(pdf)
        #expect(inspector.canonicalStructureIssues().isEmpty, "\(inspector.canonicalStructureReport())")
    }

    @Test("Alt text falls back when the title or author is missing")
    func coverAltFallbacks() throws {
        func alt(title: String?, author: String?) throws -> String {
            let options = PDFOptions(
                title: title,
                taggedPDF: .init(isEnabled: true),
                author: author,
                cover: cover(solidPNG(width: 500, height: 707)),
            )
            let text = try PDFInspector(MarkdownPDFRenderer(options: options).render(markdown: "Body.")).text
            return try #require(text.firstMatch(of: /\/Alt \(([^)]*)\)/)).output.1.description
        }
        #expect(try alt(title: "The Book", author: nil) == "Cover of The Book")
        #expect(try alt(title: nil, author: "A. Writer") == "Cover by A. Writer")
        #expect(try alt(title: nil, author: nil) == "Cover")
    }

    @Test("PDF/UA-1 and PDF/A-2a validate with a cover, page numbers and an author")
    func conformance() throws {
        // No table of contents: its links already fail PDF/UA-1 without a cover, which
        // is separate from this feature.
        let options = PDFOptions(
            embeddedFonts: .dejaVu,
            title: "The Book",
            conformance: .pdfUA1AndPDFA2A,
            pageNumbers: .enabled,
            author: "A. Writer",
            cover: cover(solidPNG(width: 500, height: 707)),
        )
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: Self.sections)
        for flavour in ["ua1", "2a"] {
            let result = try PDFValidation.veraPDF(data: pdf, name: "cover-\(flavour)", flavour: flavour)
            #expect(result.exitCode == 0, "veraPDF \(flavour):\n\(result.output)")
            #expect(result.output.contains("\"compliant\" : true"), "veraPDF \(flavour) did not report compliance")
        }
    }

    // MARK: Compatibility

    @Test("Documents that do not enable the cover are unchanged")
    func disabledIsUnchanged() throws {
        let plain = try MarkdownPDFRenderer().render(markdown: Self.sections)
        let explicit = try MarkdownPDFRenderer(options: PDFOptions(author: nil, cover: .disabled)).render(markdown: Self.sections)
        #expect(plain == explicit)
        #expect(!PDFInspector(plain).text.contains("mdpdf-cover"))
        #expect(!PDFInspector(plain).text.contains("/Author"))
    }

    @Test("Compression, tagging and a table of contents compose with the cover")
    func composes() throws {
        let options = PDFOptions(
            tableOfContents: .enabled,
            streamCompression: .init(isEnabled: true),
            taggedPDF: .init(isEnabled: true),
            pageNumbers: .enabled,
            index: .enabled,
            cover: cover(solidPNG(width: 500, height: 707)),
        )
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: Self.sections)
        let qpdf = try PDFValidation.qpdfCheck(data: pdf, name: "cover-composed")
        #expect(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        let stext = try PDFValidation.mutoolStructuredText(data: pdf, name: "cover-composed")
        #expect(stext.exitCode == 0, "mutool stext failed:\n\(stext.output)")
        let info = try PDFValidation.parsedInfo(from: PDFValidation.pdfinfo(data: pdf, name: "cover-composed"))
        // The contents follow the first heading, so: cover plus four sections.
        #expect(info["Pages"] == "5")
    }

    // MARK: Raster witnesses

    private func rasters(_ pdf: Data, name: String, resolution: Int) throws -> [(tool: String, image: PNMImage)] {
        let url = try PDFValidation.temporaryPDF(name: name, data: pdf)
        let poppler = try PDFValidation.pdftoppmPNM(url: url, page: 1, resolution: resolution)
        let mupdf = try PDFValidation.mutoolPNM(url: url, page: 1, resolution: resolution, rgb: true)
        try #require(poppler.result.exitCode == 0, "pdftoppm failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool failed:\n\(mupdf.result.output)")
        return try [
            ("pdftoppm", PNMImage(data: Data(contentsOf: poppler.pnmURL))),
            ("mutool", PNMImage(data: Data(contentsOf: mupdf.pnmURL))),
        ]
    }

    private func pixel(_ image: PNMImage, _ x: Int, _ y: Int) -> [Int] {
        let offset = (y * image.width + x) * image.samplesPerPixel
        if image.samplesPerPixel == 1 {
            return [Int(image.samples[offset])]
        }
        return (0 ..< 3).map { Int(image.samples[offset + $0]) }
    }

    @Test("Rasters of an exact-aspect cover are ink to every edge, from both rasterizers")
    func exactRasterFillsEveryPixel() throws {
        let color = [20, 40, 160]
        let options = PDFOptions(pageSize: .init(width: 100, height: 200), cover: cover(solidPNG(width: 50, height: 100, color: color)))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "Body.")
        for (tool, image) in try rasters(pdf, name: "cover-raster-exact", resolution: 72) {
            #expect(image.width == 100 && image.height == 200, "\(tool) raster \(image.width) x \(image.height)")
            for (x, y) in [(0, 0), (99, 0), (0, 199), (99, 199), (50, 100), (0, 100), (99, 100), (50, 0), (50, 199)] {
                let actual = pixel(image, x, y)
                for channel in 0 ..< 3 {
                    #expect(abs(actual[channel] - color[channel]) <= 3, "\(tool) (\(x), \(y)) channel \(channel): \(actual)")
                }
            }
        }
    }

    @Test("Rasters of a letterboxed cover have white bars of the documented height")
    func letterboxRaster() throws {
        let color = [20, 40, 160]
        // 200 x 200 page, 2 : 1 image: 200 x 100 drawn, 50 point bars above and below.
        let options = PDFOptions(pageSize: .init(width: 200, height: 200), cover: cover(solidPNG(width: 40, height: 20, color: color)))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "Body.")
        for (tool, image) in try rasters(pdf, name: "cover-raster-letterbox", resolution: 72) {
            #expect(image.width == 200 && image.height == 200)
            for (x, y) in [(0, 5), (199, 5), (100, 45), (0, 154), (100, 195)] {
                #expect(pixel(image, x, y).allSatisfy { $0 >= 252 }, "\(tool) bar pixel (\(x), \(y)): \(pixel(image, x, y))")
            }
            for (x, y) in [(0, 55), (199, 55), (100, 100), (0, 144), (199, 144)] {
                let actual = pixel(image, x, y)
                for channel in 0 ..< 3 {
                    #expect(abs(actual[channel] - color[channel]) <= 3, "\(tool) image pixel (\(x), \(y)): \(actual)")
                }
            }
        }
    }

    @Test("Rasters composite an RGBA cover over white")
    func alphaRaster() throws {
        let alpha = 128
        let rgba = TestPNGEncoder(
            width: 8,
            height: 8,
            colorType: 6,
            bitDepth: 8,
            sample: { _, _, channel in [200, 30, 40, alpha][channel] },
        ).encode()
        let options = PDFOptions(pageSize: .init(width: 80, height: 80), cover: cover(rgba))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "Body.")
        let source = [200.0, 30, 40]
        for (tool, image) in try rasters(pdf, name: "cover-raster-alpha", resolution: 72) {
            let actual = pixel(image, 40, 40)
            for channel in 0 ..< 3 {
                let expected = source[channel] * Double(alpha) / 255 + 255 * (1 - Double(alpha) / 255)
                #expect(abs(Double(actual[channel]) - expected) <= 3, "\(tool) channel \(channel): \(actual[channel]) vs \(expected)")
            }
        }
    }

    @Test("Poppler and MuPDF agree on every page of a cover document")
    func allPageParity() throws {
        let options = PDFOptions(
            tableOfContents: .enabled,
            pageNumbers: PDFOptions.PageNumbers(isEnabled: true, format: .ofTotal),
            index: .enabled,
            cover: cover(solidPNG(width: 500, height: 707)),
        )
        let markdown = "Intro.\n\n" + Self.sections.replacingOccurrences(of: "Body of section 2.", with: "Body of section 2. {{index: term}}")
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
        let url = try PDFValidation.temporaryPDF(name: "cover-parity", data: pdf)
        let pageCount = PDFInspector(pdf).pageCount
        let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount, resolution: 36)
        let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount, resolution: 36)
        try #require(poppler.result.exitCode == 0 && mupdf.result.exitCode == 0)
        for page in 0 ..< pageCount {
            let first = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page])).inkMetrics()
            let second = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page])).inkMetrics()
            #expect(first.nonWhitePixelCount > 0 && second.nonWhitePixelCount > 0, "page \(page + 1) is blank")
            if page == 0 {
                // The cover is ink everywhere.
                let box = try #require(first.box)
                #expect(box.left == 0 && box.top == 0)
            }
        }
        let texts = try pageTexts(pdf, name: "cover-parity-text")
        #expect(texts.count == pageCount)
    }
}
