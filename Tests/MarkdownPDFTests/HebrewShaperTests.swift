import Foundation
@testable import MarkdownPDF
import Testing

/// Witness that Hebrew is composed and positioned like the reference shaper: the
/// letter-modifying marks are reordered next to their consonant, GSUB `ccmp` composes
/// the presentation forms (shin/sin dot, letter+dagesh), and GPOS places the niqqud.
/// A system Hebrew font (Arial) provides the `hebr` GSUB/GPOS; the tests skip when it
/// is absent.
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
        "Composed and positioned Hebrew matches hb-shape glyph for glyph",
        .enabled(if: HarfBuzzOracle.isAvailable, "hb-shape not found on PATH"),
        arguments: [
            "\u{05E9}\u{05B8}\u{05C1}\u{05DC}\u{05D5}\u{05B9}\u{05DD}", // שָׁלוֹם (shin dot composes)
            "\u{05E9}\u{05B8}\u{05C2}\u{05E8}\u{05B8}\u{05D4}", // שָׂרָה (sin dot composes)
            "\u{05D1}\u{05B7}\u{05BC}\u{05D9}\u{05B4}\u{05EA}", // בַּיִת (bet+dagesh composes)
            "\u{05D1}\u{05B0}\u{05BC}\u{05E8}\u{05B5}\u{05D0}\u{05E9}\u{05C1}\u{05B4}\u{05D9}\u{05EA}", // בְּרֵאשִׁית
            "\u{05D0}\u{05B1}\u{05DC}\u{05B9}\u{05D4}\u{05B4}\u{05D9}\u{05DD}", // אֱלֹהִים
            "\u{05DE}\u{05B6}\u{05DC}\u{05B6}\u{05DA}\u{05B0}", // מֶלֶךְ (final kaf)
        ],
    )
    func composedHebrewMatchesHarfBuzz(_ word: String) throws {
        guard let arial = try Self.arial() else {
            return
        }
        let shaper = HebrewShaper(fontData: arial.data, metadata: arial.metadata)
        let upem = Double(arial.metadata.head.unitsPerEm)
        let mapping = try shaper.shapedMapping(text: word, fontSize: upem)
        // Full parity: the same positioned glyphs (glyph + offset in font units), as a
        // sorted multiset since within-cluster order is a reconstruction detail. (Holam
        // directly on a consonant needs GPOS type-8 contextual positioning the engine
        // does not yet apply; these words use holam only on vav, which composes.)
        let engine = mapping.glyphs
            .map { [Int($0.glyphID), Int($0.offset.x.rounded()), Int($0.offset.y.rounded())] }
            .sorted { $0.lexicographicallyPrecedes($1) }
        let reference = try HarfBuzzOracle.shapeWithPositions(word, fontPath: Self.arialPath, script: "hebr")
            .map { [Int($0.glyph), $0.xOffset, $0.yOffset] }
            .sorted { $0.lexicographicallyPrecedes($1) }
        #expect(engine == reference, "\(word): engine \(engine) vs hb \(reference)")
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

    @Test("A composed cluster carries an /ActualText override so extraction is base-first")
    func composedClusterWrapsActualText() throws {
        guard let arial = try Self.arial() else {
            return
        }
        let options = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: arial.data, baseName: "Arial"),
        ))
        // A composed base+mark cluster (bet + dagesh) drawn RTL in visual order would
        // extract mark-before-base; the run is wrapped in an /ActualText span so a text
        // extractor recovers the letter before its point.
        let composed = try MarkdownPDFRenderer(options: options).render(markdown: "\u{05D1}\u{05BC}") // בּ
        let composedText = PDFInspector(composed).text
        #expect(composedText.contains("/ActualText"))
        // The override must carry the scalars in visual (reversed) order: FEFF BOM then
        // dagesh U+05BC then bet U+05D1. Every ActualText-honoring extractor re-applies
        // bidi to the replacement text, so logical order (bet before dagesh) extracts fully
        // reversed; only visual order round-trips to base-first. Pinning the exact hex keeps
        // the reversal direction under test, not just the presence of the span.
        #expect(composedText.uppercased().contains("FEFF05BC05D1"), "ActualText must be visual-order UTF-16BE (dagesh, bet)")
        #expect(!composedText.uppercased().contains("FEFF05D105BC"), "ActualText must not be logical order (bet, dagesh)")
        // Plain Hebrew (no composition) needs no override.
        let plain = try MarkdownPDFRenderer(options: options).render(markdown: "\u{05E9}\u{05DC}\u{05D5}\u{05DD}") // שלום
        #expect(!PDFInspector(plain).text.contains("/ActualText"))
    }

    @Test("Detects when a mapping needs the ActualText override")
    func detectsActualTextNeed() throws {
        guard let arial = try Self.arial() else {
            return
        }
        let shaper = HebrewShaper(fontData: arial.data, metadata: arial.metadata)
        // bet + dagesh composes to one glyph over two scalars starting with a base.
        #expect(try shaper.shapedMapping(text: "\u{05D1}\u{05BC}", fontSize: 12).needsActualTextOverride)
        // Plain shin has no multi-scalar composed cluster.
        #expect(try !shaper.shapedMapping(text: "\u{05E9}", fontSize: 12).needsActualTextOverride)
    }
}
