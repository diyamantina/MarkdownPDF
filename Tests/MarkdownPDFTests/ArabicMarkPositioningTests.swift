import Foundation
@testable import MarkdownPDF
import Testing

/// Differential witness for GPOS mark positioning: the shaper's per-glyph placement
/// offsets (font units) must match the positions hb-shape reports for the same
/// vocalized text, glyph for glyph.
@Suite("Arabic mark positioning")
struct ArabicMarkPositioningTests {
    private static func notoFont() throws -> (data: Data, metadata: TrueTypeFontParser.Metadata, path: String) {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/NotoNaskhArabic-Regular.ttf")
        let data = try Data(contentsOf: url)
        return try (data, TrueTypeFontParser().parse(data), url.path)
    }

    @Test(
        "Shaped mark offsets match hb-shape for vocalized Arabic",
        .enabled(if: HarfBuzzOracle.isAvailable, "hb-shape not found on PATH"),
        arguments: [
            "\u{0628}\u{064E}", // بَ  beh + fatha
            "\u{0628}\u{0650}", // بِ  beh + kasra
            "\u{0628}\u{064F}", // بُ  beh + damma
            "\u{0645}\u{064E}", // مَ  meem + fatha
            "\u{0643}\u{064E}\u{062A}\u{064E}\u{0628}\u{064E}", // كَتَبَ kataba
            "\u{0628}\u{0650}\u{0633}\u{0645}", // بِسم
            // Two stacked below-marks: the second attaches to the first via mkmk
            // (Noto keeps these two separate rather than composing them), exercising
            // the mark-to-mark stacking path.
            "\u{0628}\u{0650}\u{065F}", // beh + kasra + wavy hamza below
        ],
    )
    func shapedOffsetsMatchHarfBuzz(_ word: String) throws {
        let font = try Self.notoFont()
        let shaper = ArabicShaper(fontData: font.data, metadata: font.metadata)
        let shaped = try shaper.shape(word)
        let oracle = try HarfBuzzOracle.shapeWithPositions(word, fontPath: font.path)

        // Same glyphs, logical order.
        #expect(shaped.map(\.glyphID) == oracle.map(\.glyph), "glyph mismatch for \(word)")
        // Same placement offset on every glyph (marks moved, bases at zero).
        let engineOffsets = shaped.map { ($0.xOffset, $0.yOffset) }
        let oracleOffsets = oracle.map { ($0.xOffset, $0.yOffset) }
        #expect(
            engineOffsets.map { [$0.0, $0.1] } == oracleOffsets.map { [$0.0, $0.1] },
            "offset mismatch for \(word): engine \(engineOffsets) vs hb \(oracleOffsets)",
        )
    }

    @Test("A base letter carries no placement offset")
    func baseHasNoOffset() throws {
        let font = try Self.notoFont()
        let shaper = ArabicShaper(fontData: font.data, metadata: font.metadata)
        let shaped = try shaper.shape("\u{0628}\u{064E}") // beh + fatha
        // beh (base) is first in logical order and unmoved; the fatha carries the
        // offset, so at least one glyph is placed.
        #expect(shaped.first?.xOffset == 0)
        #expect(shaped.first?.yOffset == 0)
        #expect(shaped.contains { $0.xOffset != 0 || $0.yOffset != 0 })
    }
}
