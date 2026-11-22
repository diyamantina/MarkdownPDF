import Foundation
@testable import MarkdownPDF
import Testing

/// The tiles that are text in a box (a callout, a call to action, a hero, a card grid) drawn in the PDF: the words of the page in its order, the inline Markdown
/// of the text kept (emphasis, code, links), the buttons as boxes whose label is a link, and everything inside the page.
@Suite("Tile blocks: callout, cta, hero, cards")
struct TilePanelTests {
    private func tile(_ type: String, _ body: String) -> TileBlock? {
        if case let .tile(block) = TileBlock.parse(type: type, body: body) {
            return block
        }
        return nil
    }

    private func refusal(_ type: String, _ body: String) -> String? {
        if case let .unsupported(reason) = TileBlock.parse(type: type, body: body) {
            return reason
        }
        return nil
    }

    // MARK: parsing

    @Test("a callout is a title (Note by default) and an optional body")
    func callout() {
        #expect(tile("callout", "title: Heads up\nbody: Read this *twice*.") == .callout(.init(title: "Heads up", body: "Read this *twice*.")))
        #expect(tile("callout", "body: Only a body") == .callout(.init(title: "Note", body: "Only a body")))
        #expect(tile("callout", "title: Only a title") == .callout(.init(title: "Only a title", body: nil)))
    }

    @Test("a call to action has a title, a body and up to two buttons, the second needing the first")
    func cta() {
        let block = tile("cta", "title: Write\nbody: Two paragraphs.\nprimary: [Write to me](mailto:a@example.com)\nsecondary: [Book](https://example.com/book)")
        guard case let .cta(cta)? = block else {
            Issue.record("not a cta")
            return
        }
        #expect(cta.title == "Write" && cta.body == "Two paragraphs.")
        #expect(cta.buttons == [.init(label: "Write to me", destination: "mailto:a@example.com"), .init(label: "Book", destination: "https://example.com/book")])
        #expect(refusal("cta", "title: T\nsecondary: [B](https://x.example)")?.contains("primary") == true)
        #expect(refusal("cta", "title: T\nprimary: not a link")?.contains("[Label](url)") == true)
    }

    @Test("a hero has an eyebrow, a title (a rolling word shows its first), a body and buttons")
    func hero() {
        guard case let .hero(hero)? = tile("hero", "eyebrow: Consultant\ntitle: Docs for {every API|any question}\nbody: I review.\nprimary: [Tell me](/contact/)") else {
            Issue.record("not a hero")
            return
        }
        #expect(hero.eyebrow == "Consultant" && hero.title == "Docs for every API" && hero.body == "I review.")
        #expect(hero.buttons == [.init(label: "Tell me", destination: "/contact/")])
        guard case let .hero(braces)? = tile("hero", "title: {braces} stay\nkicker: K\nlede: L") else {
            Issue.record("not a hero")
            return
        }
        #expect(braces.title == "{braces} stay" && braces.eyebrow == "K" && braces.body == "L")
    }

    @Test("each card line starts a card; the lines after it belong to it; the grid has one to three columns")
    func cards() {
        guard case let .cards(grid)? = tile("cards", "columns: 3\ncard: A\nbadge: Review\nbody: Boundaries.\nlink: /a/\ncard: B") else {
            Issue.record("not a card grid")
            return
        }
        #expect(grid.columns == 3)
        #expect(grid.cards == [.init(title: "A", badge: "Review", body: "Boundaries.", link: "/a/"), .init(title: "B", badge: nil, body: nil, link: nil)])
        guard case let .cards(plain)? = tile("cards", "card: Only") else {
            Issue.record("not a card grid")
            return
        }
        #expect(plain.columns == 2, "two columns by default")
    }

    @Test("every mistake is a refusal that says what to change", arguments: [
        ("callout", "", "title or a body"),
        ("callout", "title: A\ncolor: red", "color"),
        ("callout", "title: A\ntitle: B", "twice"),
        ("hero", "body: only", "title"),
        ("cta", "body: only", "title"),
        ("cards", "", "no card"),
        ("cards", "body: x", "before any card"),
        ("cards", "card: A\nbody: x\nbody: y", "twice"),
        ("cards", "columns: 4\ncard: A", "1, 2 or 3"),
    ])
    func refusals(type: String, body: String, mention: String) {
        let reason = refusal(type, body)
        #expect(reason?.contains(mention) == true, Comment(rawValue: reason ?? "no refusal"))
    }

