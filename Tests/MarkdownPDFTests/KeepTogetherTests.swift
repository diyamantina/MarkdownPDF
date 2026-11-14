import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: which page each word lands on, read from the generated content streams.
/// Every unit under test is written with a word of its own (`item7`, `sec3`), so
/// "the unit is on one page" is "its word is found on one page", whatever the
/// renderer believes.
@Suite("Keep together")
struct KeepTogetherTests {
    /// A short page, so a few lines fill it: `lines` body lines of 11 pt at 1.24.
    private static func options(_ keep: PDFOptions.KeepTogether = [], lines: Double = 20) -> PDFOptions {
        var options = PDFOptions()
        options.pageSize = PDFOptions.PageSize(width: 400, height: 54 * 2 + 11 * 1.24 * lines)
        options.keepTogether = keep
        return options
    }

    private static func render(_ markdown: String, _ options: PDFOptions) throws -> Data {
        try MarkdownPDFRenderer(options: options).render(markdown: markdown)
    }

    /// For each word that starts with `prefix`, the pages it is drawn on.
    private static func pages(of prefix: String, in pdf: Data) -> [String: Set<Int>] {
        var found: [String: Set<Int>] = [:]
        for (index, page) in ContentStreamGeometry(pdf: pdf).pages.enumerated() {
            for text in page.texts {
                let word = text.string.trimmingCharacters(in: .whitespaces)
                if word.hasPrefix(prefix) {
                    found[word, default: []].insert(index)
                }
            }
        }
        return found
    }

