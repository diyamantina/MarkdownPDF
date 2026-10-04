@testable import MarkdownPDF
import Testing

/// Oracle: the parsed tree for each marker spelling, written by hand.
@Suite("Index marker parsing")
struct IndexMarkerParsingTests {
    private func blocks(_ markdown: String, markers: Bool = true) -> [MarkdownBlock] {
        MarkdownParser(options: MarkdownParser.Options(indexMarkers: markers)).parse(markdown).blocks
    }

    @Test("A marker becomes an invisible inline node")
    func marker() {
        #expect(blocks("A {{index: layer}} B") == [
            .paragraph([.text("A "), .indexMarker(term: "layer"), .text(" B")]),
        ])
    }

    @Test("Spacing inside a marker is normalized and a main > sub pair is kept whole")
    func normalization() {
        #expect(blocks("{{index:   animation  >   timing  }}") == [
            .paragraph([.indexMarker(term: "animation > timing")]),
        ])
    }

    @Test("A marker with an empty term is consumed and dropped")
    func emptyTerm() {
        #expect(blocks("A {{index:}}B{{index:   }}C") == [.paragraph([.text("A B"), .text("C")]).merged])
    }

    @Test("Without the option the text stays literal")
    func disabled() {
        #expect(blocks("A {{index: layer}} B", markers: false) == [.paragraph([.text("A {{index: layer}} B")])])
    }

    @Test("Inside inline code and fenced code a marker is literal text")
    func code() {
        #expect(blocks("`{{index: layer}}`") == [.paragraph([.code("{{index: layer}}")])])
        #expect(blocks("```\n{{index: layer}}\n```") == [.codeBlock(info: nil, code: "{{index: layer}}")])
    }

    @Test("An unclosed marker or one spanning a line break is literal text")
    func malformed() {
        #expect(blocks("{{index: layer") == [.paragraph([.text("{{index: layer")])])
        #expect(blocks("{{index: lay\ner}}") == [.paragraph([.text("{{index: lay"), .softBreak, .text("er}}")])])
        #expect(blocks("{{notindex: layer}}") == [.paragraph([.text("{{notindex: layer}}")])])
    }

    @Test("Markers work inside emphasis, links, headings and table cells")
    func nested() {
        #expect(blocks("**bold {{index: a}}**") == [.paragraph([.strong([.text("bold "), .indexMarker(term: "a")])])])
        #expect(blocks("# Title {{index: b}}") == [.heading(level: 1, content: [.text("Title "), .indexMarker(term: "b")])])
        #expect(blocks("[link {{index: c}}](x.md)") == [
            .paragraph([.link(children: [.text("link "), .indexMarker(term: "c")], destination: "x.md", title: nil)]),
        ])
    }
}

private extension MarkdownBlock {
    /// The paragraph with adjacent text nodes merged, as the parser merges them.
    var merged: MarkdownBlock {
        guard case let .paragraph(inlines) = self else {
            return self
        }
        return .paragraph([.text(inlines.compactMap { inline -> String? in
            if case let .text(text) = inline {
                text
            } else {
                nil
            }
        }.joined())])
    }
}
