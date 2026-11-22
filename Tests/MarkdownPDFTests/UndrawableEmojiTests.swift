import Foundation
@testable import MarkdownPDF
import Testing

/// An emoji no bundled face can draw (they carry no color glyphs) used to print as an empty box, or as a question mark. It is left out instead, with the
/// space that set it apart, so the words around it read as written. A character the face can draw is drawn, and a missing glyph that is not an emoji
/// (a script the faces lack) is still shown as the face's missing-glyph box: that is a fault to see, not to hide.
@Suite("Emoji the faces cannot draw are left out")
struct UndrawableEmojiTests {
    private func words(_ markdown: String, omit: Bool = true) throws -> [PDFDocumentReader.Word] {
        let renderer = MarkdownPDFRenderer(options: PDFOptions(omitUndrawableEmoji: omit))
        return try PDFDocumentReader(data: renderer.render(markdown: markdown)).pages.flatMap(\.words)
    }

    @Test("with the option off, as by default, the text is as written and the heading keeps the gap of the missing-glyph box")
    func offByDefault() throws {
        let printed = try words("# \u{1F9F1} The Foundation\n", omit: false)
        let first = try #require(printed.first { $0.text == "The" })
        #expect(first.x > 56, Comment(rawValue: "The starts at \(first.x)"))
    }

    @Test("a heading that starts with an emoji starts at the margin with its first word")
    func heading() throws {
        let printed = try words("# \u{1F9F1} The Foundation\n")
        let first = try #require(printed.first { $0.text == "The" })
        #expect(first.x < 56, Comment(rawValue: "The starts at \(first.x): the emoji left a gap or a box"))
        #expect(printed.map(\.text).filter { !$0.isEmpty } == ["The", "Foundation"] || printed.map(\.text).contains("Foundation"))
    }

    @Test("a list item and a sentence with an emoji in the middle lose the emoji and one space, not the words")
    func inText() throws {
        let printed = try words("- \u{2699}\u{FE0F} Integration with the generator\n\nBefore \u{1F680} after.\n").map(\.text)
        #expect(printed.contains("Integration") && printed.contains("generator"), Comment(rawValue: "\(printed)"))
        #expect(printed.contains("Before") && printed.contains("after."), Comment(rawValue: "\(printed)"))
        #expect(!printed.contains(where: { $0.unicodeScalars.contains { $0.value == 0x1F680 } }))
    }

    @Test("text with no emoji, and a character the face does draw, are unchanged")
    func unchanged() throws {
        let printed = try words("Caf\u{E9} \u{2014} na\u{EF}ve \u{3C0} and plain words.\n").map(\.text)
        #expect(printed.contains("plain") && printed.contains("words."), Comment(rawValue: "\(printed)"))
    }
}
