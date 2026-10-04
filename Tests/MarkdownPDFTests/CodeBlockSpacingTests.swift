import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: the distance from a code box's bottom edge to the top of the next
/// block's first line box is the visible gap that sits above the box (the
/// previous paragraph's trailing spacing plus its line height, less the
/// descender), and the box never overlaps the next block. Measured from the
/// generated content stream geometry.
@Suite("Code block spacing")
struct CodeBlockSpacingTests {
    private static let size = 11.0
    private static let tolerance = 0.002

    /// 6 pt paragraph spacing + 13.64 pt line height - 2.75 pt descender, derived
    /// from the default theme (`6/11` spacing, `1.24` line height, 11 pt body).
    private static let standardGap = 6.0 + 11.0 * 1.24 - 11.0 * 0.25

    private func geometry(_ markdown: String, options: PDFOptions = PDFOptions()) throws -> ContentStreamGeometry {
        try ContentStreamGeometry(pdf: MarkdownPDFRenderer(options: options).render(markdown: markdown))
    }

    private func codeBoxes(_ page: ContentStreamGeometry.Page) -> [ContentStreamGeometry.Rect] {
        page.rects.filter { abs($0.width - 487.28) < 0.01 && $0.height < 800 }
    }

    @Test("Gap after the box equals the gap before it, for a paragraph")
    func paragraphAfterBoxMatchesGapAbove() throws {
        let geometry = try geometry("Intro.\n\n```\nbox\n```\n\nNext.\n")
        let page = try #require(geometry.pages.first)
        let box = try #require(codeBoxes(page).first)
        let intro = try #require(page.texts.first { $0.string.hasPrefix("Intro") })
        let next = try #require(page.texts.first { $0.string.hasPrefix("Next") })

        let before = intro.bottom - box.top
        let after = box.bottom - next.top
        #expect(abs(before - Self.standardGap) < Self.tolerance, "gap above was \(before)")
        #expect(abs(after - before) < Self.tolerance, "gap below \(after) differs from above \(before)")
    }

    @Test(
        "The box never overlaps or touches the next block",
        arguments: [
            ("list", "- item\n"),
            ("ordered list", "1. item\n"),
            ("heading 1", "# Title\n"),
            ("heading 3", "### Title\n"),
            ("table", "| a | b |\n|---|---|\n| 1 | 2 |\n"),
            ("code block", "```\nsecond\n```\n"),
            ("block quote", "> quoted\n"),
        ],
    )
    func nextBlockClearsTheBox(name: String, following: String) throws {
        let geometry = try geometry("Intro.\n\n```\nbox\n```\n\n\(following)")
        let page = try #require(geometry.pages.first)
        let boxes = codeBoxes(page)
        let box = try #require(boxes.max { $0.top < $1.top })

        let following = page.texts.filter { $0.top < box.bottom + 40 && $0.string != "box" && !$0.string.hasPrefix("Intro") }
        let nextTexts = following.filter { $0.y < box.bottom }
        let nextTop = nextTexts.map(\.top).max()
        let nextRectTop = page.rects.filter { $0.top < box.bottom + 0.001 && $0 != box }.map(\.top).max()
        let top = try #require([nextTop, nextRectTop].compactMap(\.self).max(), "no block after the box for \(name)")

        #expect(box.bottom - top >= Self.standardGap - Self.tolerance, "\(name): clearance \(box.bottom - top)")
    }

    @Test("An empty code block keeps a positive box and the same gap")
    func emptyCodeBlock() throws {
        let geometry = try geometry("Intro.\n\n```\n```\n\nNext.\n")
        let page = try #require(geometry.pages.first)
        let box = try #require(codeBoxes(page).first)
        let next = try #require(page.texts.first { $0.string.hasPrefix("Next") })

        #expect(box.height > 0)
        #expect(abs((box.bottom - next.top) - Self.standardGap) < Self.tolerance)
    }

    @Test("A code block that ends the document adds no page")
    func codeBlockAtEndOfDocument() throws {
        let geometry = try geometry("Intro.\n\n```\nlast\n```\n")
        #expect(geometry.pages.count == 1)
    }

    @Test("A code block split across pages keeps its box inside the margins with no sliver or overlap")
    func splitAcrossPages() throws {
        let code = (1 ... 120).map { "line \($0)" }.joined(separator: "\n")
        let options = PDFOptions()
        let geometry = try geometry("Intro.\n\n```\n\(code)\n```\n\nAfter the long box.\n", options: options)
        let pages = geometry.pages
        try #require(pages.count >= 2)

        let bottomMargin = options.margins.bottom
        let topLimit = options.pageSize.height - options.margins.top
        let lineHeight = 11.0 * 0.9 * 1.4
        var rendered = 0
        for page in pages {
            for box in codeBoxes(page) {
                #expect(box.bottom >= bottomMargin - Self.tolerance, "box bottom \(box.bottom) below margin")
                #expect(box.top <= topLimit + Self.tolerance, "box top \(box.top) above page")
                #expect(box.height >= lineHeight + 12 - Self.tolerance, "sliver of height \(box.height)")
                rendered += 1
            }
        }
        #expect(rendered >= 2)

        let lastPage = try #require(pages.last)
        let lastBox = try #require(codeBoxes(lastPage).last)
        let after = try #require(lastPage.texts.first { $0.string.hasPrefix("After") })
        #expect(lastBox.bottom - after.top >= Self.standardGap - Self.tolerance)

        let everyLine = pages.flatMap(\.texts).filter { $0.string.hasPrefix("line ") }
        #expect(everyLine.count == 120)
        for page in pages {
            for text in page.texts where text.string.hasPrefix("line ") {
                #expect(text.bottom >= bottomMargin - Self.tolerance)
            }
        }
    }

    @Test("Code blocks inside a list item clear the next paragraph too")
    func insideListItem() throws {
        let geometry = try geometry("- item\n\n  ```\n  box\n  ```\n\n  after\n")
        let page = try #require(geometry.pages.first)
        let box = try #require(page.rects.first { $0.width < 487 && $0.width > 100 })
        let after = try #require(page.texts.first { $0.string.hasPrefix("after") })
        #expect(box.bottom - after.top > 0)
    }

    @Test("Poppler reports the next paragraph below the code box")
    func popplerWitnessesClearance() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Intro.\n\n```\nbox\n```\n\nNext.\n")
        let page = try #require(ContentStreamGeometry(pdf: data).pages.first)
        let box = try #require(codeBoxes(page).first)
        let result = try PDFValidation.pdftotextTSV(data: data, name: "code-block-spacing")
        try #require(result.exitCode == 0, "pdftotext failed:\n\(result.output)")

        let pageHeight = PDFOptions().pageSize.height
        var wordTop: Double?
        for line in result.output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            if fields.count == 12, fields[11] == "Next." {
                wordTop = Double(fields[7])
            }
        }
        let top = try #require(wordTop)
        let boxBottomFromTop = pageHeight - box.bottom
        #expect(top > boxBottomFromTop, "Poppler word top \(top) is not below the box bottom \(boxBottomFromTop)")
    }
}