    /// Every word of the document in drawing order, pages joined.
    private static func words(in pdf: Data) -> [String] {
        ContentStreamGeometry(pdf: pdf).pages.flatMap { page in
            page.texts.map { $0.string.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }

    /// `count` list items of three to seven lines, so page ends fall inside items.
    private static func list(_ count: Int, marker: (Int) -> String = { _ in "-" }, prefix: String = "item") -> String {
        (1 ... count).map { number in
            "\(marker(number)) " + Array(repeating: "\(prefix)\(number)", count: 18 + number * 7 % 23).joined(separator: " ")
        }.joined(separator: "\n") + "\n"
    }

    /// Whether any word that starts with `prefix` is drawn on more than one page.
    private static func breaks(_ prefix: String, in pdf: Data) -> Bool {
        pages(of: prefix, in: pdf).contains { $0.value.count > 1 }
    }

    @Test("By default a list item breaks where the page ends")
    func defaultSplitsItems() throws {
        let pdf = try Self.render(Self.list(12), Self.options())

        #expect(Self.breaks("item", in: pdf), "the fixture must put an item across a page break")
        #expect(PDFOptions().keepTogether == [])
    }

    @Test("List items stay on one page", arguments: ["-", "1."])
    func listItemsStayWhole(marker: String) throws {
        let markdown = Self.list(12, marker: { _ in marker })
        let plain = try Self.render(markdown, Self.options())
        let kept = try Self.render(markdown, Self.options(.listItems))
        let pages = Self.pages(of: "item", in: kept)

        try #require(Self.breaks("item", in: plain), "the fixture must put an item across a page break")
        #expect(pages.count == 12)
        for (word, on) in pages {
            #expect(on.count == 1, "\(word) is on pages \(on.sorted())")
        }
        // Nothing is lost, repeated or reordered by moving items.
        #expect(Self.words(in: kept) == Self.words(in: plain))
    }

    @Test("An ordered list keeps its numbers when items move")
    func orderedNumbersSurvive() throws {
        let markdown = Self.list(12, marker: { _ in "1." })
        let plain = try Self.render(markdown, Self.options())
        let kept = try Self.render(markdown, Self.options(.listItems))
        try #require(kept != plain, "the fixture must move an item")
        let labels = Self.words(in: kept).filter { $0.hasSuffix(".") && Int($0.dropLast()) != nil }

        #expect(labels == (1 ... 12).map { "\($0)." })
    }

    @Test("An item taller than a page still breaks, where it would have")
    func oversizedItemBreaksInPlace() throws {
        let giant = "- " + Array(repeating: "giant", count: 400).joined(separator: " ") + "\n"
        let markdown = "intro\n\n" + giant
        let plain = try Self.render(markdown, Self.options())
        let kept = try Self.render(markdown, Self.options(.listItems))

        #expect(try #require(Self.pages(of: "giant", in: kept)["giant"]).count > 1)
        #expect(kept == plain, "an item that fits no page is laid out as without the option")
    }

    @Test("Output is byte identical when nothing meets the end of a page", arguments: [
        PDFOptions.KeepTogether.listItems, .sections, [.listItems, .sections],
    ])
    func identicalWhenNothingBreaks(keep: PDFOptions.KeepTogether) throws {
        let markdown = "# Title\n\nA paragraph.\n\n## One\n\n- alpha\n- beta\n  - nested\n\n## Two\n\n1. first\n2. second\n\n> - quoted\n"
        let plain = try Self.render(markdown, Self.options())
        let kept = try Self.render(markdown, Self.options(keep))
        #expect(kept == plain)

        // Several pages of paragraphs only: nothing is a unit, so nothing moves.
        let prose = (1 ... 30).map { _ in Array(repeating: "prose", count: 40).joined(separator: " ") }.joined(separator: "\n\n")
        var keeping = Self.options(keep)
        var unkept = Self.options()
        let prosePlain = try Self.render(prose, unkept)
        let proseKept = try Self.render(prose, keeping)
        #expect(proseKept == prosePlain)
        keeping.taggedPDF = .enabled
        unkept.taggedPDF = .enabled
        let taggedPlain = try Self.render(prose, unkept)
        let taggedKept = try Self.render(prose, keeping)
        #expect(taggedKept == taggedPlain)
    }

    @Test("A nested list moves with the item that holds it")
    func nestedListMovesWithItsItem() throws {
        let filler = Array(repeating: "filler", count: 150).joined(separator: " ")
        let outer = "- " + Array(repeating: "outer", count: 20).joined(separator: " ")
        let inner = (1 ... 4).map { "  - " + Array(repeating: "inner\($0)", count: 14).joined(separator: " ") }.joined(separator: "\n")
        let markdown = "\(filler)\n\n\(outer)\n\(inner)\n"
        let plain = try Self.render(markdown, Self.options())
        let kept = try Self.render(markdown, Self.options(.listItems))

        let before = Self.pages(of: "outer", in: plain).merging(Self.pages(of: "inner", in: plain)) { $0.union($1) }
        try #require(Set(before.values.flatMap(\.self)).count > 1, "the fixture must break inside the outer item")
        let after = Self.pages(of: "outer", in: kept).merging(Self.pages(of: "inner", in: kept)) { $0.union($1) }
        #expect(Set(after.values.flatMap(\.self)).count == 1, "outer item and nested list are on pages \(after)")
    }

    @Test("A heading is not left behind when the first item under it moves")
    func headingStaysWithFirstItem() throws {
        // A first item of about nine lines under a heading, pushed down the page a
        // line at a time, so the heading meets every amount of room left. A level 4
        // heading reserves only two lines for what follows it, far less than the item.
        let item = "- " + Array(repeating: "first", count: 100).joined(separator: " ") + "\n- second\n"
        var splitsByDefault = 0
        for lines in 1 ... 16 {
            let lead = Array(repeating: "filler", count: lines * 8).joined(separator: " ")
            let markdown = "\(lead)\n\n#### headword\n\n" + item
            let plain = try Self.render(markdown, Self.options())
            splitsByDefault += Self.breaks("first", in: plain) ? 1 : 0

            let kept = try Self.render(markdown, Self.options(.listItems))
            let heading = try #require(Self.pages(of: "headword", in: kept)["headword"])
            let first = try #require(Self.pages(of: "first", in: kept)["first"])
            #expect(first.count == 1, "first item on pages \(first.sorted()), lead of \(lines) lines")
            #expect(heading == first, "heading on \(heading.sorted()), first item on \(first.sorted()), lead of \(lines) lines")
        }
        #expect(splitsByDefault >= 3, "the fixture must break the first item in several positions")
    }

    @Test("A block under a heading is not moved away from it when both fit no page together")
    func itemUnderHeadingIsNotMovedAlone() throws {
        /// The item alone fits a page, the heading and the item together do not. Moving
        /// the item would leave the heading alone on its page, so it breaks instead.
        /// The longest item that fills one page alone leaves no room for a heading.
        func item(_ words: Int) -> String {
            "- " + Array(repeating: "tall", count: words).joined(separator: " ") + "\n"
        }
        var words = 270
        while try !Self.breaks("tall", in: Self.render(item(words + 1), Self.options())) {
            words += 1
        }
        let item = item(words)
        let markdown = "intro\n\n## headword\n\n" + item

        let plain = try Self.render(markdown, Self.options())
        try #require(Self.breaks("tall", in: plain), "under the heading the item must run over the page")
        let kept = try Self.render(markdown, Self.options(.listItems))
        #expect(kept == plain)
        let heading = try #require(Self.pages(of: "headword", in: kept)["headword"])
        let tall = try #require(Self.pages(of: "tall", in: kept)["tall"])
        #expect(tall.isSuperset(of: heading), "heading on \(heading.sorted()), item on \(tall.sorted())")
    }

    @Test("A section moves whole to the next page")
    func sectionsStayWhole() throws {
        let section = { (number: Int) in
            "## sec\(number)\n\n" + Array(repeating: "sec\(number)", count: 90 + number * 17).joined(separator: " ") + "\n\n"
                + (1 ... 2).map { _ in "- " + Array(repeating: "sec\(number)", count: 12).joined(separator: " ") }.joined(separator: "\n") + "\n\n"
        }
        let markdown = (1 ... 6).map(section).joined()
        // A taller page: a section starts with room to spare and still runs over.
        let plain = try Self.render(markdown, Self.options(lines: 45))
        let kept = try Self.render(markdown, Self.options(.sections, lines: 45))

        try #require(Self.breaks("sec", in: plain), "the fixture must break inside a section")
        let pages = Self.pages(of: "sec", in: kept)
        #expect(pages.count == 6)
        for (word, on) in pages {
            #expect(on.count == 1, "\(word) is on pages \(on.sorted())")
        }
        #expect(Self.words(in: kept) == Self.words(in: plain))
    }

    @Test("A section taller than a page breaks, and its list items are still kept")
    func oversizedSectionFallsBackToItems() throws {
        let markdown = "intro\n\n## tall\n\n" + Self.list(14)
        let sectionsOnly = try Self.render(markdown, Self.options(.sections))
        let plain = try Self.render(markdown, Self.options())
        #expect(sectionsOnly == plain, "a section that fits no page is laid out as without the option")

        try #require(Self.breaks("item", in: sectionsOnly), "the fixture must put an item across a page break")
        let both = try Self.render(markdown, Self.options([.sections, .listItems]))
        for (word, on) in Self.pages(of: "item", in: both) {
            #expect(on.count == 1, "\(word) is on pages \(on.sorted())")
        }
        let heading = try #require(Self.pages(of: "tall", in: both)["tall"])
        #expect(heading == Self.pages(of: "item1", in: both)["item1"])
    }

    @Test("The table of contents and the index follow the moved items")
    func contentsAndIndexFollow() throws {
        var options = Self.options([.listItems, .sections])
        options.tableOfContents = .enabled
        options.index = PDFOptions.Index(isEnabled: true, terms: ["item9"])
        let markdown = "# Title\n\n## Lists\n\n" + Self.list(12)
        let pdf = try Self.render(markdown, options)

        var unkept = options
        unkept.keepTogether = []
        let plain = try Self.render(markdown, unkept)
        try #require(pdf != plain, "the fixture must move an item")
        let item = try #require(Self.pages(of: "item9", in: pdf)["item9"])
        #expect(item.count == 2, "once in the list, once as the index entry: \(item.sorted())")
        // The index prints the page of the item, which is the page it was moved to.
        let geometry = ContentStreamGeometry(pdf: pdf)
        let indexPage = try #require(item.max())
        let bodyPage = try #require(item.min())
        let printed = geometry.pages[indexPage].texts.map(\.string).joined(separator: " ")
        #expect(printed.contains("\(bodyPage + 1)"), "index page reads: \(printed)")
    }

    @Test("Tagged output keeps one structure element per item and the same reading order")
    func taggedStructureIsUnchangedByMoving() throws {
        var plain = Self.options()
        plain.taggedPDF = .enabled
        var kept = Self.options(.listItems)
        kept.taggedPDF = .enabled
        let markdown = "## Lists\n\n" + Self.list(12)
        let before = try PDFInspector(Self.render(markdown, plain)).text
        let after = try PDFInspector(Self.render(markdown, kept)).text
        try #require(before != after, "the fixture must move an item")

        func count(_ needle: String, in text: String) -> Int {
            text.components(separatedBy: needle).count - 1
        }
        #expect(count("/S /LI", in: after) == 12)
        for role in ["/S /L ", "/S /LI", "/S /Lbl", "/S /LBody", "/S /P", "/S /H2"] {
            #expect(count(role, in: after) == count(role, in: before), "\(role) elements differ")
        }
    }

    @Test("Items inside a block quote, and items that hold code, a quote or a table, stay whole")
    func itemsWithOtherBlocksStayWhole() throws {
        let cases = [
            ("quoted list", "> - " + Array(repeating: "unit", count: 60).joined(separator: " ") + "\n"),
            ("code in item", "- unit\n\n  ```\n" + Array(repeating: "  unit", count: 9).joined(separator: "\n") + "\n  ```\n"),
            ("quote in item", "- unit\n\n  > " + Array(repeating: "unit", count: 60).joined(separator: " ") + "\n"),
            ("table in item", "- unit\n\n  | a | b |\n  |---|---|\n" + Array(repeating: "  | unit | unit |", count: 6).joined(separator: "\n") + "\n"),
        ]
        for (name, unit) in cases {
            // Grow the paragraph above the unit until the page ends inside the unit.
            var markdown = unit
            var plain = try Self.render(markdown, Self.options())
            for fillerWords in stride(from: 80, through: 240, by: 6) where !Self.breaks("unit", in: plain) {
                markdown = Array(repeating: "filler", count: fillerWords).joined(separator: " ") + "\n\n" + unit
                plain = try Self.render(markdown, Self.options())
            }
            try #require(Self.breaks("unit", in: plain), "\(name): the fixture must break inside the item")
            let kept = try Self.render(markdown, Self.options(.listItems))
            #expect(!Self.breaks("unit", in: kept), "\(name): item on pages \(Self.pages(of: "unit", in: kept))")
            // A table that breaks repeats its header row on the next page, so the
            // kept table has fewer words than the broken one: compare without them.
            let header: Set = ["a", "b"]
            let keptWords = Self.words(in: kept).filter { !header.contains($0) }
            let plainWords = Self.words(in: plain).filter { !header.contains($0) }
            #expect(keptWords == plainWords, "\(name): the words differ")
        }
    }

    @Test("Rendering twice gives the same bytes")
    func deterministic() throws {
        let markdown = "## Lists\n\n" + Self.list(12) + "\n## More\n\n" + Self.list(5, prefix: "more")
        let options = Self.options([.listItems, .sections])
        let first = try Self.render(markdown, options)
        let second = try Self.render(markdown, options)
        #expect(first == second)
        let unkept = try Self.render(markdown, Self.options())
        #expect(first != unkept, "the fixture must move something")
    }
}
