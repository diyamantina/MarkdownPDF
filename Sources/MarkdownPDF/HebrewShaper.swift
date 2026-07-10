import Foundation

/// Hebrew shaping: composes the font's Hebrew presentation forms (shin/sin dot,
/// letter+dagesh, vav+holam, and the like) with GSUB `ccmp`, then places the remaining
/// niqqud on their letters with GPOS. Hebrew does not join cursively, so there is no
/// positional form or contextual joining step; the letters map one glyph per scalar,
/// `ccmp` collapses the composed clusters, and the shared ``GPOSMarkPositioner`` attaches
/// the marks. The mapping stays in logical order; the caller draws it reversed for the
/// right-to-left run.
struct HebrewShaper {
    var fontData: Data
    var metadata: TrueTypeFontParser.Metadata

    /// The font's `hebr` GSUB (presentation composition) and GPOS mark attachment, plus
    /// GDEF glyph classes, parsed once. Any of them nil when absent or malformed: the
    /// marks then keep their nominal positions and the font still renders.
    private let gsub: GSUBTable?
    private let gpos: GPOSTable?
    private let gdef: GDEFTable?

    init(fontData: Data, metadata: TrueTypeFontParser.Metadata) {
        self.fontData = fontData
        self.metadata = metadata
        do {
            gsub = try GSUBTable(
                fontData: fontData,
                gsubTableRange: Self.tableRange(named: "GSUB", fontData: fontData, metadata: metadata),
                scriptTag: "hebr",
                numGlyphs: metadata.maxp.numGlyphs,
            )
        } catch {
            gsub = nil
        }
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
    /// whose composition or placement this shaper would refine. A plain Hebrew run
    /// without points needs neither and stays on the ordinary path.
    static func containsPointedHebrew(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isHebrewMark)
    }

    /// Whether this font can shape Hebrew marks: it carries `hebr` GPOS mark features or
    /// `hebr` GSUB composition.
    var canPositionHebrewMarks: Bool {
        (gpos?.hasMarkPositioning ?? false) || gsub != nil
    }

    /// Composes and positions `text`, returning logical-order glyphs. Steps: base glyph
    /// per scalar, GSUB `ccmp` composition, then GPOS mark attachment.
    func shape(
        _ text: String,
        missingGlyphPolicy: TrueTypeGlyphMapper.MissingGlyphPolicy = .useNotdef,
    ) throws -> [ShapedGlyph] {
        // Reorder the letter-modifying marks (dagesh, shin/sin dot) to sit right after
        // their consonant, before the vowels, so `ccmp` can compose the presentation
        // form. This matches the reference shaper's Hebrew mark reordering; `shapedMapping`
        // reproduces it so source ranges and ToUnicode stay aligned.
        let scalars = Self.reorderedForShaping(Array(text.unicodeScalars))
        let orderedText = String(String.UnicodeScalarView(scalars))
        let mapper = TrueTypeGlyphMapper(data: fontData, metadata: metadata, missingGlyphPolicy: missingGlyphPolicy)
        let baseGlyphs = try mapper.map(text: orderedText, fontSize: 1).glyphs.map(\.glyphID)
        guard baseGlyphs.count == scalars.count else {
            return baseGlyphs.indices.map { ShapedGlyph(glyphID: baseGlyphs[$0], sourceScalarRange: $0 ..< $0 + 1) }
        }

        var glyphs = baseGlyphs.indices.map { ShapedGlyph(glyphID: baseGlyphs[$0], sourceScalarRange: $0 ..< $0 + 1) }
        if let gsub {
            glyphs = GSUBFeatureApplier(gsub: gsub, gdef: gdef, numGlyphs: metadata.maxp.numGlyphs)
                .apply(feature: "ccmp", to: glyphs)
        }
        if let gpos, gpos.hasMarkPositioning, let gdef {
            let placements = GPOSMarkPositioner.placements(for: glyphs.map(\.glyphID), gpos: gpos, gdef: gdef)
            for index in glyphs.indices {
                glyphs[index].xOffset = placements[index].xOffset
                glyphs[index].yOffset = placements[index].yOffset
            }
        }
        return glyphs
    }

