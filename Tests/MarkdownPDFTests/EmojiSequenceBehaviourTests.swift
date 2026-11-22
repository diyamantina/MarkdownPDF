import Foundation
@testable import MarkdownPDF
import Testing

/// What the engine does with an emoji sequence, MEASURED with the bundled colour face (and the basis of the "Known" paragraph of the 0.16.0 notes):
///
/// - a single emoji, and an emoji with its variation selector, are drawn in colour;
/// - a joined sequence (zero width joiner) falls apart into its single emoji, each drawn in colour, with no missing-glyph box;
/// - a skin-tone pair (the emoji and its modifier), a keycap (a digit, the variation selector and the enclosing keycap) and a flag (two regional
///   indicators) are not drawn yet: they stay text and show as the missing-glyph box (a `.notdef` glyph, code 0000), or are left out when
///   `PDFOptions.omitUndrawableEmoji` is on.
///
/// When sequences are drawn this test changes with it: that is its job.
@Suite("Emoji sequences")
struct EmojiSequenceBehaviourTests {
    /// The sample, the number of missing-glyph boxes it draws, and the number it draws with the option that leaves undrawable emoji out.
    private static let samples: [(name: String, text: String, boxes: Int, boxesWhenOmitted: Int)] = [
        ("single emoji", "\u{1F9E9}", 0, 0),
        ("emoji with a variation selector", "\u{2699}\u{FE0F}", 0, 0),
        ("joined family", "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", 0, 0),
        ("joined heart on fire", "\u{2764}\u{FE0F}\u{200D}\u{1F525}", 0, 0),
        ("skin tone pair", "\u{1F44D}\u{1F3FD}", 2, 0),
        // The enclosing keycap mark (U+20E3) is not an emoji code point, so the option does not leave it out: its box stays.
        ("keycap", "1\u{FE0F}\u{20E3}", 1, 1),
        ("flag", "\u{1F1ED}\u{1F1F7}", 2, 0),
    ]

    /// The glyph codes of every `Tj` string of the page content that are 0000, the `.notdef` of a font.
    private func boxes(in data: Data) -> Int {
        var count = 0
        let tokens = PDFInspector(data).text.split(whereSeparator: \.isWhitespace)
        for index in tokens.indices.dropLast() where tokens[index + 1] == "Tj" && tokens[index].hasPrefix("<") && tokens[index].hasSuffix(">") {
            let hex = Array(tokens[index].dropFirst().dropLast())
            for start in stride(from: 0, to: hex.count - 3, by: 4) where String(hex[start ..< start + 4]) == "0000" {
                count += 1
            }
        }
        return count
    }

    @Test("each kind of sequence draws what the notes say: the missing-glyph boxes it leaves, with and without the option that leaves them out")
    func boxesPerSequence() throws {
        for sample in Self.samples {
            let plain = try MarkdownPDFRenderer().render(markdown: "a \(sample.text) b\n")
            #expect(boxes(in: plain) == sample.boxes, Comment(rawValue: "\(sample.name): \(boxes(in: plain)) boxes, expected \(sample.boxes)"))
            let omitted = try MarkdownPDFRenderer(options: PDFOptions(omitUndrawableEmoji: true)).render(markdown: "a \(sample.text) b\n")
            #expect(boxes(in: omitted) == sample.boxesWhenOmitted, Comment(rawValue: "\(sample.name) omitted: \(boxes(in: omitted)) boxes"))
        }
    }

    /// MEASURED: the text read back keeps every emoji and letter of the sequence, but not the zero width joiner and not the variation selector
    /// of a joined or keycap sequence (each drawn emoji carries its own text), so a copied family reads as three emoji.
    @Test("every sequence reads back with its emoji and letters, drawn or not, without the joiner and the variation selector")
    func textIsKept() throws {
        func essential(_ text: String) -> [UInt32] {
            text.unicodeScalars.map(\.value).filter { $0 != 0x200D && $0 != 0xFE0F }
        }
        for sample in Self.samples {
            let data = try MarkdownPDFRenderer().render(markdown: "a \(sample.text) b\n")
            let words = try PDFDocumentReader(data: data).pages.flatMap(\.words).map(\.text).joined()
            let read = essential(words)
            let wanted = essential(sample.text)
            #expect(read.contains(wanted.first ?? 0), Comment(rawValue: "\(sample.name): \(read.map { String($0, radix: 16) })"))
            #expect(Array(read.dropFirst().dropLast()) == wanted, Comment(rawValue: "\(sample.name): \(read.map { String($0, radix: 16) }) is not a, \(wanted.map { String($0, radix: 16) }), b"))
        }
    }
}
