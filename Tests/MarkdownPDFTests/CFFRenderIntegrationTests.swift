import Foundation
@testable import MarkdownPDF
import Testing

/// End-to-end witness for #49: an OpenType/CFF font (PostScript outlines) embeds and
/// renders. A CID-keyed CFF (the shape of CJK system fonts) goes out as a
/// `CIDFontType0` descendant with a `CIDFontType0C` `FontFile3`, addressing glyphs by
/// the CID its charset assigns; a name-keyed CFF goes out as `CIDFontType0` with an
/// `OpenType` `FontFile3`. The glyph raster, the `/W` width geometry, and `/ToUnicode`
/// extraction are all checked by the shared visual witness. Tests that need a system
/// CFF font skip when it is absent (as no CFF font can be committed to a public repo).
@Suite("CFF render integration")
struct CFFRenderIntegrationTests {
    /// A CID-keyed CFF collection face: Hiragino Sans GB (Adobe-GB1). CJK fonts ship
    /// this way, so it exercises the primary CIDFontType0C path.
    private static let cidKeyedCFFPath = "/System/Library/Fonts/Hiragino Sans GB.ttc"
    /// A single-face name-keyed (non-CID) CFF: STIX General (SIL OFL), exercising the
    /// OpenType FontFile3 path.
    private static let nameKeyedCFFPath = "/System/Library/Fonts/Supplemental/STIXGeneral.otf"

    private func fontData(_ path: String) -> Data? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    @Test("A CID-keyed CFF is recognized by the parser and addresses glyphs by CID")
    func parsesCIDKeyedOpenTypeFont() throws {
        guard let data = fontData(Self.cidKeyedCFFPath) else {
            return
        }
        let metadata = try TrueTypeFontParser().parse(data, faceIndex: 0)
        let cff = try #require(metadata.cff, "expected a parsed CFF table for an OTTO font")
        #expect(cff.isCIDKeyed)
        #expect(cff.glyphCount == Int(metadata.maxp.numGlyphs))
        // For a CID-keyed font the composite CID is the charset value, not the glyph
        // id; glyph 0 (.notdef) is always CID 0.
        #expect(metadata.compositeCID(forGlyph: 0) == 0)
        let someGlyph = UInt16(min(cff.charset.count - 1, 100))
        #expect(metadata.compositeCID(forGlyph: someGlyph) == cff.charset[Int(someGlyph)])
    }

    @Test("A glyf font stays name-agnostic of CFF: composite CID is the glyph id")
    func glyfFontHasNoCFF() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/NotoNaskhArabic-Regular.ttf")
        let metadata = try TrueTypeFontParser().parse(Data(contentsOf: url))
        #expect(metadata.cff == nil)
        #expect(metadata.compositeCID(forGlyph: 42) == 42)
    }

    @Test("A CJK CID-keyed CFF renders: CIDFontType0C FontFile3, real glyphs, ToUnicode")
    func cidKeyedCFFRendersCJK() throws {
        guard let data = fontData(Self.cidKeyedCFFPath) else {
            return
        }
        let options = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: data, baseName: "HiraginoSansGB", faceIndex: 0),
        ))
        // A heading plus a fuller paragraph, so the raster carries enough ink for the
        // shared witness's density floor while every distinct character is checked
        // below through extraction.
        let heading = "# \u{6F22}\u{5B57} \u{65E5}\u{672C}\u{8A9E} \u{4E2D}\u{6587}\n\n" // 漢字 日本語 中文
        let body = String(repeating: "\u{6F22}\u{5B57}\u{8868}\u{793A}\u{30C6}\u{30B9}\u{30C8}\u{65E5}\u{672C}\u{8A9E}\u{4E2D}\u{6587}\u{30AB}\u{30CA} ", count: 8)
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: heading + body)

        try assertEmbeddedFontVisualWitness(
            pdf,
            name: "cff-cid-keyed-cjk",
            expectedSubstrings: ["\u{6F22}\u{5B57}", "\u{65E5}\u{672C}\u{8A9E}", "\u{4E2D}\u{6587}"],
        )

        let inspector = PDFInspector(pdf)
        #expect(inspector.text.contains("/CIDFontType0C"))
        #expect(inspector.text.contains("/CIDFontType0"))
        #expect(inspector.text.contains("/FontFile3"))
        #expect(inspector.text.contains("/ToUnicode"))
        // The CFF path must not emit a CIDToGIDMap: a CIDFontType0's mapping lives in
        // the embedded CFF charset.
        #expect(!inspector.text.contains("/CIDToGIDMap"))
    }

    @Test("A name-keyed CFF renders through the OpenType FontFile3 path")
    func nameKeyedCFFRendersLatin() throws {
        guard let data = fontData(Self.nameKeyedCFFPath) else {
            return
        }
        let options = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: data, baseName: "STIXGeneral"),
        ))
        let pdf = try MarkdownPDFRenderer(options: options)
            .render(markdown: "The quick brown fox jumps over 12345.")

        try assertEmbeddedFontVisualWitness(
            pdf,
            name: "cff-name-keyed-latin",
            expectedSubstrings: ["quick", "brown", "12345"],
            minWords: 5,
        )

        let inspector = PDFInspector(pdf)
        #expect(inspector.text.contains("/OpenType"))
        #expect(inspector.text.contains("/CIDFontType0"))
        #expect(inspector.text.contains("/FontFile3"))
    }

    @Test("A glyf font still embeds as CIDFontType2 / FontFile2, not the CFF path")
    func glyfFontStillEmbedsAsCIDFontType2() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/NotoNaskhArabic-Regular.ttf")
        let options = try PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: Data(contentsOf: url), baseName: "Noto"),
        ))
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "\u{0646}\u{0639}\u{0645}") // نعم
        let inspector = PDFInspector(pdf)
        #expect(inspector.text.contains("/CIDFontType2"))
        #expect(inspector.text.contains("/FontFile2"))
        #expect(!inspector.text.contains("/CIDFontType0"))
        #expect(!inspector.text.contains("/FontFile3"))
    }
}
