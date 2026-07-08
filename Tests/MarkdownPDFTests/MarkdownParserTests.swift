import MarkdownPDF
import Testing

@Suite("Markdown parser")
struct MarkdownParserTests {
    @Test("Indented markers nest instead of flattening into siblings")
    func nestsUnorderedLists() {
        let document = MarkdownParser().parse("""
        - top one
          - nested a
            - deep
        - top two
        """)

        guard case let .unorderedList(items) = document.blocks.first else {
            Issue.record("expected an unordered list, got \(document.blocks)")
            return
        }
        #expect(items.count == 2)

        guard case let .unorderedList(nested) = items[0].blocks.last else {
            Issue.record("expected a nested list inside the first item")
            return
        }
        #expect(nested.count == 1)
        guard case let .unorderedList(deep) = nested[0].blocks.last else {
            Issue.record("expected a doubly nested list")
            return
        }
        #expect(deep.count == 1)
        // The last top-level item is a sibling, not swallowed by the nesting.
        #expect(items[1].blocks.count == 1)
    }

    @Test("A marker below the content column is a sibling, however it is indented")
    func shallowIndentStaysSibling() {
        // CommonMark allows up to three spaces before a marker without nesting it.
        // "- a" has content column 2, so " - b" is a sibling and "  - b" nests.
        let sibling = MarkdownParser().parse("- a\n - b\n")
        #expect(sibling.blocks.count == 1)
        guard case let .unorderedList(items) = sibling.blocks[0] else {
            Issue.record("expected one list")
            return
        }
        #expect(items.count == 2)

        // Dedenting below the list's own indent keeps the items siblings too.
        let dedented = MarkdownParser().parse("  - a\n- b\n")
        #expect(dedented.blocks.count == 1)

        let nested = MarkdownParser().parse("- a\n  - b\n")
        #expect(nested.blocks.count == 1)
        guard case let .unorderedList(outer) = nested.blocks[0] else {
            Issue.record("expected one list")
            return
        }
        #expect(outer.count == 1)
    }

    @Test("Ordered lists nest and each level keeps its own start")
    func nestsOrderedLists() {
        let document = MarkdownParser().parse("""
        3. three
           1. sub one
           2. sub two
        4. four
        """)

        guard case let .orderedList(start, items) = document.blocks.first else {
            Issue.record("expected an ordered list")
            return
        }
        #expect(start == 3)
        #expect(items.count == 2)
        guard case let .orderedList(nestedStart, nested) = items[0].blocks.last else {
            Issue.record("expected a nested ordered list")
            return
        }
        #expect(nestedStart == 1)
        #expect(nested.count == 2)
    }

    @Test("A blank line between siblings makes one loose list, not two lists")
    func blankLineKeepsOneList() {
        let loose = MarkdownParser().parse("- a\n\n- b\n")
        #expect(loose.blocks.count == 1)
        guard case let .unorderedList(items) = loose.blocks[0] else {
            Issue.record("expected one list")
            return
        }
        #expect(items.count == 2)

        // An ordered loose list must not restart its numbering.
        let ordered = MarkdownParser().parse("1. a\n\n2. b\n")
        #expect(ordered.blocks.count == 1)

        // A dedented paragraph still ends the list.
        let ended = MarkdownParser().parse("- a\n\nplain\n")
        #expect(ended.blocks.count == 2)
        if case .paragraph = ended.blocks[1] {} else {
            Issue.record("expected the list to end at the dedented paragraph")
        }
    }

    @Test("An item carries block content, not just one paragraph")
    func itemsCarryBlockContent() {
        let document = MarkdownParser().parse("""
        - outer

          a second paragraph

        - sibling
        """)

        guard case let .unorderedList(items) = document.blocks.first else {
            Issue.record("expected an unordered list")
            return
        }
        #expect(items.count == 2)
        #expect(items[0].blocks.count == 2)
    }

    @Test("Task checkboxes survive nesting")
    func taskItemsNest() {
        let document = MarkdownParser().parse("""
        - [x] done
        - [ ] todo
          - [x] sub
        """)

        guard case let .unorderedList(items) = document.blocks.first else {
            Issue.record("expected an unordered list")
            return
        }
        #expect(items.count == 2)
        #expect(items[0].checkbox == .checked)
        #expect(items[1].checkbox == .unchecked)

        guard case let .unorderedList(nested) = items[1].blocks.last else {
            Issue.record("expected a nested task list")
            return
        }
        #expect(nested[0].checkbox == .checked)
    }

    @Test("Parses headings, inline styles, links, and code")
    func parsesInlineMarkdown() {
        let document = MarkdownParser().parse("""
        # Title

        Text with **strong**, *emphasis*, `code`, ~~strike~~, and [a link](https://example.com).
        """)

        #expect(document.blocks.count == 2)
        #expect(document.blocks.first == .heading(level: 1, content: [.text("Title")]))
    }

    @Test("Parses GFM tables")
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
