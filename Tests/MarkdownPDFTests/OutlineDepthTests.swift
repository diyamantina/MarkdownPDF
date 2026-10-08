import Foundation
@testable import MarkdownPDF
import Testing

@Suite("Outline depth")
struct OutlineDepthTests {
    private static let markdown = """
    # Part

    ## Slide

    ### Line

    #### Deep
    """

    /// The titles of the outline entries, in order, read from the `/Title` strings of the outline items.
    private func outlineTitles(maxLevel: Int?) throws -> [String] {
        var options = PDFOptions()
        if let maxLevel {
            options.outlineMaxHeadingLevel = maxLevel
        }
        let data = try MarkdownPDFRenderer(options: options).render(markdown: Self.markdown)
        let text = String(decoding: data, as: UTF8.self)
        return text.matches(of: /\/Title \(([^)]*)\)/).map { String($0.output.1) }
    }

    @Test("By default every heading is in the outline")
    func defaultKeepsEveryHeading() throws {
        #expect(try outlineTitles(maxLevel: nil) == ["Part", "Slide", "Line", "Deep"])
    }

    @Test("A depth of two keeps deeper headings out of the outline")
    func depthTwoStopsAtLevelTwo() throws {
        #expect(try outlineTitles(maxLevel: 2) == ["Part", "Slide"])
    }

    @Test("A depth of one keeps only the top level")
    func depthOneKeepsTheTopLevel() throws {
        #expect(try outlineTitles(maxLevel: 1) == ["Part"])
    }

    @Test("A depth outside 1 to 6 is clamped")
    func depthIsClamped() throws {
        #expect(try outlineTitles(maxLevel: 0) == ["Part"])
        #expect(try outlineTitles(maxLevel: 99) == ["Part", "Slide", "Line", "Deep"])
    }

    @Test("A heading left out of the outline is still a destination links can reach")
    func leftOutHeadingStaysADestination() throws {
        var options = PDFOptions()
        options.outlineMaxHeadingLevel = 2
        let data = try MarkdownPDFRenderer(options: options).render(markdown: Self.markdown)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("(line)"))
    }
}

@Suite("Heading destination position")
struct HeadingDestinationPositionTests {
    private static let pageHeight = 540.0
    /// A heading with text above it, so it is not at the top of the page.
    private static let markdown = """
    A line above the heading.

    # Slide
    """

    /// The `y` of every `/XYZ` destination written to the PDF.
    private func destinationHeights(atPageTop: Bool?) throws -> [Double] {
        var options = PDFOptions(
            pageSize: PDFOptions.PageSize(width: 960, height: Self.pageHeight),
            margins: PDFOptions.Margins(top: 80, right: 72, bottom: 30, left: 72),
        )
        if let atPageTop {
            options.headingDestinationsAtPageTop = atPageTop
        }
        let data = try MarkdownPDFRenderer(options: options).render(markdown: Self.markdown)
        let text = String(decoding: data, as: UTF8.self)
        return text.matches(of: /\/XYZ ([0-9.]+) ([0-9.]+) null/).compactMap { Double($0.output.2) }
    }

    @Test("By default the destination is the heading, below the top of the page")
    func defaultIsTheHeading() throws {
        let heights = try destinationHeights(atPageTop: nil)
        #expect(!heights.isEmpty)
        #expect(heights.allSatisfy { $0 < Self.pageHeight })
    }

    @Test("At the page top the destination is the top of the page")
    func pageTopIsTheTop() throws {
        let heights = try destinationHeights(atPageTop: true)
        #expect(!heights.isEmpty)
        #expect(heights.allSatisfy { $0 == Self.pageHeight })
    }
}

@Suite("Outline options together")
struct OutlineOptionsTogetherTests {
    private static let pageHeight = 540.0

