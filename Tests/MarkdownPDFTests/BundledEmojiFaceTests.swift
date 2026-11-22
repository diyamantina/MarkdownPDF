import Foundation
@testable import MarkdownPDF
import Testing

/// Facts about the bundled colour emoji face that the drawing relies on, MEASURED over every emoji code point it can draw.
///
/// The invisible base glyph of a drawn emoji uses the glyph id as its character code and the emoji's code point as its `/ToUnicode` value, so two
/// different code points that the face maps to the SAME glyph would give one code two values and abort the render. The bundled face has none; a face
/// of the caller's is not checked here.
@Suite("The bundled emoji face")
struct BundledEmojiFaceTests {
    /// Every code point the segmenter treats as an emoji of the first planes (the symbols and pictographs) that the face draws, with its character code.
    private func drawnEmoji() throws -> [(scalar: Unicode.Scalar, code: UInt16)] {
        let face = try #require(BundledFonts.colorEmoji)
        var drawn: [(Unicode.Scalar, UInt16)] = []
        for value in UInt32(0xAA) ... UInt32(0x1FAFF) {
            guard let scalar = Unicode.Scalar(value), scalar.properties.isEmoji else { continue }
            let cluster = EmojiSegmenter.Cluster(scalars: [scalar], base: scalar)
            guard let drawing = face.drawing(of: cluster, fontSize: 10),
                  let code = drawing.base.clusters.first?.glyphs.first?.pdfCharacterCode
            else { continue }
            drawn.append((scalar, code))
        }
        return drawn
    }

    @Test("the face draws a few thousand emoji, and no two code points share a character code")
    func noSharedCodes() throws {
        let drawn = try drawnEmoji()
        #expect(drawn.count > 1000, "only \(drawn.count) emoji are drawn")
        var byCode: [UInt16: Unicode.Scalar] = [:]
        for (scalar, code) in drawn {
            if let other = byCode[code] {
                Issue.record("U+\(String(scalar.value, radix: 16)) and U+\(String(other.value, radix: 16)) share the character code \(code)")
            }
            byCode[code] = scalar
        }
    }

    /// MEASURED: 15 of the 1063 entries of the bundled palette have an alpha below 255 (shadows and highlights in black, white and brown shades, alpha 38 to
    /// 230). Dropping the alpha would paint them opaque; the drawing fills them with it (see `EmojiAlphaTests`).
    @Test("MEASURED: 15 colours of the bundled palette are translucent, none fully transparent")
    func paletteTranslucency() throws {
        let face = try #require(BundledFonts.twemoji)
        let metadata = try TrueTypeFontParser().parse(face.data, faceIndex: face.faceIndex, preferFullUnicodeCMap: true)
        let record = try #require(metadata.table(named: "CPAL"))
        let bytes = [UInt8](face.data)
        let table = try TrueTypeByteReader(table: "CPAL", bytes: bytes).bytes(in: Int(record.offset) ..< Int(record.offset) + Int(record.length))
        let palette = try CPALTable(bytes: table)
        var alphas: [UInt8] = []
        for index in 0 ..< palette.paletteCount {
            for entry in 0 ..< palette.entryCount {
                if let color = palette.color(palette: index, entry: UInt16(entry)), color.alpha != 255 {
                    alphas.append(color.alpha)
                }
            }
        }
        // MEASURED: the Twemoji 17.0.3 build has 1141 palette entries (the face of 0.17.0, Twemoji Mozilla, had 1063).
        #expect(palette.entryCount == 1141)
        #expect(alphas.count == 15, "\(alphas.count) translucent entries")
        #expect(alphas.min() == 38 && alphas.max() == 230, "alphas \(alphas.min() ?? 0) to \(alphas.max() ?? 0)")
    }

    @Test("a document that holds every one of them renders, with no conflicting text mapping")
    func allInOneDocument() throws {
        let all = try drawnEmoji().map { String(Character($0.scalar)) }.joined(separator: " ")
        let data = try MarkdownPDFRenderer().render(markdown: all + "\n")
        #expect(!data.isEmpty)
        let text = try PDFDocumentReader(data: data).pages.flatMap(\.words).map(\.text).joined()
        #expect(text.unicodeScalars.count >= 1000, "\(text.unicodeScalars.count) code points read back")
    }
}
