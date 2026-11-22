import Foundation

/// A colour emoji face: a TrueType font with a `COLR` (version 0) and a `CPAL` table, such as Twemoji. An emoji is drawn as the layers of its base
/// glyph, each layer's outline filled as a vector path in its palette colour, the first at the bottom. The text of the emoji is carried by one
/// invisible glyph, the base glyph, whose `/ToUnicode` entry is the emoji itself: a reader that ignores `/ActualText` (PDFKit, so Preview) finds
/// the emoji there, and the layers, being paths, are no text at all.
///
/// Immutable after `init` (every stored property is a `let` value type read only), so the one bundled instance is shared between threads:
/// `@unchecked Sendable` because the font parser types it holds are not declared `Sendable`.
struct ColorEmojiFont: @unchecked Sendable {
    /// One layer of a drawn emoji: its outline in font units and its colour.
    struct Layer: Equatable {
        var segments: [TrueTypeGlyphOutline.Segment]
        /// The palette colour, nil for the foreground colour of the text.
        var color: PDFColor?
        /// The alpha of the palette entry, 0 to 255 (255 for the foreground colour): a shadow or a highlight is filled with it, not opaque.
        var alpha: Int = 255
    }

    /// What a cluster is drawn as.
    struct Drawing: Equatable {
        /// The invisible base glyph that carries the emoji as text.
        var base: ShapedTextMapping
        var layers: [Layer]
        var unitsPerEm: Double
    }

    enum ColorEmojiFontError: Error, Equatable {
        case missingTable(String)
    }

    let resource: PDFEmbeddedFontResource
    private let mapper: TrueTypeGlyphMapper
    private let metadata: TrueTypeFontParser.Metadata
    private let colr: COLRTable
    private let cpal: CPALTable
    private let outlines: TrueTypeGlyphOutline
    /// The glyph substitutions of the face (`ccmp`, 2298 ligatures in the bundled face): they turn the glyphs of the scalars of a sequence into the one
    /// glyph of the sequence. Nil when the face has no `GSUB` table or it cannot be read: sequences are then not drawn from it.
    private let substitutions: GSUBFeatureApplier?

    init(source: PDFOptions.EmbeddedFontSource, resourceName: String = "EF6") throws {
        let metadata = try TrueTypeFontParser().parse(source.data, faceIndex: source.faceIndex, preferFullUnicodeCMap: true)
        let bytes = [UInt8](source.data)
        func table(_ tag: String) throws -> [UInt8] {
            guard let record = metadata.table(named: tag) else { throw ColorEmojiFontError.missingTable(tag) }
            let reader = TrueTypeByteReader(table: tag, bytes: bytes)
            return try reader.bytes(in: Int(record.offset) ..< Int(record.offset) + Int(record.length))
        }
        colr = try COLRTable(bytes: table("COLR"))
        cpal = try CPALTable(bytes: table("CPAL"))
        outlines = try TrueTypeGlyphOutline(
            glyf: table("glyf"), loca: table("loca"), longOffsets: metadata.head.indexToLocFormat != 0, glyphCount: Int(metadata.maxp.numGlyphs),
        )
        self.metadata = metadata
        mapper = TrueTypeGlyphMapper(data: source.data, metadata: metadata)
        if let record = metadata.table(named: "GSUB"), let table = try? GSUBTable(
            fontData: source.data,
            gsubTableRange: Int(record.offset) ..< Int(record.offset) + Int(record.length),
            scriptTag: "DFLT",
            numGlyphs: metadata.maxp.numGlyphs,
        ) {
            substitutions = GSUBFeatureApplier(gsub: table, gdef: nil, numGlyphs: metadata.maxp.numGlyphs)
        } else {
            substitutions = nil
        }
        resource = PDFEmbeddedFontResource(resourceName: resourceName, fontProgram: source.data, metadata: metadata, baseName: source.baseName)
    }

    /// The base glyph of a cluster: the cmap glyph of its first scalar, nil when the font has none (so the cluster is not drawn from this face).
    func baseGlyph(of cluster: EmojiSegmenter.Cluster) -> UInt16? {
        if cluster.scalars.count >= 2, !(cluster.scalars.count == 2 && cluster.scalars[1].value == 0xFE0F) {
            return sequenceGlyph(of: cluster)
        }
        guard let mapped = try? mapper.map(text: String(cluster.base), fontSize: 1), let glyph = mapped.glyphs.first, glyph.glyphID != 0 else {
            return nil
        }
        return glyph.glyphID
    }

    /// The glyph of a sequence: the cmap glyphs of its scalars, put through the face's own `ccmp` ligatures; the sequence is drawn from this face only when
    /// that leaves exactly one glyph (a flag, a keycap, a skin tone, a joined emoji have one in the bundled face). Nil otherwise: a scalar the cmap lacks, no
    /// substitution table, or a result of several glyphs, which would be the parts of the sequence drawn one by one.
    private func sequenceGlyph(of cluster: EmojiSegmenter.Cluster) -> UInt16? {
        // The ligatures of a face are keyed on one spelling of each sequence, and the faces differ (the older face keyed the keycap with its selector, the
        // newer one keys it without): the spelling as written, the fully qualified one (the variation selector after each text-default emoji of the
        // sequence; unicode.org lists both), then the one with every variation selector taken off.
        var spellings: [[Unicode.Scalar]] = [cluster.scalars]
        for spelling in [Self.fullyQualified(cluster.scalars), cluster.scalars.filter { $0.value != 0xFE0F }] where !spellings.contains(spelling) {
            spellings.append(spelling)
        }
        for spelling in spellings {
            if let glyph = sequenceGlyph(of: spelling) {
                return glyph
            }
        }
        return nil
    }

