import MarkdownPDF
import Testing

/// The render half of a parser test that moved with the parser to ExtendedMarkdown: the parse half is there.
@Suite("Link with a trailing quote: the render")
struct LinkTrailingQuoteRenderTests {
    @Test("A stray trailing quote in a link destination does not crash", arguments: [
        "[a](\")",
        "[site](https://example.com\")",
        "![alt](url\")",
        "[a](\")text after",
        "[a](\"",
    ])
    func linkWithTrailingQuoteDoesNotCrash(_ markdown: String) throws {
        // The only `"` sits at the end, so it is not a title opener. Treating it as
        // one built an inverted range and aborted the whole render.
        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        #expect(!data.isEmpty)
    }
}
