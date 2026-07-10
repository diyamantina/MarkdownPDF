import Foundation
@testable import MarkdownPDF
import Testing

/// Vertical (top-to-bottom) CJK shaping: the `vert` feature turns brackets and the
/// ideographic comma and full stop into their vertical forms, ideographs are unchanged,
/// and each glyph carries its `vmtx` advance. The expected glyph ids and advances are the
/// output of CoreText's vertical typesetter for the same font (Hiragino Sans GB, W3),
/// which this reproduces.
@Suite("Vertical text shaper")
struct VerticalTextShaperTests {
    private static let path = "/System/Library/Fonts/Hiragino Sans GB.ttc"

    private static func shaper() throws -> VerticalTextShaper? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let metadata = try TrueTypeFontParser().parse(data, faceIndex: 0)
        return VerticalTextShaper(fontData: data, metadata: metadata)
    }

    @Test("Applies vertical forms and vertical advances, matching CoreText")
    func shapesVertically() throws {
        guard let shaper = try Self.shaper() else {
            return
        }
        #expect(shaper.hasVerticalMetrics)
        // あ。「い」, whose CoreText vertical typesetting gives these glyph ids.
        let glyphs = try shaper.shape("\u{3042}\u{3002}\u{300C}\u{3044}\u{300D}", fontSize: 1000)
        #expect(glyphs.map(\.glyphID) == [357, 574, 588, 359, 589])
        // The ideographic full stop and both brackets are substituted to a different glyph
        // than their horizontal form; the two hiragana are not.
        #expect(glyphs[1].glyphID != 98) // 。 is not its horizontal glyph
        #expect(glyphs[2].glyphID != 119) // 「
        #expect(glyphs[4].glyphID != 120) // 」
        // Every glyph advances one em down the line.
        #expect(glyphs.allSatisfy { Int($0.advance.rounded()) == 1000 })
        // The source scalars are preserved in order for extraction.
        #expect(glyphs.map(\.scalar.value) == [0x3042, 0x3002, 0x300C, 0x3044, 0x300D])
    }

    @Test("A run of ideographs is unchanged by the vertical forms feature")
    func ideographsStayUpright() throws {
        guard let shaper = try Self.shaper() else {
            return
        }
        let vertical = try shaper.shape("\u{6F22}\u{5B57}", fontSize: 1000) // 漢字
        let data = try Data(contentsOf: URL(fileURLWithPath: Self.path))
        let metadata = try TrueTypeFontParser().parse(data, faceIndex: 0)
        let mapper = TrueTypeGlyphMapper(data: data, metadata: metadata, missingGlyphPolicy: .useNotdef)
        let horizontal = try mapper.map(text: "\u{6F22}\u{5B57}", fontSize: 1000).glyphs.map(\.glyphID)
        // Ideographs have no vertical variant, so vertical shaping keeps the same glyphs.
        #expect(vertical.map(\.glyphID) == horizontal)
    }
}
