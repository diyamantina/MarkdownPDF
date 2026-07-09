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
            // Two below-marks, both attached to the base (Noto keeps them separate):
            // the wavy hamza does not mkmk-stack onto the kasra in this font.
            "\u{0628}\u{0650}\u{065F}", // beh + kasra + wavy hamza below
            // A genuine mkmk stack: two superscript alefs, the second attached to the
            // first (its offset builds on the first's), exercising the accumulation in
            // the mark-to-mark path. hb stacks them at @354,39 then @352,279.
            "\u{0628}\u{0670}\u{0670}", // beh + superscript alef + superscript alef
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

    @Test("A vocalized run renders through the positioned path with recoverable text")
    func vocalizedRunUsesPositionedPath() throws {
        let font = try Self.notoFont()
        let options = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: font.data, baseName: "Noto"),
        ))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "\u{0643}\u{064E}\u{062A}\u{064E}\u{0628}\u{064E}") // كَتَبَ
        let inspector = PDFInspector(pdf)
        // The positioned path shows each glyph in its own operator (one `Tj` per glyph,
        // each preceded by a `Td` move), so a vocalized run has several `Tj`, unlike the
        // single-operator baseline path.
        let textStream = try #require(inspector.streams.first { $0.body.contains(" Tj") })
        #expect(textStream.body.components(separatedBy: " Tj").count - 1 > 1)
        // The vowels are still recoverable: mark positioning does not disturb ToUnicode.
        #expect(inspector.text.contains("/ToUnicode"))
        for scalar in "\u{0643}\u{064E}\u{062A}\u{064E}\u{0628}\u{064E}".unicodeScalars {
            #expect(inspector.text.uppercased().contains(String(format: "%04X", scalar.value)))
        }
    }

    @Test("An unvocalized run keeps the single-show baseline path")
    func unvocalizedRunKeepsSingleShow() throws {
        let font = try Self.notoFont()
        let options = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: font.data, baseName: "Noto"),
        ))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}") // مرحبا, no marks
        // No mark offsets, so the run is emitted in one showCIDText: exactly one Tj in
        // the page content, the byte-identical pre-positioning path.
        let inspector = PDFInspector(pdf)
        let contentStreams = inspector.streams.filter { $0.body.contains(" Tj") }
        #expect(contentStreams.count == 1)
        #expect(contentStreams.allSatisfy { $0.body.components(separatedBy: " Tj").count - 1 == 1 })
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
