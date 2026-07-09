import Foundation
@testable import MarkdownPDF
import Testing

/// Witness that the GDEF reader classifies real glyphs as marks or bases, the fact the
/// contextual and (future) positioning passes rely on to honor `IgnoreMarks` and to
/// place marks. Ground truth is the Noto Naskh Arabic fixture's own GDEF table.
@Suite("GDEF table")
struct GDEFTableTests {
    private func fixture() throws -> (data: Data, metadata: TrueTypeFontParser.Metadata) {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/NotoNaskhArabic-Regular.ttf")
        let data = try Data(contentsOf: url)
        return try (data, TrueTypeFontParser().parse(data))
    }

    private func gdefRange(_ metadata: TrueTypeFontParser.Metadata, in _: Data) throws -> Range<Int> {
        let record = try #require(metadata.table(named: "GDEF"))
        let start = Int(record.offset)
        return start ..< (start + Int(record.length))
    }

    private func glyphID(for scalar: UnicodeScalar, data: Data, metadata: TrueTypeFontParser.Metadata) throws -> UInt16 {
        let mapper = TrueTypeGlyphMapper(data: data, metadata: metadata, missingGlyphPolicy: .useNotdef)
        return try #require(mapper.map(text: String(scalar), fontSize: 1).glyphs.first?.glyphID)
    }

    @Test("Classifies Arabic harakat as marks and letters as non-marks")
    func classifiesMarksAndBases() throws {
        let (data, metadata) = try fixture()
        let gdef = try #require(try GDEFTable(fontData: data, gdefTableRange: gdefRange(metadata, in: data)))

        // Harakat (combining vowel marks) are GDEF class 3.
        for scalar in [UnicodeScalar(0x064E), UnicodeScalar(0x0650), UnicodeScalar(0x0651)] { // fatha, kasra, shadda
            let mark = try #require(scalar)
            let glyph = try glyphID(for: mark, data: data, metadata: metadata)
            #expect(gdef.isMark(glyph), "U+\(String(mark.value, radix: 16)) should be a mark")
        }
        // Letters are bases, not marks.
        for scalar in [UnicodeScalar(0x0645), UnicodeScalar(0x0628), UnicodeScalar(0x0627)] { // meem, beh, alef
            let letter = try #require(scalar)
            let glyph = try glyphID(for: letter, data: data, metadata: metadata)
            #expect(!gdef.isMark(glyph), "U+\(String(letter.value, radix: 16)) should not be a mark")
        }
    }

    @Test("A font without GDEF yields a nil reader")
    func nilWhenNoGDEF() throws {
        let data = try fixture().data
        #expect(try GDEFTable(fontData: data, gdefTableRange: nil) == nil)
    }
}
