import Foundation

/// A minimal reader for the GDEF (Glyph Definition) table (spec: OpenType `GDEF`),
/// exposing just the glyph-class definition. Lookups can set `IgnoreMarks` (lookup
/// flag bit 0x0008) or other class-skipping flags; honoring them, which is required to
/// match a reference shaper on marked text, needs the per-glyph class from here.
///
/// Glyph class values (OpenType `GDEF`, GlyphClassDef): 1 = base, 2 = ligature,
/// 3 = mark, 4 = component. An unlisted glyph is class 0 (unknown), treated as a base.
struct GDEFTable {
    static let markClass: UInt16 = 3

    private let glyphClassDef: OpenTypeClassDef?

    /// Whether `glyph` is a mark (GDEF glyph class 3).
    func isMark(_ glyph: UInt16) -> Bool {
        glyphClassDef?.classValue(for: glyph) == Self.markClass
    }

    /// Parses the GDEF table of `data` within `gdefTableRange`. Returns nil when the
    /// font has no GDEF table; a malformed GDEF throws (the caller degrades to no
    /// class information rather than aborting shaping).
    init?(fontData: Data, gdefTableRange: Range<Int>?) throws {
        guard let gdefTableRange else {
            return nil
        }
        let bytes = [UInt8](fontData[gdefTableRange])
        let reader = TrueTypeByteReader(table: "GDEF", bytes: bytes)
        try reader.requireRange(offset: 0, count: 6)
        let majorVersion = try reader.uint16(at: 0)
        guard majorVersion == 1 else {
            throw GSUBTable.GSUBTableError.malformed(reason: "GDEF major version must be 1")
        }
        let glyphClassDefOffset = try Int(reader.uint16(at: 4))
        glyphClassDef = glyphClassDefOffset == 0
            ? nil
            : try OpenTypeClassDef.parse(reader: reader, offset: glyphClassDefOffset)
    }
}
