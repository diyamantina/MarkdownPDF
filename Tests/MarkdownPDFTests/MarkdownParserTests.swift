import MarkdownPDF
import Testing

@Suite("Markdown parser")
struct MarkdownParserTests {
    @Test("Quoting a block keeps its indentation")
    func blockQuoteKeepsIndentation() {
        // The marker is up to three spaces, `>`, then at most one space. Everything
        // after that is content, indentation intact. Trimming it dedents the whole
        // quote to column zero, so nothing inside one could nest.
        guard case let .blockQuote(inner)? = MarkdownParser().parse("> - a\n>   - b\n").blocks.first,
              case let .unorderedList(items)? = inner.first
        else {
            Issue.record("expected a quoted list")
            return
        }
        #expect(items.count == 1)
        guard case .unorderedList = items[0].blocks.last else {
            Issue.record("expected the quoted list to nest")
            return
        }

        // A second space after the marker is content, not part of the marker.
        guard case let .blockQuote(indented)? = MarkdownParser().parse(">     code\n").blocks.first,
              case let .paragraph(content)? = indented.first
        else {
            Issue.record("expected a quoted paragraph")
            return
        }
        let text = content.map { inline in
            if case let .text(value) = inline { value } else { "" }
        }.joined()
        #expect(text == "    code")

        // Up to three spaces may precede the marker.
        #expect(MarkdownParser().parse("   > quoted\n").blocks.count == 1)
        if case .blockQuote = MarkdownParser().parse("   > quoted\n").blocks[0] {} else {
            Issue.record("three spaces before the marker should still open a quote")
        }
        // A fourth does not.
        if case .blockQuote = MarkdownParser().parse("    > quoted\n").blocks[0] {
            Issue.record("four spaces should not open a quote")
        }
    }

    @Test("Hostile nesting is bounded, not a stack overflow")
    func nestingIsBounded() {
        // One 4KB line used to recurse 2000 BlockParser frames and crash with
        // SIGSEGV. Each container level costs a frame, so hostile input reaches
        // any depth in a single line.
        let bomb = String(repeating: "- ", count: 2000) + "x"
        let document = MarkdownParser().parse(bomb)
        #expect(document.blocks.count == 1)

        // Quotes and footnote bodies recurse through the same parser.
        let quoteBomb = MarkdownParser().parse(String(repeating: "> ", count: 5000) + "x")
        #expect(quoteBomb.blocks.count == 1)

        /// Depth is capped, and the deepest item keeps its text as prose rather
        /// than recursing further or dropping it.
        func depth(_ blocks: [MarkdownBlock]) -> Int {
            blocks.reduce(0) { deepest, block in
                switch block {
                case let .unorderedList(items):
                    max(deepest, 1 + items.reduce(0) { max($0, depth($1.blocks)) })
                default:
                    deepest
                }
            }
        }
        #expect(depth(document.blocks) <= MarkdownParser.maximumNestingDepth + 1)
    }

    @Test("The content column skips the spaces after the marker")
    func contentColumnSkipsMarkerSpaces() {
        /// `*   text` puts content at column 4. Keeping the extra spaces left them
        /// at the head of the item's text, so the first line drew two space glyphs
        /// and no longer aligned with its own wrapped lines.
        func firstText(_ markdown: String) -> String {
            let block = MarkdownParser().parse(markdown).blocks.first
            let inlines: [MarkdownInline]? = switch block {
            case let .unorderedList(items):
                items.first.flatMap { item -> [MarkdownInline]? in
                    if case let .paragraph(content)? = item.blocks.first { content } else { nil }
                }
            case let .orderedList(_, items):
                items.first.flatMap { item -> [MarkdownInline]? in
                    if case let .paragraph(content)? = item.blocks.first { content } else { nil }
                }
            default:
                nil
            }
            return (inlines ?? []).map { inline in
                if case let .text(text) = inline { text } else { "" }
            }.joined()
        }

        #expect(firstText("- normal\n") == "normal")
        #expect(firstText("*   spaced\n") == "spaced")
        #expect(firstText("1.   spaced\n") == "spaced")
        // Five or more spaces open an indented code block, so the content column
        // stays at one and the extra spaces are the item's own content.
        #expect(firstText("-     code\n") == "    code")
    }

    @Test("A page break survives inside a list item")
    func pageBreakSurvivesInsideAnItem() {
        /// Trailing page breaks are dropped, but only by the root parser: inside an
        /// item, "last block" is not "end of document".
        func breaks(_ markdown: String) -> Int {
            func walk(_ blocks: [MarkdownBlock]) -> Int {
                blocks.reduce(0) { total, block in
                    switch block {
                    case .pageBreak: total + 1
                    case let .unorderedList(items): total + items.reduce(0) { $0 + walk($1.blocks) }
                    case let .blockQuote(inner): total + walk(inner)
                    default: total
                    }
                }
            }
            return walk(MarkdownParser().parse(markdown).blocks)
        }

        #expect(breaks("- a\n\n  <!-- pagebreak -->\n\n- b\n") == 1)
        #expect(breaks("a\n\n<!-- pagebreak -->\n\nb\n") == 1)
        #expect(breaks("a\n\n<!-- pagebreak -->\n") == 0)
    }

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

    @Test("Unmatched inline openers parse in linear time", arguments: ["[", "![", "<", "[a](", "[^"])
    func unmatchedOpenersAreLinear(_ opener: String) {
        // Each unmatched opener used to scan to end-of-string, while the loop
        // advanced one character, so a run was O(n^2): a few KB of one byte wedged
        // the parser for seconds. A memo of "this close char is absent from here on"
        // makes it linear.
        //
        // Sized so the quadratic path still completes (a bit over a second) and
        // fails this bound outright, rather than hanging the suite. Linear parses
        // 8000 openers in well under 20 ms, a ~50x margin under the ceiling, so this
        // does not flake on a loaded machine.
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = MarkdownParser().parse(String(repeating: opener, count: 8000))
        }
        #expect(elapsed < .seconds(1), "8000 \(opener.debugDescription) took \(elapsed)")

        // The openers still parse to their literal text, unchanged by the memo.
        let parsed = MarkdownParser().parse(String(repeating: opener, count: 8))
        #expect(parsed.blocks.count == 1)
    }

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

    @Test("A link title is taken only from a distinct opening and closing quote")
    func linkTitleParsing() {
        func firstLink(_ markdown: String) -> (String, String?)? {
            guard case let .paragraph(inlines)? = MarkdownParser().parse(markdown).blocks.first
            else { return nil }
            for inline in inlines {
                if case let .link(_, destination, title) = inline { return (destination, title) }
            }
            return nil
        }

        // A real title: distinct opening quote before the closing quote at the end.
        #expect(firstLink("[a](url \"real title\")").map(\.0) == "url")
        #expect(firstLink("[a](url \"real title\")").flatMap(\.1) == "real title")

        // A lone trailing quote is part of the destination, not a title.
        #expect(firstLink("[a](https://example.com\")")?.1 == nil)
        #expect(firstLink("[a](https://example.com\")")?.0 == "https://example.com\"")
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
