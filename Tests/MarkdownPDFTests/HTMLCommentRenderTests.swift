import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: with the option on, the parse of a document with comments equals the parse
/// of the same document written without them; with it off, nothing changes and the
/// comments are visible text. Rendered PDFs are read back through Poppler.
@Suite("HTML comment option")
struct HTMLCommentRenderTests {
    private let on = MarkdownParser(options: MarkdownParser.Options(ignoreHTMLComments: true))
    private let off = MarkdownParser()

    private func pageTexts(_ pdf: Data, name: String) throws -> [String] {
        let result = try PDFValidation.pdftotext(data: pdf, name: name)
        try #require(result.exitCode == 0, "pdftotext failed:\n\(result.output)")
        var pages = result.output.components(separatedBy: "\u{0C}")
        if pages.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            pages.removeLast()
        }
        return pages
    }

    // MARK: Parser

    @Test("The option is off by default on the parser and on the options")
    func defaults() {
        #expect(!MarkdownParser.Options().ignoreHTMLComments)
        #expect(PDFOptions().ignoreHTMLComments == .disabled)
        #expect(PDFOptions.IgnoreHTMLComments.enabled.isEnabled)
        #expect(PDFOptions.IgnoreHTMLComments.enabled != .disabled)
    }

    @Test("Off, a block comment is an HTML block and an inline comment is text")
    func offKeepsComments() {
        #expect(off.parse("<!--print-only-->").blocks == [.html("<!--print-only-->")])
        #expect(off.parse("a<!--say: x-->b").blocks == [.paragraph([.text("a<!--say: x-->b")])])
    }

    @Test("A document with comments parses like the same document without them", arguments: [
        ("a<!--say: x-->b", "ab"),
        ("Intro.\n\n<!--print-only-->\n```text\nbox\n```\n<!--/print-only-->\n\nOutro.", "Intro.\n\n```text\nbox\n```\n\nOutro."),
        ("Before.\n\n<!--print-only-->\n| a | b |\n|---|---|\n| 1 | 2 |\n<!--/print-only-->\n\nAfter.", "Before.\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nAfter."),
        ("- one<!--x-->\n- two\n<!--y-->\n- three", "- one\n- two\n- three"),
        ("| a<!--x--> | b |\n|---|---|\n| c | <!--y-->d |", "| a | b |\n|---|---|\n| c | d |"),
        ("# Title <!--audio: t.mp3-->\n\nBody.", "# Title\n\nBody."),
        ("## Part<!--x--> two\n\nBody.", "## Part two\n\nBody."),
        ("> quoted<!--x--> text", "> quoted text"),
        ("A <!-- multi\nline\ncomment --> B", "A  B"),
    ])
    func equalsParseWithoutComments(_ withComments: String, _ without: String) {
        #expect(on.parse(withComments) == on.parse(without))
        #expect(!"\(on.parse(withComments))".contains("<!--"), "\(on.parse(withComments))")
    }

    @Test("A code span keeps its comment while a comment beside it goes")
    func codeSpanBesideComment() {
        #expect(on.parse("`<!--keep-->` and <!--drop-->done").blocks == [.paragraph([.code("<!--keep-->"), .text(" and done")])])
    }

    @Test("Code keeps its comments")
    func codeKeepsComments() {
        #expect(on.parse("```html\n<!-- keep -->\n```").blocks == [.codeBlock(info: "html", code: "<!-- keep -->")])
        #expect(on.parse("see `<!--x-->`").blocks == [.paragraph([.text("see "), .code("<!--x-->")])])
    }

    @Test("An unterminated comment stays visible text")
    func unterminated() {
        #expect(on.parse("a <!-- open\nb").blocks == off.parse("a <!-- open\nb").blocks)
    }

    @Test("The page break marker still breaks the page")
    func pageBreakStillWorks() {
        #expect(on.parse("a\n\n<!-- pagebreak -->\n\nb").blocks == [
            .paragraph([.text("a")]), .pageBreak, .paragraph([.text("b")]),
        ])
    }

    // MARK: Rendering

    private static let markers = """
    # Chapter

    The `minificationFilter`<!--say: minification filter--> reads the image.

    <!--print-only-->
    | name | value |
    |---|---|
    | alpha | 1 |
    <!--/print-only-->

    <!--audio: intro.mp3-->

    - item<!--say: item--> one
    - item two
    """

    @Test("Rendered, no comment text reaches the page and the content between markers stays")
    func renderedHasNoCommentText() throws {
        let pdf = try MarkdownPDFRenderer(options: PDFOptions(ignoreHTMLComments: .enabled)).render(markdown: Self.markers)
        let text = try pageTexts(pdf, name: "comments-on").joined(separator: "\n")
        #expect(!text.contains("<!--"))
        #expect(!text.contains("-->"))
        #expect(!text.contains("say:"))
        #expect(!text.contains("print-only"))
        #expect(!text.contains("audio:"))
        #expect(text.contains("minificationFilter"))
        #expect(text.contains("alpha"))
        #expect(text.contains("item one"))
    }

    @Test("Rendered with the option off, the comments are visible, as before")
    func renderedOffShowsComments() throws {
        let pdf = try MarkdownPDFRenderer().render(markdown: Self.markers)
        let text = try pageTexts(pdf, name: "comments-off").joined(separator: "\n")
        #expect(text.contains("<!--say: minification filter-->"))
        #expect(text.contains("<!--print-only-->"))
    }

    @Test("Turning the option on for a document with no comments changes nothing")
    func noCommentsByteIdentical() throws {
        let markdown = "# Title\n\nParagraph with `code`, a < b, and <b>html</b>.\n\n```\nfence\n```\n\n- a\n- b\n"
        let plain = try MarkdownPDFRenderer().render(markdown: markdown)
        let ignoring = try MarkdownPDFRenderer(options: PDFOptions(ignoreHTMLComments: .enabled)).render(markdown: markdown)
        #expect(plain == ignoring)
    }

    @Test("Every source of a merged render is stripped, with the page break kept")
    func mergedSources() throws {
        let options = PDFOptions(ignoreHTMLComments: .enabled)
        let pdf = try MarkdownPDFRenderer(options: options).render(sources: [
            MarkdownSource(markdown: "# A\n\nfirst<!--x-->\n\n<!-- pagebreak -->\n\nsecond"),
            MarkdownSource(markdown: "# B\n\n<!--y-->third"),
        ])
        let pages = try pageTexts(pdf, name: "comments-merged")
        #expect(pages.count == 3)
        #expect(!pages.joined().contains("<!--"))
        #expect(pages[2].contains("third"))
    }

    @Test("Comments do not reach the index or the contents")
    func contentsAndIndex() throws {
        let options = PDFOptions(
            tableOfContents: .enabled,
            index: PDFOptions.Index(isEnabled: true, terms: ["secret"]),
            ignoreHTMLComments: .enabled,
        )
        let pdf = try MarkdownPDFRenderer(options: options).render(
            markdown: "# Head<!--say: head-->\n\nbody <!-- secret -->text\n",
        )
        let text = try pageTexts(pdf, name: "comments-index").joined(separator: "\n")
        #expect(!text.contains("secret"))
        #expect(!text.contains("<!--"))
        #expect(!text.contains("Index"))
    }
}
