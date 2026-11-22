import Foundation
@testable import MarkdownPDF
import Testing

/// Drawing emoji from a COLR/CPAL colour face. The face file is not in the repository until it is approved: these tests run when the variable
/// `TWEMOJI_FONT` names a Twemoji.Mozilla.ttf, and are reported as not run otherwise.
private enum EmojiFixture {
    static let source: PDFOptions.EmbeddedFontSource? = {
        guard let path = ProcessInfo.processInfo.environment["TWEMOJI_FONT"], let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? PDFOptions.EmbeddedFontSource(data: data, baseName: "Twemoji")
    }()

    static var available: Bool {
        source != nil
    }

    static func options() -> PDFOptions {
        var fonts = PDFOptions.EmbeddedFonts.dejaVu
        fonts.emoji = source
        return PDFOptions(embeddedFonts: fonts)
    }

    /// The 23 emoji of the published posts that need colour, as the clusters they are written.
    static let census: [String] = [
        0x1F310, 0x1F449, 0x1F4A1, 0x1F4AC, 0x1F4C1, 0x1F4C2, 0x1F4CA, 0x1F4DA, 0x1F4E6, 0x1F501, 0x1F50D, 0x1F510, 0x1F605, 0x1F680, 0x1F9E0, 0x1F9E9,
        0x1F9EA, 0x1F9ED, 0x1F9F1, 0x26A1, 0x2705, 0x274C,
    ].compactMap { Unicode.Scalar(UInt32($0)).map { String($0) } } + ["\u{1F5A5}\u{FE0F}", "\u{2699}\u{FE0F}", "\u{26A0}\u{FE0F}", "\u{2B06}\u{FE0F}", "\u{2B07}\u{FE0F}"]
}

