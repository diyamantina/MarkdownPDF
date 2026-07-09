import Foundation
import MathTypeset

struct PDFEmbeddedFontCatalog {
    struct Entry {
        var resource: PDFEmbeddedFontResource
        var mapper: TrueTypeGlyphMapper
        var shaper: OpenTypeShaper
        var mathMetrics: MathLayoutMetrics?
    }

    private var entriesByFont: [StandardFont: Entry]

    /// Policy for a scalar the font's cmap cannot draw on the *rendering* path.
    /// `.useNotdef` keeps one missing glyph from aborting the whole document; the
    /// caller passes `.reject` when a conformance profile is active, because
    /// PDF/UA-1 and PDF/A-2a forbid referencing the `.notdef` glyph in content and
    /// require a Unicode mapping for every code, so drawing notdef would ship
    /// spec-violating output under a conformance claim. The strict `.reject` probe
    /// in ``covers(_:font:)`` is unaffected by this and stays strict always.
    private let renderingMissingGlyphPolicy: TrueTypeGlyphMapper.MissingGlyphPolicy

    init(
        fonts: PDFOptions.EmbeddedFonts,
        parseMathTables: Bool = false,
        renderingMissingGlyphPolicy: TrueTypeGlyphMapper.MissingGlyphPolicy = .useNotdef,
    ) throws {
        self.renderingMissingGlyphPolicy = renderingMissingGlyphPolicy
        var entries: [StandardFont: Entry] = [:]
        try Self.add(fonts.regular, for: .helvetica, resourceName: "EF1", parseMathTables: parseMathTables, to: &entries)
        try Self.add(fonts.bold, for: .helveticaBold, resourceName: "EF2", parseMathTables: parseMathTables, to: &entries)
        try Self.add(
            fonts.italic,
            for: .helveticaOblique,
            resourceName: "EF3",
            parseMathTables: parseMathTables,
            to: &entries,
        )
        try Self.add(fonts.monospaced, for: .courier, resourceName: "EF4", parseMathTables: parseMathTables, to: &entries)
        entriesByFont = entries
    }

    func entry(for font: StandardFont) -> Entry? {
        entriesByFont[font]
    }

    /// Whether the embedded font bound to `font` can draw every scalar in `text`.
    /// Used to decide, per math symbol, between the Unicode glyph and an ASCII
    /// transliteration. A font with no embedded entry (the base-14 portable
    /// profile) covers no math glyphs, so this returns `false`.
    func covers(_ text: String, font: StandardFont) -> Bool {
        guard let entry = entry(for: font) else {
            return false
        }
        return (try? entry.mapper.map(text: text, fontSize: 1)) != nil
    }

    func width(of run: PDFTextRun, fallbackFontSet: PDFOptions.FontSet) throws -> Double {
        guard let entry = entry(for: run.font) else {
            return run.width(fontSet: fallbackFontSet)
        }

        return try shapedMapping(for: run, entry: entry).totalAdvance
    }

    /// Maps a run to glyphs for drawing under ``renderingMissingGlyphPolicy``. With
    /// `.useNotdef` a single scalar the font's cmap lacks (an emoji, a stray
    /// combining mark, a CJK glyph the subset omits) renders as that font's
    /// `.notdef` glyph for that one scalar instead of aborting the whole document
    /// with `missingGlyph`; the subset always retains glyph 0. Under a conformance
    /// profile the policy is `.reject`, so a missing glyph refuses rather than
    /// shipping non-conformant notdef content. The strict `.reject` probe stays in
    /// ``covers(_:font:)`` regardless, deciding math-symbol transliteration.
    func mapping(for run: PDFTextRun, entry: Entry) throws -> TrueTypeGlyphMapper.TextMapping {
        var mapper = entry.mapper
        mapper.missingGlyphPolicy = renderingMissingGlyphPolicy
        return try mapper.map(text: run.text, fontSize: run.size)
    }

    func shapedMapping(for run: PDFTextRun, entry: Entry) throws -> ShapedTextMapping {
        if OpenTypeShaper.canShapeLatinIncrement(run.text) {
            var shaper = entry.shaper
            shaper.missingGlyphPolicy = renderingMissingGlyphPolicy
            return try shaper.shape(text: run.text, fontSize: run.size)
        }
        if let scalar = run.text.unicodeScalars.first(where: Self.requiresExplicitShapingSupport) {
            throw PDFEmbeddedFontError.unsupportedComplexScriptScalar(scalar: scalar)
        }
        return try mapping(for: run, entry: entry).shapedText()
    }

    private static func add(
        _ source: PDFOptions.EmbeddedFontSource?,
        for font: StandardFont,
        resourceName: String,
        parseMathTables: Bool,
        to entries: inout [StandardFont: Entry],
    ) throws {
        guard let source else {
            return
        }

        let metadata = try TrueTypeFontParser().parse(
            source.data,
            parseMathTable: parseMathTables,
            faceIndex: source.faceIndex,
        )
        let resource = PDFEmbeddedFontResource(
            resourceName: resourceName,
            fontProgram: source.data,
            metadata: metadata,
            baseName: source.baseName,
        )
        entries[font] = Entry(
            resource: resource,
            mapper: TrueTypeGlyphMapper(data: source.data, metadata: metadata),
            shaper: OpenTypeShaper(data: source.data, metadata: metadata),
            mathMetrics: metadata.math.map {
                MathLayoutMetrics.openType(constants: $0.constants, unitsPerEm: metadata.head.unitsPerEm)
            },
        )
    }

    private static func requiresExplicitShapingSupport(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0700 ... 0x074F, // Syriac
             0x0750 ... 0x077F, // Arabic Supplement
             0x0780 ... 0x07BF, // Thaana
             0x07C0 ... 0x07FF, // NKo
             0x08A0 ... 0x08FF, // Arabic Extended-A
             0x0900 ... 0x0D7F, // Indic script blocks used by the first roadmap fixture set.
             0x0E00 ... 0x0E7F, // Thai
             0x1780 ... 0x17FF, // Khmer
             0xFB1D ... 0xFDFF, // Hebrew and Arabic presentation forms
             0xFE70 ... 0xFEFE: // Arabic Presentation Forms-B (U+FEFF is the BOM, not a letter)
            true
        default:
            false
        }
    }
}
