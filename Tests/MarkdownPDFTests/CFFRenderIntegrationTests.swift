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
        // Exercise the charset on a glyph it maps to a DIFFERENT id. Hiragino's charset
        // is identity for the low glyphs and diverges higher up; an identity-only
        // witness cannot catch a mapping that silently drops to `return glyphID`.
        let remapped = try #require(
            cff.charset.indices.first { cff.charset[$0] != UInt16($0) },
            "expected a glyph whose charset CID differs from its glyph id",
        )
        #expect(cff.charset[remapped] != UInt16(remapped))
        #expect(metadata.compositeCID(forGlyph: UInt16(remapped)) == cff.charset[remapped])
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

        // End-to-end witness that the writer draws the charset CID, not the glyph id:
        // find a character the charset remaps (CID != glyph id), render it alone, and
        // confirm the drawn CID is the charset value. This fails if `compositeCID` is
        // bypassed, so it protects the exact mapping this feature exists for.
        let metadata = try TrueTypeFontParser().parse(data, faceIndex: 0)
        let mapper = TrueTypeGlyphMapper(data: data, metadata: metadata, missingGlyphPolicy: .useNotdef)
        // Ranges that sit above Hiragino's identity boundary; the charset remaps these.
        let candidates = Array(0x9FA6 ... 0x9FFF) + Array(0x4DB6 ... 0x4DBF) + Array(0xFA0E ... 0xFA29)
        var remappedScalar: UnicodeScalar?
        var expectedCID: UInt16 = 0
        for value in candidates {
            guard let scalar = UnicodeScalar(value) else {
                continue
            }
            let glyphID = try mapper.map(text: String(scalar), fontSize: 10).glyphs.first?.glyphID ?? 0
            guard glyphID != 0 else {
                continue
            }
            let cid = metadata.compositeCID(forGlyph: glyphID)
            if cid != glyphID {
                remappedScalar = scalar
                expectedCID = cid
                break
            }
        }
        let scalar = try #require(remappedScalar, "expected a CJK char whose charset CID differs from its glyph id")
        let singleGlyphPDF = try MarkdownPDFRenderer(options: options).render(markdown: String(scalar))
        #expect(drawnCIDs(singleGlyphPDF) == [expectedCID], "the drawn CID must be the charset CID, not the glyph id")
    }

    @Test("A CID-keyed CFF embeds only the glyphs the document uses")
    func cidKeyedCFFSubsetsUsedGlyphs() throws {
        guard let data = fontData(Self.cidKeyedCFFPath) else {
            return
        }
        let options = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: data, baseName: "HiraginoSansGB", faceIndex: 0),
        ))
        // A handful of CJK characters, including two whose charstrings call subroutines
        // that consume operands their caller pushed (U+819B 膛, whose hint count would be
        // miscounted, and U+3B3B 㬻, which leaves a subroutine index on the stack across a
        // call). The whole Hiragino `CFF ` table is over ten megabytes; a subset of a dozen
        // glyphs is a few kilobytes, so the rendered PDF staying far below the whole-font
        // size is a robust witness that the subsetter ran, desubroutinized these glyphs
        // without aborting, and did not fall back to embedding the whole program.
        let pdf = try MarkdownPDFRenderer(options: options)
            .render(markdown: "\u{6F22}\u{5B57}\u{65E5}\u{672C}\u{8A9E}\u{4E2D}\u{6587}\u{819B}\u{3B3B}")
        #expect(pdf.count < 200_000, "expected a subset embed (\(pdf.count) bytes); the whole CFF is > 10 MB")
        #expect(PDFInspector(pdf).text.contains("/CIDFontType0C"))
    }

    @Test("Every glyph of a real CID-keyed CFF desubroutinizes without aborting")
    func desubroutinizesEveryGlyph() throws {
        guard let data = fontData(Self.cidKeyedCFFPath) else {
            return
        }
        let metadata = try TrueTypeFontParser().parse(data, faceIndex: 0)
        let record = try #require(metadata.table(named: "CFF "))
        let start = Int(record.offset)
        let end = start + Int(record.length)
        let program = try CFFFontProgram(bytes: [UInt8](data[start ..< end]))
        // The operand stack is shared across subroutine frames; a per-frame model miscounts
        // hints (silent corruption) or drops a subroutine index (a thrown abort). Exercising
        // every glyph guards both: any regression makes at least one glyph throw here.
        for glyphID in 0 ..< program.glyphCount {
            let fd = program.fdSelect[glyphID]
            let desubroutinizer = CFFCharstringDesubroutinizer(
                globalSubrs: program.globalSubrs,
                localSubrs: program.privateDicts[fd].localSubrs,
            )
            let output = try desubroutinizer.desubroutinize(program.charStrings[glyphID])
            #expect(!output.isEmpty, "glyph \(glyphID) desubroutinized to nothing")
        }
    }

    /// The CID codes drawn by `<hex> Tj` operators, in draw order (stream compression
    /// is off by default, so the content stream is plain text). Mirrors the Arabic
    /// integration test's extractor.
    private func drawnCIDs(_ data: Data) -> [UInt16] {
        let content = String(String.UnicodeScalarView(data.map { UnicodeScalar($0) }))
        guard let regex = try? NSRegularExpression(pattern: "<([0-9A-Fa-f]+)>\\s*Tj") else {
            return []
        }
        let range = NSRange(content.startIndex ..< content.endIndex, in: content)
        var codes: [UInt16] = []
        for match in regex.matches(in: content, range: range) {
            guard let hexRange = Range(match.range(at: 1), in: content) else {
                continue
            }
            let hex = content[hexRange]
            var index = hex.startIndex
            while let end = hex.index(index, offsetBy: 4, limitedBy: hex.endIndex) {
                if let code = UInt16(hex[index ..< end], radix: 16) {
                    codes.append(code)
                }
                index = end
            }
        }
        return codes
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

    @Test("A name-keyed CFF face from a collection embeds as OpenType, never Type1C")
    func nameKeyedCFFCollectionEmbedsAsOpenType() throws {
        guard let stix = fontData(Self.nameKeyedCFFPath) else {
            return
        }
        // STIX General is a name-keyed CFF sfnt; wrap two copies into a genuine 'ttcf'
        // collection (distinct per-face directories) so the writer must reconstruct a
        // standalone single-face sfnt for the selected face and emit it as OpenType. A
        // bare `Type1C` under a `CIDFontType0` descendant, the old fallback, is a
        // composite/simple mismatch that fails PDF/A and PDF/UA validation.
        let collection = SyntheticTrueTypeFont.makeCollection(faces: [stix, stix])
        let options = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: collection, baseName: "STIXCollection", faceIndex: 1),
        ))
        // The same sentence the single-face STIX test uses, so the raster clears the
        // visual witness's ink-density floor; the reconstructed sfnt renders as the
        // standalone STIX face would.
        let pdf = try MarkdownPDFRenderer(options: options)
            .render(markdown: "The quick brown fox jumps over 12345.")

        try assertEmbeddedFontVisualWitness(
            pdf,
            name: "cff-name-keyed-collection",
            expectedSubstrings: ["quick", "brown", "12345"],
            minWords: 5,
        )

        let inspector = PDFInspector(pdf)
        #expect(inspector.text.contains("/OpenType"))
        #expect(inspector.text.contains("/CIDFontType0"))
        #expect(inspector.text.contains("/FontFile3"))
        // The spec-invalid `/Type1C` subtype must never appear (`/CIDFontType0C` and
        // `/OpenType` do not contain it).
        #expect(!inspector.text.contains("/Type1C"))
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