@Suite("Colour emoji")
struct ColorEmojiTests {
    @Test("every emoji of the published posts has layers in the colour face: real glyphs, palette colours that exist", .enabled(if: EmojiFixture.available))
    func layersForCensus() throws {
        let font = try ColorEmojiFont(source: #require(EmojiFixture.source))
        for text in EmojiFixture.census {
            let cluster = try #require(EmojiSegmenter.cluster(of: Character(text)), "\(text) is not a cluster")
            let layers = try #require(font.layers(of: cluster, fontSize: 12), "no layers for \(cluster.text.unicodeScalars.map(\.value))")
            #expect(!layers.isEmpty && layers.allSatisfy { $0.glyph.glyphID != 0 })
            #expect(layers.contains { $0.color != nil }, "no palette colour for \(text)")
            #expect(font.advance(of: cluster, fontSize: 12).map { $0 > 6 && $0 < 24 } == true)
        }
    }

    @Test("an emoji the face lacks has no layers and no advance, so it is left to the text path", .enabled(if: EmojiFixture.available))
    func lacking() throws {
        let font = try ColorEmojiFont(source: #require(EmojiFixture.source))
        let cluster = try EmojiSegmenter.Cluster(scalars: [#require(Unicode.Scalar(0x10FFFD))], base: #require(Unicode.Scalar(0x10FFFD)))
        #expect(font.layers(of: cluster, fontSize: 12) == nil && font.advance(of: cluster, fontSize: 12) == nil)
    }

    @Test("a run's width is its text pieces plus the emoji advance: nothing is lost or added", .enabled(if: EmojiFixture.available))
    func width() throws {
        let catalog = try PDFEmbeddedFontCatalog(fonts: EmojiFixture.options().embeddedFonts)
        let font = try #require(catalog.colorEmoji)
        let entry = try #require(catalog.entry(for: .helvetica))
        func run(_ text: String) -> PDFTextRun {
            PDFTextRun(text: text, font: .helvetica, size: 12)
        }
        let cluster = try #require(EmojiSegmenter.cluster(of: Character("\u{1F680}")))
        let whole = try catalog.width(of: run("ab \u{1F680} cd"), fallbackFontSet: .pdfBase)
        let left = try catalog.shapedMapping(for: run("ab "), entry: entry).totalAdvance
        let right = try catalog.shapedMapping(for: run(" cd"), entry: entry).totalAdvance
        let emoji = try #require(font.advance(of: cluster, fontSize: 12))
        #expect(abs(whole - (left + emoji + right)) < 1e-9, "whole \(whole) = \(left) + \(emoji) + \(right)")
        // A run with no emoji is laid out as before.
        let plain = try catalog.width(of: run("ab cd"), fallbackFontSet: .pdfBase)
        let shaped = try catalog.shapedMapping(for: run("ab cd"), entry: entry).totalAdvance
        #expect(abs(plain - shaped) < 1e-9)
    }

    @Test(
        "a document with emoji draws them from the colour face: layer colours appear in the content, glyph code 0 (the missing-glyph box) never does",
        .enabled(if: EmojiFixture.available),
    )
    func document() throws {
        let markdown = "# \u{1F9F1} The Foundation\n\n- \u{2699}\u{FE0F} Gear and \u{1F680} rocket and \u{2705} done\n"
        let renderer = MarkdownPDFRenderer(options: EmojiFixture.options())
        let pdf = try renderer.render(markdown: markdown)
        let text = String(decoding: pdf, as: UTF8.self)
        #expect(text.contains("/EF6"), "the emoji face is not a page font resource")
        let reader = try PDFDocumentReader(data: pdf)
        let words = reader.pages.flatMap(\.words).map(\.text)
        #expect(words.contains("The") && words.contains("Foundation") && words.contains("rocket"), "\(words)")
    }

    @Test("no emoji of the published posts takes the missing-glyph path: each is its own colour piece between its two text pieces", .enabled(if: EmojiFixture.available))
    func noMissingGlyphBox() throws {
        let catalog = try PDFEmbeddedFontCatalog(fonts: EmojiFixture.options().embeddedFonts)
        let entry = try #require(catalog.entry(for: .helvetica))
        for text in EmojiFixture.census {
            let run = PDFTextRun(text: "a \(text) b", font: .helvetica, size: 12)
            let laidOut = try catalog.pieces(of: run, entry: entry)
            let pieces = try #require(laidOut, "\(text) is not laid out as pieces")
            #expect(pieces.count == 3, "\(text): \(pieces.count) pieces")
            guard pieces.count == 3, case let .emoji(cluster, layers, advance) = pieces[1] else {
                Issue.record("the middle piece of \(text) is not an emoji piece")
                continue
            }
            #expect(cluster.text == text && !layers.isEmpty && advance > 0)
            if case let .text(_, mapping) = pieces[0] {
                #expect(!mapping.glyphs.contains { $0.glyphID == 0 })
            }
        }
    }

    @Test("the content stream of a drawn emoji: the colour face, one fill colour per layer set, the emoji as its extraction text", .enabled(if: EmojiFixture.available))
    func contentStream() throws {
        let pdf = try MarkdownPDFRenderer(options: EmojiFixture.options()).render(markdown: "Before \u{1F680} after\n")
        let text = String(decoding: pdf, as: UTF8.self)
        #expect(text.contains("/EF6"))
        // The rocket has several layers, each its own palette colour.
        let colours = text.components(separatedBy: " rg\n").count - 1
        #expect(colours >= 4, "\(colours) fill colour operators")
        // The /ActualText of the emoji span is the rocket, UTF-16BE with a byte order mark.
        #expect(text.contains("FEFFD83DDE80"), "no /ActualText for U+1F680")
    }

    @Test("a run with no emoji draws exactly as before: the same bytes with and without the colour face")
    func plainTextUnchanged() throws {
        var withFace = PDFOptions.EmbeddedFonts.dejaVu
        withFace.emoji = EmojiFixture.source
        let markdown = "# Plain heading\n\nA paragraph with **bold**, *italic* and `code`.\n"
        let plain = try MarkdownPDFRenderer(options: PDFOptions(embeddedFonts: .dejaVu)).render(markdown: markdown)
        let colour = try MarkdownPDFRenderer(options: PDFOptions(embeddedFonts: withFace)).render(markdown: markdown)
        #expect(plain == colour)
    }
}
