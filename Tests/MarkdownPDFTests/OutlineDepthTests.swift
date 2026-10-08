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
