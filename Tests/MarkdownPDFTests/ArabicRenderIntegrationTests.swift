import Foundation
@testable import MarkdownPDF
import Testing

/// End-to-end witness for #47: an Arabic paragraph rendered with an embedded Arabic
/// font must draw its glyphs joined and in RTL visual order, matching HarfBuzz, with
/// `/ToUnicode` recovering the original characters.
@Suite("Arabic render integration")
struct ArabicRenderIntegrationTests {
    private static func notoOptions() throws -> (PDFOptions, path: String) {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/NotoNaskhArabic-Regular.ttf")
        let data = try Data(contentsOf: url)
        let options = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: data, baseName: "Noto"),
        ))
        return (options, url.path)
    }

    /// The CID codes drawn by the `showCIDText` operators (`<hex> Tj`) in the content
    /// stream, in draw order (which is visual order). A strict contiguous-hex match
    /// avoids spanning a `<...>` in a CMap/font object; stream compression is off by
    /// default, so the content stream is plain text. Returns the codes of every
    /// `<hex> Tj`, flattened in document order (a single-word render has one).
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

    @Test(
        "An Arabic paragraph draws joined, RTL-visual, matching HarfBuzz",
        .enabled(if: HarfBuzzOracle.isAvailable, "hb-shape not found on PATH"),
        arguments: [
            "\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}", // مرحبا
            "\u{0628}\u{0633}\u{0645}", // بسم
            "\u{0643}\u{062A}\u{0627}\u{0628}", // كتاب
            "\u{0645}\u{062D}\u{0645}\u{062F}", // محمد
            "\u{0639}\u{0631}\u{0628}\u{064A}", // عربي
            "\u{0646}\u{0639}\u{0645}", // نعم
            // Lam-alef: the engine now applies Noto's contextual (GSUB type 5) rlig
            // lookup, so the drawn glyphs are the font's exact contextual pair and
            // match hb-shape end to end.
            "\u{0633}\u{0644}\u{0627}\u{0645}", // سلام
        ],
    )
    func arabicParagraphDrawsJoinedRTL(_ word: String) throws {
        let (options, fontPath) = try Self.notoOptions()
        let data = try MarkdownPDFRenderer(options: options).render(markdown: word)

        // hb-shape returns glyphs in visual (RTL) order already; the content stream is
        // emitted in the same visual order.
        let oracleVisual = try HarfBuzzOracle.shape(word, fontPath: fontPath).reversed()
        #expect(drawnCIDs(data) == Array(oracleVisual), "drawn CIDs != hb-shape visual order for \(word)")
    }

    @Test("The shaping path honors the missing-glyph policy (conformance still refuses)")
    func arabicShapingHonorsMissingGlyphPolicy() throws {
        // An Arabic run containing a scalar the font lacks must refuse under `.reject`
        // (a conformance profile) instead of drawing `.notdef`, matching the base
        // policy. Before the fix the Arabic path hard-coded `.useNotdef`, so a PDF/UA
        // document silently shipped a notdef reference with no ToUnicode.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/NotoNaskhArabic-Regular.ttf")
        let data = try Data(contentsOf: url)
        let metadata = try TrueTypeFontParser().parse(data)
        let shaper = ArabicShaper(fontData: data, metadata: metadata)
        let text = "\u{0645}\u{6F22}\u{062F}" // meem + a CJK char Noto Arabic lacks + dal

        // `.useNotdef` tolerates the missing glyph (non-conformance path).
        _ = try shaper.shapedMapping(text: text, fontSize: 10, missingGlyphPolicy: .useNotdef)
        // `.reject` refuses it (conformance path).
        #expect(throws: TrueTypeGlyphMappingError.self) {
            _ = try shaper.shapedMapping(text: text, fontSize: 10, missingGlyphPolicy: .reject)
        }
    }

    @Test(
        "A joined Arabic word is drawn narrower than its isolated-form width",
        .enabled(if: HarfBuzzOracle.isAvailable, "hb-shape not found on PATH"),
    )
    func joinedWidthIsShorterThanIsolated() throws {
        let (options, _) = try Self.notoOptions()
        let catalog = try PDFEmbeddedFontCatalog(fonts: options.embeddedFonts)
        let entry = try #require(catalog.entry(for: .helvetica))
        let word = "\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}" // مرحبا

        let shaped = try entry.arabicShaper.shapedMapping(text: word, fontSize: 100).totalAdvance
        // Isolated width: sum of each base glyph's advance with no shaping.
        let isolated = try entry.mapper.map(text: word, fontSize: 100).glyphs.reduce(0.0) { $0 + $1.width }
        #expect(shaped < isolated, "shaped width \(shaped) should be less than isolated \(isolated)")
    }

    @Test("ToUnicode recovers the original Arabic characters from the drawn PDF")
    func toUnicodeRecoversArabic() throws {
        let (options, _) = try Self.notoOptions()
        let word = "\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}" // مرحبا
        let data = try MarkdownPDFRenderer(options: options).render(markdown: word)
        let inspector = try PDFInspector(data)
        #expect(inspector.text.contains("/ToUnicode"))
        // Every source scalar appears as a bfchar/bfrange Unicode value in the CMap.
        let content = inspector.text
        for scalar in word.unicodeScalars {
            let hex = String(format: "%04X", scalar.value)
            #expect(content.uppercased().contains(hex), "ToUnicode is missing U+\(hex)")
        }
    }

    @Test("A Hebrew paragraph still renders (non-joining, unaffected by Arabic shaping)")
    func hebrewStillRenders() throws {
        let (options, _) = try Self.notoOptions()
        // Noto Naskh Arabic has no Hebrew, so use Arial which has both.
        let arialPath = "/System/Library/Fonts/Supplemental/Arial.ttf"
        guard FileManager.default.fileExists(atPath: arialPath) else {
            return
        }
        let arial = try Data(contentsOf: URL(fileURLWithPath: arialPath))
        _ = options
        let opts = PDFOptions(embeddedFonts: .allRoles(PDFOptions.EmbeddedFontSource(data: arial, baseName: "Arial")))
        let data = try MarkdownPDFRenderer(options: opts).render(markdown: "\u{05E9}\u{05DC}\u{05D5}\u{05DD}") // שלום
        #expect(!data.isEmpty)
        #expect(try PDFInspector(data).text.contains("/ToUnicode"))
    }
}
