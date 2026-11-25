import Foundation
@testable import MarkdownPDF
import Testing

/// The `COLR` (version 0) and `CPAL` tables, read from bytes built here by hand. Every expected value is written out from the table layout in the
/// OpenType specification, not computed by the code under test.
@Suite("COLR and CPAL tables")
struct ColorTableTests {
    // MARK: - Byte builders

    private func u16(_ value: Int) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private func u32(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    /// A COLR v0 table: header (14 bytes), base glyph records (6 bytes each), layer records (4 bytes each).
    private func colr(version: Int = 0, bases: [(glyph: Int, first: Int, count: Int)], layers: [(glyph: Int, palette: Int)]) -> [UInt8] {
        let baseOffset = 14
        let layerOffset = baseOffset + bases.count * 6
        var bytes = u16(version) + u16(bases.count) + u32(baseOffset) + u32(layerOffset) + u16(layers.count)
        for base in bases {
            bytes += u16(base.glyph) + u16(base.first) + u16(base.count)
        }
        for layer in layers {
            bytes += u16(layer.glyph) + u16(layer.palette)
        }
        return bytes
    }

    /// A CPAL v0 table: header (12 bytes) + one u16 per palette, then the colour records (B, G, R, A).
    private func cpal(entries: Int, palettes: [[(r: Int, g: Int, b: Int, a: Int)]]) -> [UInt8] {
        let recordsOffset = 12 + palettes.count * 2
        var first: [Int] = []
        var records: [UInt8] = []
        for palette in palettes {
            first.append(records.count / 4)
            for color in palette {
                records += [UInt8(color.b), UInt8(color.g), UInt8(color.r), UInt8(color.a)]
            }
        }
        var bytes = u16(0) + u16(entries) + u16(palettes.count) + u16(records.count / 4) + u32(recordsOffset)
        for index in first {
            bytes += u16(index)
        }
        return bytes + records
    }

    // MARK: - COLR

    @Test("a hand-made COLR table gives each base glyph its layers in drawing order, with palette indices as written")
    func colrLayers() throws {
        let bytes = colr(
            bases: [(glyph: 10, first: 0, count: 2), (glyph: 12, first: 2, count: 3), (glyph: 40, first: 5, count: 1)],
            layers: [(100, 0), (101, 1), (200, 2), (201, 0xFFFF), (202, 1), (300, 3)],
        )
        let table = try COLRTable(bytes: bytes)
        #expect(table.layers(forBaseGlyph: 10) == [.init(glyphID: 100, paletteIndex: 0), .init(glyphID: 101, paletteIndex: 1)])
        #expect(table.layers(forBaseGlyph: 12)?.map(\.glyphID) == [200, 201, 202])
        #expect(table.layers(forBaseGlyph: 12)?.map(\.paletteIndex) == [2, 0xFFFF, 1])
        #expect(table.layers(forBaseGlyph: 40) == [.init(glyphID: 300, paletteIndex: 3)])
        #expect(table.baseGlyphIDs == [10, 12, 40])
        #expect(COLRTable.foregroundPaletteIndex == 0xFFFF)
    }

    @Test("a glyph that is not a base glyph has no layers: nil, never an empty list")
    func colrAbsentGlyph() throws {
        let table = try COLRTable(bytes: colr(bases: [(glyph: 10, first: 0, count: 1)], layers: [(100, 0)]))
        #expect(table.layers(forBaseGlyph: 11) == nil)
        #expect(table.layers(forBaseGlyph: 0) == nil)
        #expect(table.layers(forBaseGlyph: 65535) == nil)
    }

    @Test("a table with no base glyphs is valid and covers nothing")
    func colrEmpty() throws {
        let table = try COLRTable(bytes: colr(bases: [], layers: []))
        #expect(table.baseGlyphIDs.isEmpty && table.layers(forBaseGlyph: 1) == nil)
    }

    @Test("a version 1 table is read through its version 0 records: its base glyph and layer records sit where version 0 puts them")
    func colrVersionOne() throws {
        let table = try COLRTable(bytes: colr(version: 1, bases: [(glyph: 7, first: 0, count: 1)], layers: [(70, 5)]))
        #expect(table.layers(forBaseGlyph: 7) == [.init(glyphID: 70, paletteIndex: 5)])
    }

    @Test("every malformed COLR is refused with its reason, never read as something else", arguments: [
        ("a version the reader does not know", 2),
        ("a truncated header", 0),
        ("base records out of order", 1),
        ("a duplicate base glyph", 3),
        ("a layer run past the layer records", 4),
        ("a layer record array cut short", 5),
        ("a base record array cut short", 6),
    ] as [(String, Int)])
    func colrMalformed(_ name: String, _ kind: Int) {
        let bytes: [UInt8] = switch kind {
        case 2: colr(version: 2, bases: [(glyph: 1, first: 0, count: 1)], layers: [(9, 0)])
        case 0: Array(colr(bases: [(glyph: 1, first: 0, count: 1)], layers: [(9, 0)]).prefix(9))
        case 1: colr(bases: [(glyph: 5, first: 0, count: 1), (glyph: 3, first: 1, count: 1)], layers: [(9, 0), (8, 0)])
        case 3: colr(bases: [(glyph: 5, first: 0, count: 1), (glyph: 5, first: 1, count: 1)], layers: [(9, 0), (8, 0)])
        case 4: colr(bases: [(glyph: 5, first: 1, count: 2)], layers: [(9, 0), (8, 0)])
        case 5: Array(colr(bases: [(glyph: 5, first: 0, count: 2)], layers: [(9, 0), (8, 0)]).dropLast(3))
        default: Array(colr(bases: [(glyph: 5, first: 0, count: 1), (glyph: 6, first: 0, count: 1)], layers: [(9, 0)]).prefix(14 + 8))
        }
        #expect(throws: (any Error).self, "\(name)") { try COLRTable(bytes: bytes) }
    }

    // MARK: - CPAL

    @Test("a hand-made CPAL table gives each palette entry its colour: the records are stored blue, green, red, alpha")
    func cpalColors() throws {
        let table = try CPALTable(bytes: cpal(entries: 3, palettes: [
            [(r: 255, g: 0, b: 0, a: 255), (r: 0, g: 128, b: 255, a: 255), (r: 10, g: 20, b: 30, a: 40)],
            [(r: 1, g: 2, b: 3, a: 4), (r: 5, g: 6, b: 7, a: 8), (r: 9, g: 10, b: 11, a: 12)],
        ]))
        #expect(table.paletteCount == 2 && table.entryCount == 3)
        #expect(table.color(palette: 0, entry: 0) == .init(red: 255, green: 0, blue: 0, alpha: 255))
        #expect(table.color(palette: 0, entry: 1) == .init(red: 0, green: 128, blue: 255, alpha: 255))
        #expect(table.color(palette: 0, entry: 2) == .init(red: 10, green: 20, blue: 30, alpha: 40))
        #expect(table.color(palette: 1, entry: 0) == .init(red: 1, green: 2, blue: 3, alpha: 4))
        #expect(table.color(palette: 1, entry: 2) == .init(red: 9, green: 10, blue: 11, alpha: 12))
    }

    @Test("an entry or a palette that does not exist is nil, including the foreground index 0xFFFF")
    func cpalAbsent() throws {
        let table = try CPALTable(bytes: cpal(entries: 1, palettes: [[(r: 1, g: 2, b: 3, a: 255)]]))
        #expect(table.color(palette: 0, entry: 1) == nil)
        #expect(table.color(palette: 0, entry: 0xFFFF) == nil)
        #expect(table.color(palette: 1, entry: 0) == nil)
        #expect(table.color(palette: -1, entry: 0) == nil)
    }

    @Test("every malformed CPAL is refused", arguments: [0, 1, 2, 3] as [Int])
    func cpalMalformed(kind: Int) {
        let good = cpal(entries: 2, palettes: [[(r: 1, g: 2, b: 3, a: 4), (r: 5, g: 6, b: 7, a: 8)]])
        var bytes = good
        switch kind {
        case 0: bytes = Array(good.prefix(8)) // a truncated header
        case 1: bytes = Array(good.dropLast(2)) // the last colour record cut short
        case 2: bytes = u16(0) + u16(2) + u16(1) + u16(1) + u32(14) + u16(0) + [1, 2, 3, 4] // an entry count larger than the records
        default: bytes = u16(5) + Array(good.dropFirst(2)) // a version the reader does not know
        }
        #expect(throws: (any Error).self) { try CPALTable(bytes: bytes) }
    }

    // MARK: - The real font (when the file is at hand)

    @Test("the Twemoji COLR font: its COLR and CPAL parse, and the lightbulb is a base glyph with layers whose palette indices exist")
    func twemojiTables() throws {
        // The bundled face, unless the variable `TWEMOJI_FONT` names another file.
        let named = ProcessInfo.processInfo.environment["TWEMOJI_FONT"].flatMap { FileManager.default.contents(atPath: $0) }
        let data = try #require(named ?? BundledFonts.twemoji?.data, "no colour face to read")
        let bytes = [UInt8](data)
        let tables = try TrueTypeFontParser().parse(data).tables
        func slice(_ tag: String) throws -> [UInt8] {
            let record = try #require(tables.first { $0.tag == tag })
            return Array(bytes[Int(record.offset) ..< Int(record.offset + record.length)])
        }
        let colrTable = try COLRTable(bytes: slice("COLR"))
        let cpalTable = try CPALTable(bytes: slice("CPAL"))
        #expect(colrTable.baseGlyphIDs.count > 1000)
        #expect(cpalTable.paletteCount >= 1)
        for base in colrTable.baseGlyphIDs.prefix(500) {
            for layer in try #require(colrTable.layers(forBaseGlyph: base)) where layer.paletteIndex != COLRTable.foregroundPaletteIndex {
                #expect(cpalTable.color(palette: 0, entry: layer.paletteIndex) != nil, "base \(base) layer \(layer.glyphID)")
            }
        }
    }
}
