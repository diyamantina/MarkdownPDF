import Foundation

/// Hebrew shaping: places niqqud (vowel points) and other Hebrew combining marks on
/// their letters via GPOS. Hebrew does not join cursively, so there is no positional
/// form or contextual step; the letters map one glyph per scalar and the marks are
/// attached by the shared ``GPOSMarkPositioner``. The mapping stays in logical order;
/// the caller draws it reversed for the right-to-left run.
struct HebrewShaper {
    var fontData: Data
    var metadata: TrueTypeFontParser.Metadata

    /// The font's `hebr` GPOS mark-attachment lookups and its GDEF glyph classes,
    /// parsed once. Both nil when absent or malformed: the marks then keep their
    /// nominal positions and the font still renders.
    private let gpos: GPOSTable?
    private let gdef: GDEFTable?

    init(fontData: Data, metadata: TrueTypeFontParser.Metadata) {
        self.fontData = fontData
        self.metadata = metadata
        do {
            gpos = try GPOSTable(
                fontData: fontData,
                gposTableRange: Self.tableRange(named: "GPOS", fontData: fontData, metadata: metadata),
                scriptTag: "hebr",
            )
        } catch {
            gpos = nil
        }
        do {
            gdef = try GDEFTable(
                fontData: fontData,
                gdefTableRange: Self.tableRange(named: "GDEF", fontData: fontData, metadata: metadata),
            )
        } catch {
            gdef = nil
        }
    }

    /// Whether `text` carries a Hebrew combining mark (niqqud, dagesh, or cantillation)
    /// whose placement this shaper would refine. A plain Hebrew run without points needs
    /// no positioning and stays on the ordinary path.
    static func containsPointedHebrew(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isHebrewMark)
    }

    /// Whether this font can place Hebrew marks (it carries `hebr` GPOS mark features).
    var canPositionHebrewMarks: Bool {
        gpos?.hasMarkPositioning ?? false
    }

    /// Maps `text` to logical-order glyphs (one per scalar) and attaches its Hebrew
    /// marks with GPOS. Advances come from the font `hmtx` scaled to `fontSize`; each
    /// cluster records its source scalar so `/ToUnicode` recovers the original text.
    func shapedMapping(
        text: String,
        fontSize: Double,
        missingGlyphPolicy: TrueTypeGlyphMapper.MissingGlyphPolicy = .useNotdef,
    ) throws -> ShapedTextMapping {
        let mapper = TrueTypeGlyphMapper(data: fontData, metadata: metadata, missingGlyphPolicy: missingGlyphPolicy)
        let glyphs = try mapper.map(text: text, fontSize: fontSize).glyphs

        let placements: [GPOSMarkPositioner.Placement] = if let gpos, gpos.hasMarkPositioning, let gdef {
            GPOSMarkPositioner.placements(for: glyphs.map(\.glyphID), gpos: gpos, gdef: gdef)
        } else {
            [GPOSMarkPositioner.Placement](repeating: .zero, count: glyphs.count)
        }

        let unitsPerEm = Double(metadata.head.unitsPerEm)
        let scale = unitsPerEm > 0 ? fontSize / unitsPerEm : 0

        var clusters: [ShapedTextMapping.Cluster] = []
        clusters.reserveCapacity(glyphs.count)
        for (index, glyph) in glyphs.enumerated() {
            let placement = placements[index]
            let offset = ShapedTextMapping.Offset(x: Double(placement.xOffset) * scale, y: Double(placement.yOffset) * scale)
            clusters.append(ShapedTextMapping.Cluster(
                sourceScalarRange: index ..< index + 1,
                normalizedText: String(glyph.scalar),
                glyphs: [ShapedTextMapping.Glyph(glyph, offset: offset, cmapScalar: glyph.scalar)],
                toUnicodeScalars: [glyph.scalar],
            ))
        }
        return try ShapedTextMapping(sourceText: text, clusters: clusters)
    }

    private static func isHebrewMark(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0591 ... 0x05BD, // cantillation accents and most niqqud
             0x05BF, // rafe
             0x05C1, 0x05C2, // shin dot, sin dot
             0x05C4, 0x05C5, // upper/lower dot
             0x05C7: // qamats qatan
            true
        default:
            false
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
}