    /// The scalars with the emoji variation selector after every text-default emoji (an emoji that is not drawn as an emoji by default) and after a
    /// keycap base, unless the selector is there already or a skin tone modifier follows (a modifier takes the place of the selector).
    static func fullyQualified(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        for (index, scalar) in scalars.enumerated() {
            result.append(scalar)
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil
            if next?.value == 0xFE0F {
                continue
            }
            if let next, (0x1F3FB ... 0x1F3FF).contains(next.value) {
                continue
            }
            let isKeycapBase = next?.value == 0x20E3 && (scalar.value == 0x23 || scalar.value == 0x2A || (0x30 ... 0x39).contains(scalar.value))
            let isTextDefaultEmoji = scalar.value > 0x7F && scalar.properties.isEmoji && !scalar.properties.isEmojiPresentation
                && !(0x1F3FB ... 0x1F3FF).contains(scalar.value) && scalar.value != 0x200D && scalar.value != 0x20E3
            if isKeycapBase || isTextDefaultEmoji {
                result.append("\u{FE0F}")
            }
        }
        return result
    }

    private func sequenceGlyph(of scalars: [Unicode.Scalar]) -> UInt16? {
        guard let substitutions else { return nil }
        var glyphs: [ShapedGlyph] = []
        for (index, scalar) in scalars.enumerated() {
            guard let mapped = try? mapper.map(text: String(scalar), fontSize: 1), let glyph = mapped.glyphs.first, glyph.glyphID != 0 else { return nil }
            glyphs.append(ShapedGlyph(glyphID: glyph.glyphID, sourceScalarRange: index ..< index + 1))
        }
        // A long sequence is built in steps (a joined family is two ligatures, the first pair and then the third emoji): apply until nothing shrinks.
        // MEASURED on the bundled face: `ccmp` joins flags and skin tones; the joined sequences and the keycap need the contextual lookups of `liga`, `rlig`
        // and `clig` after it, in this order (every one of the four tags is read from the face's own tables, none is assumed present).
        var substituted = glyphs
        for _ in 0 ..< 8 {
            var next = substituted
            for feature in ["ccmp", "liga", "rlig", "clig"] {
                next = substitutions.apply(feature: feature, to: next)
            }
            if next.count >= substituted.count {
                break
            }
            substituted = next
        }
        guard substituted.count == 1, let glyph = substituted.first?.glyphID, glyph != 0 else { return nil }
        return glyph
    }

    /// The advance of the cluster in points at `fontSize`, nil when the font cannot draw it.
    func advance(of cluster: EmojiSegmenter.Cluster, fontSize: Double) -> Double? {
        guard let base = baseGlyph(of: cluster), Int(base) < metadata.hmtx.advanceWidths.count else { return nil }
        return Double(metadata.hmtx.advanceWidths[Int(base)]) / Double(metadata.head.unitsPerEm) * fontSize
    }

    /// The drawing of a cluster; nil when the font cannot draw it. A base glyph with no colour layers is drawn as its own outline, in the
    /// foreground colour.
    func drawing(of cluster: EmojiSegmenter.Cluster, fontSize: Double) -> Drawing? {
        guard let base = baseGlyph(of: cluster), Int(base) < metadata.hmtx.advanceWidths.count else { return nil }
        let records = colr.layers(forBaseGlyph: base) ?? [COLRTable.Layer(glyphID: base, paletteIndex: COLRTable.foregroundPaletteIndex)]
        var layers: [Layer] = []
        for record in records {
            guard let segments = try? outlines.segments(forGlyph: record.glyphID) else { return nil }
            let entry = cpal.color(palette: 0, entry: record.paletteIndex)
            let color = entry.map {
                PDFColor(red: Double($0.red) / 255, green: Double($0.green) / 255, blue: Double($0.blue) / 255)
            }
            layers.append(Layer(segments: segments, color: color, alpha: entry.map { Int($0.alpha) } ?? 255))
        }
        let cid = metadata.compositeCID(forGlyph: base)
        let advanceWidth = metadata.hmtx.advanceWidths[Int(base)]
        let glyph = ShapedTextMapping.Glyph(
            glyphID: base, cid: cid, pdfCharacterCode: cid, advanceWidth: advanceWidth,
            advance: Double(advanceWidth) / Double(metadata.head.unitsPerEm) * fontSize,
        )
        // The text of the glyph: the emoji scalar for a single emoji and one with its selector (as before), the whole sequence, joiners and selectors
        // included, for a sequence.
        let isSequence = cluster.scalars.count >= 2 && !(cluster.scalars.count == 2 && cluster.scalars[1].value == 0xFE0F)
        let scalars = isSequence ? cluster.scalars : [cluster.base]
        let text = String(String.UnicodeScalarView(scalars))
        guard let mapping = try? ShapedTextMapping(
            sourceText: text,
            clusters: [ShapedTextMapping.Cluster(sourceScalarRange: 0 ..< scalars.count, normalizedText: text, glyphs: [glyph], toUnicodeScalars: scalars)],
        ) else { return nil }
        return Drawing(base: mapping, layers: layers, unitsPerEm: Double(metadata.head.unitsPerEm))
    }
}
