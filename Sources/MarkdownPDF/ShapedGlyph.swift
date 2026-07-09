import Foundation

/// One glyph in a shaping buffer, in logical order: the glyph id, the source scalar
/// range it came from (a range so a ligature can record the cluster it consumed, for a
/// later `/ToUnicode` step), and its GPOS placement offset in font units (zero for a
/// glyph the positioning did not move). Shared by the Arabic and Hebrew shapers and the
/// GSUB feature applier.
struct ShapedGlyph: Equatable {
    var glyphID: UInt16
    var sourceScalarRange: Range<Int>
    var xOffset: Int = 0
    var yOffset: Int = 0
}
