import Foundation

/// The `CPAL` (colour palette) table: one or more palettes of RGBA colours that the layers of a colour glyph (`COLR`) refer to by index.
/// Version 0 and the version 1 extensions that do not change the record layout are read; labels and palette types are ignored.
struct CPALTable: Equatable {
    struct Color: Equatable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
        var alpha: UInt8
    }

    enum CPALError: Error, Equatable {
        case unsupportedVersion(UInt16)
        case malformed(reason: String)
    }

    private var palettes: [[Color]]

    var paletteCount: Int {
        palettes.count
    }

    /// The number of entries in each palette.
    var entryCount: Int {
        palettes.first?.count ?? 0
    }

    /// Reads the table. A record array, a palette index or a record range outside the table is refused.
    init(bytes: [UInt8]) throws {
        let reader = TrueTypeByteReader(table: "CPAL", bytes: bytes)
        let version = try reader.uint16(at: 0)
        guard version <= 1 else { throw CPALError.unsupportedVersion(version) }
        let entryCount = try Int(reader.uint16(at: 2))
        let paletteCount = try Int(reader.uint16(at: 4))
        let recordCount = try Int(reader.uint16(at: 6))
        let recordsOffset = try Int(reader.uint32(at: 8))
        try reader.requireRange(offset: recordsOffset, count: recordCount * 4)
        var palettes: [[Color]] = []
        for palette in 0 ..< paletteCount {
            let first = try Int(reader.uint16(at: 12 + palette * 2))
            guard first + entryCount <= recordCount else {
                throw CPALError.malformed(reason: "palette \(palette) runs past the colour records")
            }
            var colors: [Color] = []
            for entry in 0 ..< entryCount {
                let at = recordsOffset + (first + entry) * 4
                // Stored blue, green, red, alpha.
                try colors.append(Color(
                    red: reader.uint8(at: at + 2), green: reader.uint8(at: at + 1), blue: reader.uint8(at: at), alpha: reader.uint8(at: at + 3),
                ))
            }
            palettes.append(colors)
        }
        self.palettes = palettes
    }

    /// The colour of an entry of a palette, nil for a palette or an entry that does not exist (the foreground index 0xFFFF included).
    func color(palette: Int = 0, entry: UInt16) -> Color? {
        guard palette >= 0, palette < palettes.count, Int(entry) < palettes[palette].count else { return nil }
        return palettes[palette][Int(entry)]
    }
}
