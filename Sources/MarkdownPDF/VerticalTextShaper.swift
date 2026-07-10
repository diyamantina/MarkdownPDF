import Foundation

/// Shapes a run for top-to-bottom (vertical) CJK layout: it maps each scalar to its glyph,
/// applies the font's `vert` feature so upright-only forms (brackets, the ideographic comma
/// and full stop, dashes) become their vertical variants, and gives each glyph its vertical
/// advance from `vmtx`. Ideographs are unchanged by `vert` and stand upright; a scalar the
/// font cannot draw maps to `.notdef`.
///
/// This produces the glyphs and their descent; the column layout (stacking glyphs down a
/// line and lines right to left) and the PDF drawing are the renderer's job. Verified
/// against CoreText's vertical typesetter: the substituted glyph ids and advances match.
struct VerticalTextShaper {
    struct VerticalGlyph: Equatable {
        var glyphID: UInt16
        var cid: UInt16
        /// The vertical advance in `fontSize` units: how far the pen descends after this
        /// glyph.
        var advance: Double
        /// The source scalar, kept so the renderer can build `/ToUnicode` and classify the
        /// glyph (ideograph vs punctuation) for orientation.
        var scalar: UnicodeScalar
    }

    var fontData: Data
    var metadata: TrueTypeFontParser.Metadata

    private let gsub: GSUBTable?
    private let gdef: GDEFTable?
    private let verticalMetrics: VerticalMetrics?

    init(fontData: Data, metadata: TrueTypeFontParser.Metadata) {
        self.fontData = fontData
        self.metadata = metadata
        // `vert` is registered under the CJK scripts and DFLT; the reader falls back to
        // DFLT when the named script is absent, so either resolves the feature.
        gsub = try? GSUBTable(
            fontData: fontData,
            gsubTableRange: Self.tableRange(named: "GSUB", fontData: fontData, metadata: metadata),
            scriptTag: "kana",
            numGlyphs: metadata.maxp.numGlyphs,
        )
        gdef = try? GDEFTable(
            fontData: fontData,
            gdefTableRange: Self.tableRange(named: "GDEF", fontData: fontData, metadata: metadata),
        )
        verticalMetrics = try? VerticalMetrics(
            vheaBytes: Self.tableBytes(named: "vhea", fontData: fontData, metadata: metadata),
            vmtxBytes: Self.tableBytes(named: "vmtx", fontData: fontData, metadata: metadata),
            numGlyphs: metadata.maxp.numGlyphs,
        )
    }

    /// Whether the font carries what vertical shaping needs (vertical metrics). Without
    /// them the em square is the fallback advance, which is correct for a full-em CJK font
    /// but the caller may prefer to decline vertical layout.
    var hasVerticalMetrics: Bool {
        verticalMetrics != nil
    }

    func shape(
        _ text: String,
        fontSize: Double,
        missingGlyphPolicy: TrueTypeGlyphMapper.MissingGlyphPolicy = .useNotdef,
    ) throws -> [VerticalGlyph] {
        let mapper = TrueTypeGlyphMapper(data: fontData, metadata: metadata, missingGlyphPolicy: missingGlyphPolicy)
        let scalars = Array(text.unicodeScalars)
        let baseGlyphs = try mapper.map(text: text, fontSize: 1).glyphs.map(\.glyphID)
        guard baseGlyphs.count == scalars.count else {
            return []
        }

        var glyphs = scalars.indices.map { ShapedGlyph(glyphID: baseGlyphs[$0], sourceScalarRange: $0 ..< $0 + 1) }
        if let gsub {
            glyphs = GSUBFeatureApplier(gsub: gsub, gdef: gdef, numGlyphs: metadata.maxp.numGlyphs)
                .apply(feature: "vert", to: glyphs)
        }

        let unitsPerEm = metadata.head.unitsPerEm
        let scale = unitsPerEm > 0 ? fontSize / Double(unitsPerEm) : 0
        return glyphs.map { glyph in
            let advanceUnits = verticalMetrics?.advanceHeight(glyphID: glyph.glyphID, unitsPerEm: unitsPerEm) ?? unitsPerEm
            let scalar = scalars[glyph.sourceScalarRange.lowerBound]
            return VerticalGlyph(
                glyphID: glyph.glyphID,
                cid: metadata.compositeCID(forGlyph: glyph.glyphID),
                advance: Double(advanceUnits) * scale,
                scalar: scalar,
            )
        }
    }

    private static func tableRange(named tag: String, fontData: Data, metadata: TrueTypeFontParser.Metadata) -> Range<Int>? {
        guard let record = metadata.table(named: tag) else {
            return nil
        }
        let start = Int(record.offset)
        let end = start + Int(record.length)
        guard start >= 0, end <= fontData.count, start <= end else {
            return nil
        }
        return start ..< end
    }

    private static func tableBytes(named tag: String, fontData: Data, metadata: TrueTypeFontParser.Metadata) -> [UInt8]? {
        guard let range = tableRange(named: tag, fontData: fontData, metadata: metadata) else {
            return nil
        }
        return [UInt8](fontData[range])
    }
}