    /// Shapes `text` into a `ShapedTextMapping` in logical order: advances from the font
    /// `hmtx` scaled to `fontSize`, GPOS offsets scaled likewise, and each cluster's
    /// source scalars recorded so `/ToUnicode` recovers the original text through the
    /// composed glyphs.
    func shapedMapping(
        text: String,
        fontSize: Double,
        missingGlyphPolicy: TrueTypeGlyphMapper.MissingGlyphPolicy = .useNotdef,
    ) throws -> ShapedTextMapping {
        let scalars = Self.reorderedForShaping(Array(text.unicodeScalars))
        let orderedText = String(String.UnicodeScalarView(scalars))
        let shaped = try shape(text, missingGlyphPolicy: missingGlyphPolicy)
        let unitsPerEm = Double(metadata.head.unitsPerEm)
        let advanceWidths = metadata.hmtx.advanceWidths
        let scale = unitsPerEm > 0 ? fontSize / unitsPerEm : 0

        var clusters: [ShapedTextMapping.Cluster] = []
        clusters.reserveCapacity(shaped.count)
        for glyph in shaped {
            let range = glyph.sourceScalarRange
            let clusterScalars = Array(scalars[range])
            let advanceWidth = Int(glyph.glyphID) < advanceWidths.count ? advanceWidths[Int(glyph.glyphID)] : 0
            let advance = unitsPerEm > 0 ? Double(advanceWidth) / unitsPerEm * fontSize : 0
            let cid = metadata.compositeCID(forGlyph: glyph.glyphID)
            let offset = ShapedTextMapping.Offset(x: Double(glyph.xOffset) * scale, y: Double(glyph.yOffset) * scale)
            clusters.append(ShapedTextMapping.Cluster(
                sourceScalarRange: range,
                normalizedText: String(String.UnicodeScalarView(clusterScalars)),
                glyphs: [ShapedTextMapping.Glyph(
                    glyphID: glyph.glyphID,
                    cid: cid,
                    pdfCharacterCode: cid,
                    advanceWidth: advanceWidth,
                    advance: advance,
                    offset: offset,
                    // A composed presentation glyph maps several scalars to one glyph,
                    // which would collide in the subset cmap; give each a synthetic,
                    // glyph-unique cmap scalar. Extraction uses the real toUnicodeScalars.
                    cmapScalar: UnicodeScalar(0x100000 + UInt32(glyph.glyphID)),
                )],
                toUnicodeScalars: clusterScalars,
            ))
        }
        return try ShapedTextMapping(sourceText: orderedText, clusters: clusters)
    }

    /// Normalizes a Hebrew run for shaping in two steps. First it reorders each mark run
    /// into Unicode canonical (combining-class) order, so niqqud or accents typed out of
    /// order match the reference shaper, which normalizes before shaping. Then it moves
    /// each consonant's letter-modifying marks (dagesh, shin dot, sin dot) to directly
    /// after the consonant, ahead of the vowels in the same cluster, so `ccmp` can compose
    /// the presentation form. Within each mark run the modifiers keep their relative order
    /// and the other marks keep theirs (a stable partition). Both steps preserve the scalar
    /// set, so the result is canonically equivalent to the input.
    static func reorderedForShaping(_ scalars: [UnicodeScalar]) -> [UnicodeScalar] {
        let canonical = CanonicalCombiningClass.canonicallyOrderedHebrew(scalars)
        guard canonical.contains(where: isLetterModifier) else {
            return canonical
        }
        var result = canonical
        var index = 0
        while index < result.count {
            guard isHebrewMark(result[index]) else {
                index += 1
                continue
            }
            var end = index
            while end < result.count, isHebrewMark(result[end]) {
                end += 1
            }
            let run = result[index ..< end]
            if run.contains(where: isLetterModifier) {
                let modifiers = run.filter(isLetterModifier)
                let others = run.filter { !isLetterModifier($0) }
                result.replaceSubrange(index ..< end, with: modifiers + others)
            }
            index = end
        }
        return result
    }

    /// The Hebrew marks that attach to the consonant itself (composed by `ccmp`), as
    /// opposed to vowel points and accents.
    private static func isLetterModifier(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x05BC, // dagesh or mapiq
             0x05C1, // shin dot
             0x05C2: // sin dot
            true
        default:
            false
        }
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
