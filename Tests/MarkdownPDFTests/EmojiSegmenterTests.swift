import Foundation
@testable import MarkdownPDF
import Testing

/// Which grapheme clusters are colour emoji, and how a text splits around them. The expectations are written out by hand from the Unicode
/// emoji data: default emoji presentation, or an emoji-capable scalar with the variation selector U+FE0F.
@Suite("Emoji segmentation")
struct EmojiSegmenterTests {
    private func kinds(_ text: String) -> [String] {
        EmojiSegmenter.segments(of: text).map { segment in
            switch segment {
            case let .text(text): "text:\(text)"
            case let .emoji(cluster): "emoji:" + cluster.scalars.map { String($0.value, radix: 16, uppercase: true) }.joined(separator: "+")
            }
        }
    }

    @Test("an emoji in the middle of a sentence splits it in three, the spaces staying in the text")
    func middle() {
        #expect(kinds("Hello \u{1F680} world") == ["text:Hello ", "emoji:1F680", "text: world"])
    }

    @Test("adjacent emoji are separate clusters and plain text is one segment")
    func adjacent() {
        #expect(kinds("\u{1F680}\u{1F680}ab") == ["emoji:1F680", "emoji:1F680", "text:ab"])
        #expect(kinds("plain words") == ["text:plain words"])
        #expect(kinds("") == [])
    }

    @Test("a default-emoji BMP scalar is an emoji, a text-default scalar is text until U+FE0F, and U+FE0E asks for text", arguments: [
        ("\u{2705}", ["emoji:2705"]), ("\u{274C}", ["emoji:274C"]), ("\u{26A1}", ["emoji:26A1"]),
        ("\u{2194}", ["text:\u{2194}"]), ("\u{2194}\u{FE0F}", ["emoji:2194+FE0F"]),
        ("\u{2699}", ["text:\u{2699}"]), ("\u{2699}\u{FE0F}", ["emoji:2699+FE0F"]), ("\u{2699}\u{FE0E}", ["text:\u{2699}\u{FE0E}"]),
        ("\u{1F5A5}\u{FE0F}", ["emoji:1F5A5+FE0F"]), ("\u{26A0}\u{FE0F}", ["emoji:26A0+FE0F"]),
        ("\u{2B06}\u{FE0F}", ["emoji:2B06+FE0F"]), ("\u{2B07}\u{FE0F}", ["emoji:2B07+FE0F"]),
    ] as [(String, [String])])
    func presentation(text: String, expected: [String]) {
        #expect(kinds(text) == expected)
    }

    @Test("every astral emoji of the published posts is an emoji cluster", arguments: [
        0x1F310, 0x1F449, 0x1F4A1, 0x1F4AC, 0x1F4C1, 0x1F4C2, 0x1F4CA, 0x1F4DA, 0x1F4E6, 0x1F501, 0x1F50D, 0x1F510, 0x1F605, 0x1F680, 0x1F9E0, 0x1F9E9,
        0x1F9EA, 0x1F9ED, 0x1F9F1,
    ] as [Int])
    func census(value: Int) throws {
        let scalar = try #require(Unicode.Scalar(UInt32(value)))
        #expect(EmojiSegmenter.cluster(of: Character(scalar))?.base == scalar)
    }

    @Test("a sequence is one cluster of all its scalars: a flag, a keycap, a skin tone, a joined family; the colour face decides whether it can draw it", arguments: [
        "\u{1F1ED}\u{1F1F7}", "1\u{FE0F}\u{20E3}", "\u{1F44D}\u{1F3FD}", "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}",
    ])
    func sequences(text: String) {
        let cluster = EmojiSegmenter.cluster(of: Character(text))
        #expect(cluster?.scalars == Array(text.unicodeScalars), "the cluster must hold every scalar of the sequence")
        #expect(EmojiSegmenter.containsColorEmoji(text))
    }

    @Test("a multi-scalar cluster that is not an emoji sequence stays text: a letter with a combining mark, two scalars one of which is not an emoji")
    func notSequences() {
        #expect(EmojiSegmenter.cluster(of: Character("e\u{0301}")) == nil)
        #expect(EmojiSegmenter.cluster(of: Character("a\u{20E3}")) == nil)
        #expect(!EmojiSegmenter.containsColorEmoji("e\u{0301} text"))
    }

    @Test("ASCII, digits, # and * are never emoji, even with U+FE0F")
    func ascii() {
        #expect(!EmojiSegmenter.containsColorEmoji("Plain 123 # * text"))
        #expect(EmojiSegmenter.cluster(of: Character("#\u{FE0F}")) == nil)
        #expect(EmojiSegmenter.cluster(of: Character("1\u{FE0F}")) == nil)
    }
}
