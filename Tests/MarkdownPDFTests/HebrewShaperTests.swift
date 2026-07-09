import Foundation
@testable import MarkdownPDF
import Testing

/// Witness that Hebrew niqqud are placed on their letters by GPOS, matching hb-shape.
/// The engine does not yet apply Hebrew GSUB presentation composition (vav+holam and
/// the like into one glyph), so its glyph set can carry a mark hb composed away; the
/// invariant verified here is that every mark hb positions, the engine positions at the
/// same offset. A system Hebrew font (Arial) provides the `hebr` GPOS; the tests skip
/// when it is absent.
@Suite("Hebrew shaper")
struct HebrewShaperTests {
    private static let arialPath = "/System/Library/Fonts/Supplemental/Arial.ttf"

    private static func arial() throws -> (data: Data, metadata: TrueTypeFontParser.Metadata)? {
        guard FileManager.default.fileExists(atPath: arialPath) else {
            return nil
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: arialPath))
        return try (data, TrueTypeFontParser().parse(data))
    }

    @Test("Detects pointed Hebrew and the font's mark-positioning capability")
    func detectsPointedHebrew() throws {
        #expect(HebrewShaper.containsPointedHebrew("\u{05E9}\u{05B8}\u{05DC}\u{05D5}\u{05DD}")) // שָׁלום (has qamats)
        #expect(!HebrewShaper.containsPointedHebrew("\u{05E9}\u{05DC}\u{05D5}\u{05DD}")) // שלום, no points
        guard let arial = try Self.arial() else {
            return
        }
        #expect(HebrewShaper(fontData: arial.data, metadata: arial.metadata).canPositionHebrewMarks)
    }

    @Test(
        "Niqqud are placed on their letters, matching hb-shape",
        .enabled(if: HarfBuzzOracle.isAvailable, "hb-shape not found on PATH"),
    )
    func niqqudMatchHarfBuzz() throws {
        guard let arial = try Self.arial() else {
            return
        }
        let shaper = HebrewShaper(fontData: arial.data, metadata: arial.metadata)
        let upem = Double(arial.metadata.head.unitsPerEm)
        for word in [
            "\u{05E9}\u{05B8}\u{05C1}\u{05DC}\u{05D5}\u{05B9}\u{05DD}", // שָׁלוֹם
            "\u{05D1}\u{05B0}\u{05BC}\u{05E8}\u{05B5}\u{05D0}\u{05E9}\u{05C1}\u{05B4}\u{05D9}\u{05EA}", // בְּרֵאשִׁית
            "\u{05D0}\u{05B1}\u{05DC}\u{05B9}\u{05D4}\u{05B4}\u{05D9}\u{05DD}",
        ] // אֱלֹהִים
        {
            let mapping = try shaper.shapedMapping(text: word, fontSize: upem)
            // A positioned mark is a glyph the shaper moved off the baseline.
            let engine = Set(mapping.glyphs
                .filter { $0.offset != .zero }
                .map { [Int($0.glyphID), Int($0.offset.x.rounded()), Int($0.offset.y.rounded())] })
            let oracle = try Set(HarfBuzzOracle.shapeWithPositions(word, fontPath: Self.arialPath, script: "hebr")
                .filter { $0.xOffset != 0 || $0.yOffset != 0 }
                .map { [Int($0.glyph), $0.xOffset, $0.yOffset] })
            // Every mark hb positions, the engine positions identically.
            #expect(oracle.isSubset(of: engine), "\(word): hb marks \(oracle) not all in engine \(engine)")
            #expect(!oracle.isEmpty, "\(word) should have positioned marks")
        }
    }

    @Test("A pointed Hebrew run renders with the niqqud recoverable via ToUnicode")
    func rendersWithToUnicode() throws {
        guard let arial = try Self.arial() else {
            return
        }
        let options = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: arial.data, baseName: "Arial"),
        ))
        let word = "\u{05E9}\u{05B8}\u{05C1}\u{05DC}\u{05D5}\u{05B9}\u{05DD}" // שָׁלוֹם
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: word)
        let inspector = PDFInspector(pdf)
        #expect(inspector.text.contains("/ToUnicode"))
        for scalar in word.unicodeScalars {
            #expect(inspector.text.uppercased().contains(String(format: "%04X", scalar.value)), "ToUnicode missing U+\(String(scalar.value, radix: 16))")
        }
    }
}
