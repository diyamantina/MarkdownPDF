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
        resource = PDFEmbeddedFontResource(resourceName: resourceName, fontProgram: source.data, metadata: metadata, baseName: source.baseName)
    }

    /// The base glyph of a cluster: the cmap glyph of its first scalar, nil when the font has none (so the cluster is not drawn from this face).
    func baseGlyph(of cluster: EmojiSegmenter.Cluster) -> UInt16? {
        guard let mapped = try? mapper.map(text: String(cluster.base), fontSize: 1), let glyph = mapped.glyphs.first, glyph.glyphID != 0 else {
            return nil
        }
        return glyph.glyphID
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
        let scalar = cluster.base
        guard let mapping = try? ShapedTextMapping(
            sourceText: String(scalar),
            clusters: [ShapedTextMapping.Cluster(sourceScalarRange: 0 ..< 1, normalizedText: String(scalar), glyphs: [glyph], toUnicodeScalars: [scalar])],
        ) else { return nil }
        return Drawing(base: mapping, layers: layers, unitsPerEm: Double(metadata.head.unitsPerEm))
    }
}