    private static func options(depth: Int? = nil, atPageTop: Bool? = nil) -> PDFOptions {
        var options = PDFOptions(
            pageSize: PDFOptions.PageSize(width: 960, height: pageHeight),
            margins: PDFOptions.Margins(top: 80, right: 72, bottom: 30, left: 72),
        )
        if let depth {
            options.outlineMaxHeadingLevel = depth
        }
        if let atPageTop {
            options.headingDestinationsAtPageTop = atPageTop
        }
        return options
    }

    /// Two slides on two pages, as a deck is written: a part, a slide and a shown line on the first, a slide and a line on the second.
    private static let deck = """
    # Part

    ## Slide A

    ### A line

    <!-- pagebreak -->

    ## Slide B

    ### Another line
    """

    private func text(_ markdown: String, _ options: PDFOptions) throws -> String {
        String(decoding: try MarkdownPDFRenderer(options: options).render(markdown: markdown), as: UTF8.self)
    }

    private func titles(in text: String) -> [String] {
        text.matches(of: /\/Title \(([^)]*)\)/).map { String($0.output.1) }
    }

    private func destinationHeights(in text: String) -> [Double] {
        text.matches(of: /\/XYZ [0-9.]+ ([0-9.]+) null/).compactMap { Double($0.output.1) }
    }

    @Test("the defaults written out give the same bytes as no options at all")
    func defaultsAreByteIdentical() throws {
        let implicit = try MarkdownPDFRenderer(options: Self.options()).render(markdown: Self.deck)
        let explicit = try MarkdownPDFRenderer(options: Self.options(
            depth: PDFOptions.defaultOutlineMaxHeadingLevel,
            atPageTop: false,
        )).render(markdown: Self.deck)
        #expect(implicit == explicit)
    }

    @Test("the options are set by the initializer and make a PDFOptions that differs from the default")
    func initializerSetsThem() {
        let options = PDFOptions(outlineMaxHeadingLevel: 2, headingDestinationsAtPageTop: true)
        #expect(options.outlineMaxHeadingLevel == 2)
        #expect(options.headingDestinationsAtPageTop)
        #expect(options != PDFOptions())
        #expect(PDFOptions().outlineMaxHeadingLevel == PDFOptions.defaultOutlineMaxHeadingLevel)
        #expect(!PDFOptions().headingDestinationsAtPageTop)
    }

    @Test("a deck with the outline stopped at level two lists the part and the slides, and leaves the shown lines out")
    func deckOutline() throws {
        let output = try text(Self.deck, Self.options(depth: 2))
        #expect(titles(in: output) == ["Part", "Slide A", "Slide B"])
        #expect(try titles(in: text(Self.deck, Self.options())) == ["Part", "Slide A", "A line", "Slide B", "Another line"])
    }

    @Test("with destinations at the page top every destination of a two page deck is the top of its page, and without it they are not")
    func destinationsOnEveryPage() throws {
        let top = destinationHeights(in: try text(Self.deck, Self.options(atPageTop: true)))
        #expect(top.count >= 5)
        #expect(top.allSatisfy { $0 == Self.pageHeight })
        let heading = destinationHeights(in: try text(Self.deck, Self.options(atPageTop: false)))
        #expect(heading.contains { $0 < Self.pageHeight }, "negative control: a heading below the top of the page is a lower destination")
    }

    @Test("a heading left out of the outline is still named in the destinations, so a link to it can resolve")
    func leftOutHeadingIsReachable() throws {
        let markdown = "[go](#a-line)\n\n# Part\n\n### A line"
        let output = try text(markdown, Self.options(depth: 1))
        #expect(titles(in: output) == ["Part"])
        #expect(output.contains("(a-line)"))
        #expect(output.contains("/Subtype /Link"))
    }

    @Test("a deck with both options is outlined by part and slide and points every entry at the top of its page")
    func theDeckCase() throws {
        let output = try text(Self.deck, Self.options(depth: 2, atPageTop: true))
        #expect(titles(in: output) == ["Part", "Slide A", "Slide B"])
        #expect(destinationHeights(in: output).allSatisfy { $0 == Self.pageHeight })
    }
}
