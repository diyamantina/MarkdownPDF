import MarkdownPDF
import Testing

/// Every name that MarkdownPDF published for the Markdown core before it moved to ExtendedMarkdown still compiles and means
/// the same: this file names each type, each nested type, each initializer and each case. A removed alias is a compile error
/// in this file, which is the point of it; the assertions only keep the names from being unused.
@Suite("Core aliases: the published names of the Markdown core still work")
struct CoreAliasTests {
    @Test("the parser, its options and the document it returns are reachable by the old names")
    func parserNames() {
        let options = MarkdownParser.Options(mathTypesetting: true, indexMarkers: true, ignoreHTMLComments: true)
        let parser = MarkdownParser(options: options)
        let document: MarkdownDocument = parser.parse("# Title\n\nText with $x$ and {{index: term}}.\n")
        #expect(document.blocks.count == 2)
        #expect(MarkdownParser.maximumNestingDepth == 32)
        #expect(MarkdownDocument(blocks: []).blocks.isEmpty)
        #expect(MarkdownParser().options == MarkdownParser.Options())
    }

    @Test("every block case, its nested types and every inline case are reachable by the old names")
    func blockAndInlineNames() {
        let item = MarkdownBlock.ListItem(blocks: [.paragraph([.text("a")])], checkbox: .checked)
        let table = MarkdownBlock.Table(
            headers: [[.text("h")]],
            alignments: [.leading, .center, .trailing],
            rows: [[[.text("c")]]],
        )
        let blocks: [MarkdownBlock] = [
            .heading(level: 1, content: [.text("t")]),
            .paragraph([.softBreak, .lineBreak, .code("c"), .emphasis([]), .strong([]), .strikethrough([])]),
            .blockQuote([]),
            .unorderedList([item]),
            .orderedList(start: 1, items: [item]),
            .codeBlock(info: nil, code: ""),
            .displayMath(MarkdownMath(source: "x", mode: .display)),
            .table(table),
            .thematicBreak,
            .pageBreak,
            .html(""),
            .footnoteDefinition(label: "1", blocks: []),
        ]
        let inlines: [MarkdownInline] = [
            .inlineMath(MarkdownMath(source: "x", mode: .inline)),
            .link(children: [], destination: "d", title: nil),
            .image(alt: "a", source: "s", title: nil),
            .footnoteReference(label: "1"),
            .indexMarker(term: "t"),
        ]
        #expect(blocks.count == 12)
        #expect(inlines.count == 5)
        #expect(MarkdownMath(source: "x", mode: .display).delimitedSource.isEmpty == false)
    }
}
