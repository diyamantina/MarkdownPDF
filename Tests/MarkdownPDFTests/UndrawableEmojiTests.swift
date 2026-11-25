import Foundation
@testable import MarkdownPDF
import Testing

/// An emoji no bundled face can draw (they carry no color glyphs) used to print as an empty box, or as a question mark. It is left out instead, with the
/// space that set it apart, so the words around it read as written. A character the face can draw is drawn, and a missing glyph that is not an emoji
/// (a script the faces lack) is still shown as the face's missing-glyph box: that is a fault to see, not to hide.
@Suite("Emoji the faces cannot draw are left out")
struct UndrawableEmojiTests {
    /// The colour face of these tests: an OLDER emoji face (the face bundled before Twemoji 17.0.3, kept as a fixture), given as the caller's face. The
    /// bundled face now draws every emoji the platform's Unicode data knows, so an emoji "no face can draw" needs a face that is older than the data; the
    /// feature (omitting an emoji nothing draws) is the same for a caller's face of any age.
    private static let olderFace: PDFOptions.EmbeddedFontSource? = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/OlderEmojiFace/Twemoji.Mozilla.ttf")
        return (try? Data(contentsOf: url)).map { PDFOptions.EmbeddedFontSource(data: $0, baseName: "Twemoji") }
    }()

    private static var fonts: PDFOptions.EmbeddedFonts {
        var fonts = PDFOptions.EmbeddedFonts.dejaVu
        fonts.emoji = olderFace
        return fonts
    }

    /// Emoji that neither the bundled text faces nor the older colour face can draw (newer than the colour face), found from the faces
    /// themselves so the tests do not depend on a hand-picked code point.
    private static let missing: [String] = {
        guard let catalog = try? PDFEmbeddedFontCatalog(fonts: fonts) else { return [] }
        var found: [String] = []
        for value in 0x1F300 ... 0x1FAFF {
            guard let scalar = Unicode.Scalar(UInt32(value)), scalar.properties.isEmojiPresentation else { continue }
            let cluster = EmojiSegmenter.Cluster(scalars: [scalar], base: scalar)
            if !catalog.covers(String(scalar), font: .helvetica), catalog.colorEmoji?.baseGlyph(of: cluster) == nil {
                found.append(String(scalar))
            }
        }
        return found
    }()

    private func words(_ markdown: String, omit: Bool = true) throws -> [PDFDocumentReader.Word] {
        let renderer = MarkdownPDFRenderer(options: PDFOptions(embeddedFonts: Self.fonts, omitUndrawableEmoji: omit))
        return try PDFDocumentReader(data: renderer.render(markdown: markdown)).pages.flatMap(\.words)
    }

    @Test("with the option off, as by default, the text is as written and the heading keeps the gap of the missing-glyph box")
    func offByDefault() throws {
        let printed = try words("# \(Self.missing[0]) The Foundation\n", omit: false)
        let first = try #require(printed.first { $0.text == "The" })
        #expect(first.x > 56, Comment(rawValue: "The starts at \(first.x)"))
    }

    @Test("a heading that starts with an emoji starts at the margin with its first word")
    func heading() throws {
        let printed = try words("# \(Self.missing[0]) The Foundation\n")
        let first = try #require(printed.first { $0.text == "The" })
        #expect(first.x < 56, Comment(rawValue: "The starts at \(first.x): the emoji left a gap or a box"))
        #expect(printed.map(\.text).filter { !$0.isEmpty } == ["The", "Foundation"] || printed.map(\.text).contains("Foundation"))
    }

    @Test("a list item and a sentence with an emoji in the middle lose the emoji and one space, not the words")
    func inText() throws {
        let printed = try words("- \(Self.missing[0]) Integration with the generator\n\nBefore \(Self.missing[1]) after.\n").map(\.text)
        #expect(printed.contains("Integration") && printed.contains("generator"), Comment(rawValue: "\(printed)"))
        #expect(printed.contains("Before") && printed.contains("after."), Comment(rawValue: "\(printed)"))
        #expect(!printed.contains(where: { $0.contains(Self.missing[1]) }))
    }

    @Test("text with no emoji, and a character the face does draw, are unchanged")
    func unchanged() throws {
        let printed = try words("Caf\u{E9} \u{2014} na\u{EF}ve \u{3C0} and plain words.\n").map(\.text)
        #expect(printed.contains("plain") && printed.contains("words."), Comment(rawValue: "\(printed)"))
    }

    @Test("the emoji the bundled colour face can draw are drawn even with the option on: only an emoji no face can draw is left out")
    func drawableIsKept() throws {
        let printed = try words("# \u{1F9F1} The Foundation\n")
        let first = try #require(printed.first { $0.text == "The" })
        #expect(first.x > 56, Comment(rawValue: "The starts at \(first.x): the drawn emoji must keep its place"))
        #expect(Self.missing.count >= 2, "the faces cannot draw at least two emoji: the tests above need them")
    }
}
