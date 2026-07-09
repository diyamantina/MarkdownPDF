import Foundation

/// A GPOS positioning adjustment: placement and advance deltas in font units, added to a
/// glyph's nominal position. Only the four positional fields are modelled; the device and
/// variation-index fields a `ValueRecord` may also carry are refinements not applied here.
///
/// A `ValueFormat` bitmask selects which of the fields are present in the font, in this
/// order: x placement (0x0001), y placement (0x0002), x advance (0x0004), y advance
/// (0x0008). Fields the mask omits read as zero and occupy no bytes.
struct GPOSValueRecord: Equatable {
    var xPlacement: Int
    var yPlacement: Int
    var xAdvance: Int
    var yAdvance: Int

    static let zero = GPOSValueRecord(xPlacement: 0, yPlacement: 0, xAdvance: 0, yAdvance: 0)

    /// The number of `int16` fields the `valueFormat` mask selects among the four
    /// positional bits, so a reader can skip the device/variation fields that follow.
    static func fieldCount(valueFormat: UInt16) -> Int {
        (0 ..< 4).reduce(0) { $0 + (valueFormat & (1 << $1) != 0 ? 1 : 0) }
    }

    /// The total number of `int16` slots a record with `valueFormat` occupies, counting
    /// the eight possible fields (four positional, four device/variation offsets) so the
    /// reader advances past a record whether or not it uses every field.
    static func slotCount(valueFormat: UInt16) -> Int {
        (0 ..< 8).reduce(0) { $0 + (valueFormat & (1 << $1) != 0 ? 1 : 0) }
    }
}
