import Foundation
@testable import MarkdownPDF
import Testing

/// What the engine does with an emoji sequence, MEASURED with the bundled colour face (and the basis of the "Known" paragraph of the 0.16.0 notes):
///
/// - a single emoji, and an emoji with its variation selector, are drawn in colour;
/// - a sequence (a joined one, a skin-tone pair, a keycap, a flag, a subdivision flag) is drawn as ONE glyph of the colour face: the face's own
///   `ccmp` substitution turns the glyphs of the scalars into the glyph of the sequence (0.17.0; before it a joined sequence fell apart into its
///   emoji and the others showed the missing-glyph box).
///
/// The text read back from the page is the whole sequence, with its joiner and its selector, exactly.
@Suite("Emoji sequences")
struct EmojiSequenceBehaviourTests {
    /// The sample, the number of missing-glyph boxes it draws, and the number it draws with the option that leaves undrawable emoji out.
    private static let samples: [(name: String, text: String, boxes: Int, boxesWhenOmitted: Int)] = [
        ("single emoji", "\u{1F9E9}", 0, 0),
        ("emoji with a variation selector", "\u{2699}\u{FE0F}", 0, 0),
        ("joined family", "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", 0, 0),
        ("joined heart on fire", "\u{2764}\u{FE0F}\u{200D}\u{1F525}", 0, 0),
        ("skin tone pair", "\u{1F44D}\u{1F3FD}", 0, 0),
        ("keycap", "1\u{FE0F}\u{20E3}", 0, 0),
        ("flag", "\u{1F1ED}\u{1F1F7}", 0, 0),
        ("subdivision flag (tag sequence)", "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}", 0, 0),
        ("joined rainbow flag", "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}", 0, 0),
        // The spellings without the variation selector (unicode.org lists them as unqualified and minimally qualified): the same picture.
        ("keycap without the selector", "1\u{20E3}", 0, 0),
        ("heart on fire without the selector", "\u{2764}\u{200D}\u{1F525}", 0, 0),
        ("eye in speech bubble, selector after the eye only", "\u{1F441}\u{FE0F}\u{200D}\u{1F5E8}", 0, 0),
        ("eye in speech bubble, no selector", "\u{1F441}\u{200D}\u{1F5E8}", 0, 0),
        ("man with beard without the selector", "\u{1F9D4}\u{200D}\u{2642}", 0, 0),
        // A text-default emoji written bare that no text face has: drawn from the colour face. (The bare heart is in the text face and stays text.)
        ("bare desktop computer, in no text face", "\u{1F5A5}", 0, 0),
        ("bare hole, in no text face", "\u{1F573}", 0, 0),
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

    @Test("a sequence is one drawn glyph, and the text read back is the whole sequence, scalar for scalar, joiner and selector included")
    func sequenceTextExact() throws {
        for sample in Self.samples {
            let data = try MarkdownPDFRenderer().render(markdown: "a \(sample.text) b\n")
            let words = try PDFDocumentReader(data: data).pages.flatMap(\.words).map(\.text).joined(separator: " ")
            #expect(
                words.contains(sample.text) || words.unicodeScalars.map(\.value).contains(sample.text.unicodeScalars.first?.value ?? 0),
                Comment(rawValue: "\(sample.name): \(words)"),
            )
            let wanted = sample.text.unicodeScalars.map(\.value)
            let read = words.unicodeScalars.map(\.value)
            let found = read.indices.contains { index in index + wanted.count <= read.count && Array(read[index ..< index + wanted.count]) == wanted }
            #expect(found, Comment(rawValue: "\(sample.name): the sequence is not in the text read back: \(read.map { String($0, radix: 16) })"))
        }
    }

    /// The text read back keeps every emoji and letter of the sequence (the weaker form of the test above, joiner and selector set aside).
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
            #expect(
                Array(read.dropFirst().dropLast()) == wanted,
                Comment(rawValue: "\(sample.name): \(read.map { String($0, radix: 16) }) is not a, \(wanted.map { String($0, radix: 16) }), b"),
            )
        }
    }
}
