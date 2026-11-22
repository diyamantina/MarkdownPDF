import Foundation

/// A colour emoji face: a TrueType font with a `COLR` (version 0) and a `CPAL` table, such as Twemoji. An emoji is drawn as its base glyph's
/// layers, each layer glyph shown in its palette colour at the same pen position, the first at the bottom.
struct ColorEmojiFont {
    /// One layer of a drawn emoji.
    struct Layer: Equatable {
        var glyph: ShapedTextMapping.Glyph
        /// The palette colour, nil for the foreground colour of the text.
        var color: PDFColor?
    }

    enum ColorEmojiFontError: Error, Equatable {
        case missingTable(String)
        case glyphOutOfRange(UInt16)
    }

    let resource: PDFEmbeddedFontResource
    private let mapper: TrueTypeGlyphMapper
    private let metadata: TrueTypeFontParser.Metadata
    private let colr: COLRTable
    private let cpal: CPALTable

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

    /// The layers to draw for a cluster, bottom first; nil when the font cannot draw it. A base glyph with no colour layers is drawn as itself,
    /// in the foreground colour.
    func layers(of cluster: EmojiSegmenter.Cluster, fontSize: Double) -> [Layer]? {
        guard let base = baseGlyph(of: cluster) else { return nil }
        let records = colr.layers(forBaseGlyph: base) ?? [COLRTable.Layer(glyphID: base, paletteIndex: COLRTable.foregroundPaletteIndex)]
        var layers: [Layer] = []
        for record in records {
            guard record.glyphID < metadata.maxp.numGlyphs, Int(record.glyphID) < metadata.hmtx.advanceWidths.count,
                  Self.privateScalar(forGlyph: record.glyphID) != nil
            else { return nil }
            let advanceWidth = metadata.hmtx.advanceWidths[Int(record.glyphID)]
            let cid = metadata.compositeCID(forGlyph: record.glyphID)
            let glyph = ShapedTextMapping.Glyph(
                glyphID: record.glyphID, cid: cid, pdfCharacterCode: cid, advanceWidth: advanceWidth,
                advance: Double(advanceWidth) / Double(metadata.head.unitsPerEm) * fontSize,
            )
            let color = cpal.color(palette: 0, entry: record.paletteIndex).map {
                PDFColor(red: Double($0.red) / 255, green: Double($0.green) / 255, blue: Double($0.blue) / 255)
            }
            layers.append(Layer(glyph: glyph, color: color))
        }
        return layers
    }

    /// The scalar a layer glyph's code stands for in the font's `/ToUnicode` map: a private-use scalar of plane 15 named by the glyph, so that two
    /// layer glyphs never claim the same text (a code maps to one scalar) and one glyph always keeps its scalar. The extracted text of a drawn emoji
    /// is the emoji itself, given by the `/ActualText` span around its layers, not these.
    static func privateScalar(forGlyph glyph: UInt16) -> Unicode.Scalar? {
        Unicode.Scalar(0xF0000 + UInt32(glyph))
    }

    /// The one-glyph text mapping of a layer.
    func mapping(of layer: Layer) throws -> ShapedTextMapping {
        guard let scalar = Self.privateScalar(forGlyph: layer.glyph.glyphID) else {
            throw ColorEmojiFontError.glyphOutOfRange(layer.glyph.glyphID)
        }
        return try ShapedTextMapping(
            sourceText: String(scalar),
            clusters: [ShapedTextMapping.Cluster(sourceScalarRange: 0 ..< 1, normalizedText: String(scalar), glyphs: [layer.glyph], toUnicodeScalars: [scalar])],
        )
    }
}
