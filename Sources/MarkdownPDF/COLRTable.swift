import Foundation

/// The `COLR` (colour glyph) table, version 0: a base glyph is drawn as a stack of layer glyphs, each in a colour of the `CPAL` palette, the
/// first layer at the bottom. A version 1 table keeps the version 0 records where version 0 puts them, so it is read through them (the paint
/// graph of version 1 is not used).
struct COLRTable: Equatable {
    struct Layer: Equatable {
        var glyphID: UInt16
        /// An index into the `CPAL` palette; 0xFFFF means the text's foreground colour.
        var paletteIndex: UInt16
    }

    enum COLRError: Error, Equatable {
        case unsupportedVersion(UInt16)
        case malformed(reason: String)
    }

    /// The palette index that stands for the current text colour.
    static let foregroundPaletteIndex: UInt16 = 0xFFFF

    private var layersByBaseGlyph: [UInt16: [Layer]]

    /// The base glyphs, ascending.
    var baseGlyphIDs: [UInt16] {
        layersByBaseGlyph.keys.sorted()
    }

    /// Reads the table. Out of order or repeated base glyph records, a layer run past the layer records, and a truncated array are refused.
    init(bytes: [UInt8]) throws {
        let reader = TrueTypeByteReader(table: "COLR", bytes: bytes)
        let version = try reader.uint16(at: 0)
        guard version <= 1 else { throw COLRError.unsupportedVersion(version) }
        let baseCount = try Int(reader.uint16(at: 2))
        let baseOffset = try Int(reader.uint32(at: 4))
        let layerOffset = try Int(reader.uint32(at: 8))
        let layerCount = try Int(reader.uint16(at: 12))
        try reader.requireRange(offset: baseOffset, count: baseCount * 6)
        try reader.requireRange(offset: layerOffset, count: layerCount * 4)
        var layersByBaseGlyph: [UInt16: [Layer]] = [:]
        var previous: Int = -1
        for index in 0 ..< baseCount {
            let at = baseOffset + index * 6
            let glyph = try reader.uint16(at: at)
            let first = try Int(reader.uint16(at: at + 2))
            let count = try Int(reader.uint16(at: at + 4))
            guard Int(glyph) > previous else {
                throw COLRError.malformed(reason: "base glyph records are not in ascending order at glyph \(glyph)")
            }
            previous = Int(glyph)
            guard first + count <= layerCount else {
                throw COLRError.malformed(reason: "the layers of glyph \(glyph) run past the layer records")
            }
            var layers: [Layer] = []
            for layer in first ..< first + count {
                let layerAt = layerOffset + layer * 4
                try layers.append(Layer(glyphID: reader.uint16(at: layerAt), paletteIndex: reader.uint16(at: layerAt + 2)))
            }
            layersByBaseGlyph[glyph] = layers
        }
        self.layersByBaseGlyph = layersByBaseGlyph
    }

    /// The layers of a base glyph, bottom first; nil for a glyph that has none.
    func layers(forBaseGlyph glyph: UInt16) -> [Layer]? {
        layersByBaseGlyph[glyph]
    }
}