    // MARK: the PDF

    private func printed(_ markdown: String) throws -> (words: [String], reader: PDFDocumentReader) {
        let reader = try PDFDocumentReader(data: MarkdownPDFRenderer().render(markdown: markdown))
        return (reader.pages.flatMap(\.words).map(\.text), reader)
    }

    @Test("a callout prints its title and body in order, with the emphasis and code of the body kept as text")
    func printedCallout() throws {
        let result = try printed("```tile callout\ntitle: Heads up\nbody: Read `this` *twice*.\n```\n")
        #expect(result.words == ["Heads", "up", "Read", "this", "twice."], Comment(rawValue: "\(result.words)"))
    }

    @Test("a call to action prints its title, body and the labels of its buttons, and the buttons are links")
    func printedCTA() throws {
        let result =
            try printed("```tile cta\ntitle: Write\nbody: Two paragraphs.\nprimary: [Write to me](https://example.com/a)\nsecondary: [Book a call](https://example.com/b)\n```\n")
        #expect(result.words == ["Write", "Two", "paragraphs.", "Write", "to", "me", "Book", "a", "call"], Comment(rawValue: "\(result.words)"))
        #expect(try PDFInspector(MarkdownPDFRenderer().render(markdown: "```tile cta\ntitle: W\nprimary: [A](https://example.com/a)\nsecondary: [B](https://example.com/b)\n```\n"))
            .linkAnnotationCount == 2)
    }

    @Test("a hero prints its eyebrow, title, body and buttons in order")
    func printedHero() throws {
        let result = try printed("```tile hero\neyebrow: Consultant\ntitle: Docs for {every API|any question}\nbody: I review.\nprimary: [Tell me](https://example.com/c)\n```\n")
        #expect(result.words == ["Consultant", "Docs", "for", "every", "API", "I", "review.", "Tell", "me"], Comment(rawValue: "\(result.words)"))
    }

    @Test("cards print badge, title and body of each card in order, a linked title is a link, and nothing leaves the page")
    func printedCards() throws {
        let markdown = "```tile cards\ncard: App architecture\nbadge: Review\nbody: Package boundaries.\nlink: https://example.com/a\ncard: SwiftUI\nbody: Why a view runs again.\n```\n"
        let result = try printed(markdown)
        #expect(result.words == ["Review", "App", "architecture", "Package", "boundaries.", "SwiftUI", "Why", "a", "view", "runs", "again."], Comment(rawValue: "\(result.words)"))
        let targets = Set(result.reader.pages.flatMap(\.links).map(\.target))
        #expect(targets == [.uri("https://example.com/a")], Comment(rawValue: "\(targets)"))
        #expect(result.reader.pages.flatMap(\.words).allSatisfy { $0.width > 0 && $0.x >= 0 && $0.x + $0.width <= 595.28 })
    }

    @Test("a long body wraps inside its box and a long page of cards continues on the next page")
    func wrapsAndPages() throws {
        let long = String(repeating: "word ", count: 120)
        let one = try printed("```tile callout\ntitle: T\nbody: \(long)\n```\n")
        #expect(one.words.filter { $0 == "word" }.count == 120)
        #expect(one.reader.pages.flatMap(\.words).allSatisfy { $0.x + $0.width <= 595.28 })
        let many = (1 ... 40).map { "card: Card \($0)\nbody: text \($0)" }.joined(separator: "\n")
        let result = try printed("```tile cards\n\(many)\n```\n")
        #expect(result.reader.pages.count > 1)
        #expect(result.words.filter { $0 == "Card" }.count == 40)
    }

    @Test("a refused panel prints as a code block that says why")
    func refusedPanel() throws {
        let words = try printed("```tile hero\nbody: no title\n```\n").words
        #expect(words.contains("Unsupported") && words.contains("title"), Comment(rawValue: "\(words)"))
    }
}
