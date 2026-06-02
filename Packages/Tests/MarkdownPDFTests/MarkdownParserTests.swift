import MarkdownPDF
import Testing

@Suite("Markdown parser")
struct MarkdownParserTests {
    @Test("Parses headings, inline styles, links, and code")
    func parsesInlineMarkdown() {
        let document = MarkdownParser().parse("""
        # Title

        Text with **strong**, *emphasis*, `code`, ~~strike~~, and [a link](https://example.com).
        """)

        #expect(document.blocks.count == 2)
        #expect(document.blocks.first == .heading(level: 1, content: [.text("Title")]))
    }

    @Test("Parses GitHub style tables")
    func parsesTables() {
        let document = MarkdownParser().parse("""
        | Name | Score |
        |:-----|------:|
        | Ada  | 10    |
        | Lin  | 8     |
        """)

        guard case let .table(table) = document.blocks.first else {
            Issue.record("Expected a table")
            return
        }

        #expect(table.headers.count == 2)
        #expect(table.rows.count == 2)
        #expect(table.alignments == [.leading, .trailing])
    }

    @Test("Parses standalone images")
    func parsesImages() {
        let document = MarkdownParser().parse("![Alt text](image.jpg \"Title\")")

        guard case let .paragraph(inlines) = document.blocks.first,
              case let .image(alt, source, title) = inlines.first
        else {
            Issue.record("Expected an image paragraph")
            return
        }

        #expect(alt == "Alt text")
        #expect(source == "image.jpg")
        #expect(title == "Title")
    }

    @Test("Parses backslash escapes in text and link labels")
    func parsesBackslashEscapes() {
        let document = MarkdownParser().parse(#"\[literal\] \*not strong\* [ACME \[Labs\]](https://example.com/a%29)"#)

        guard case let .paragraph(inlines) = document.blocks.first else {
            Issue.record("Expected an escaped text paragraph")
            return
        }

        #expect(inlines == [
            .text("[literal] *not strong* "),
            .link(children: [.text("ACME [Labs]")], destination: "https://example.com/a%29", title: nil),
        ])
    }

    @Test("Leaves dollar math literal unless math parsing is enabled")
    func leavesDollarMathLiteralUnlessEnabled() {
        let document = MarkdownParser().parse("Price is $5 and math is $x^2$.")

        #expect(document.blocks == [
            .paragraph([.text("Price is $5 and math is $x^2$.")]),
        ])
    }

    @Test("Parses opt-in inline and display math")
    func parsesOptInMath() {
        let document = MarkdownParser(options: .init(mathTypesetting: true)).parse("""
        Inline $x^2$ and escaped \\$5.

        $$
        \\frac{a}{b}
        $$
        """)

        #expect(document.blocks == [
            .paragraph([
                .text("Inline "),
                .inlineMath(MarkdownMath(source: "x^2", mode: .inline)),
                .text(" and escaped $5."),
            ]),
            .displayMath(MarkdownMath(source: "\\frac{a}{b}", mode: .display)),
        ])
    }

    @Test("Parses GFM footnote references and definitions")
    func parsesGFMFootnotes() {
        let document = MarkdownParser().parse("""
        Alpha[^note] and missing [^missing].

        [^note]: Definition with **strong** text.
            Continuation line.
        """)

        #expect(document.blocks.count == 2)
        guard case let .paragraph(inlines) = document.blocks.first else {
            Issue.record("Expected a paragraph with footnote references")
            return
        }
        #expect(inlines == [
            .text("Alpha"),
            .footnoteReference(label: "note"),
            .text(" and missing "),
            .footnoteReference(label: "missing"),
            .text("."),
        ])

        guard case let .footnoteDefinition(label, blocks) = document.blocks.last else {
            Issue.record("Expected a footnote definition")
            return
        }
        #expect(label == "note")
        #expect(blocks == [
            .paragraph([
                .text("Definition with "),
                .strong([.text("strong")]),
                .text(" text."),
                .softBreak,
                .text("Continuation line."),
            ]),
        ])
    }

    @Test("Parses GFM task-list checkboxes")
    func parsesGFMTaskLists() {
        let document = MarkdownParser().parse("""
        - [ ] Open item
        - [x] Done item
        - [X] Also done
        - [ ]not a task
        """)

        guard case let .unorderedList(items) = document.blocks.first else {
            Issue.record("Expected an unordered list")
            return
        }

        #expect(items.map(\.checkbox) == [.unchecked, .checked, .checked, nil])
        #expect(items.map(\.blocks) == [
            [.paragraph([.text("Open item")])],
            [.paragraph([.text("Done item")])],
            [.paragraph([.text("Also done")])],
            [.paragraph([.text("[ ]not a task")])],
        ])
    }
}
