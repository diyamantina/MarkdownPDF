import Foundation

/// A reader for the vertical metrics an OpenType font carries for top-to-bottom (CJK)
/// layout: the `vhea` vertical header's metric count and the `vmtx` per-glyph advance
/// heights. The advance height is how far the pen descends after a glyph in a vertical
/// line, the vertical analogue of `hmtx`'s advance width. Fonts run out of explicit
/// entries the same way `hmtx` does: the last `advanceHeight` repeats for every glyph past
/// `numberOfVMetrics`, which is how a CJK font gives thousands of ideographs one shared
/// full-em height cheaply.
///
/// Every read is bounds-checked through `TrueTypeByteReader`. A font without `vhea`/`vmtx`
/// has no vertical metrics; the caller then falls back to the em square.
struct VerticalMetrics: Equatable {
    enum ParseError: Error, Equatable {
        case malformed(reason: String)
    }

    /// The advance height (font units) for each glyph, length `numGlyphs`.
    let advanceHeights: [UInt16]
    /// The default vertical baseline-to-top offset (`vhea.ascender`), the descent from a
    /// glyph's vertical origin used when the font has no `VORG` table.
    let defaultVerticalOrigin: Int16

    /// The advance height for `glyphID`, or the em square when the glyph is out of range.
    func advanceHeight(glyphID: UInt16, unitsPerEm: UInt16) -> UInt16 {
        Int(glyphID) < advanceHeights.count ? advanceHeights[Int(glyphID)] : unitsPerEm
    }

    /// Parses `vhea` and `vmtx` for `numGlyphs`, or nil when the font carries neither.
    init?(vheaBytes: [UInt8]?, vmtxBytes: [UInt8]?, numGlyphs: UInt16) throws {
        guard let vheaBytes, let vmtxBytes else {
            return nil
        }
        let vhea = TrueTypeByteReader(table: "vhea", bytes: vheaBytes)
        try vhea.requireRange(offset: 0, count: 36)
        // vhea and hhea share a layout: ascender at 4, and the metric count is the last
        // uint16 of the 36-byte table (offset 34).
        defaultVerticalOrigin = try vhea.int16(at: 4)
        let numberOfVMetrics = try Int(vhea.uint16(at: 34))
        guard numberOfVMetrics > 0, numberOfVMetrics <= Int(numGlyphs) else {
            throw ParseError.malformed(reason: "numberOfVMetrics is out of range")
        }

        let vmtx = TrueTypeByteReader(table: "vmtx", bytes: vmtxBytes)
        let glyphCount = Int(numGlyphs)
        // `numberOfVMetrics` longVerMetric records (advanceHeight, topSideBearing), then a
        // topSideBearing-only tail for the remaining glyphs sharing the last advance.
        try vmtx.requireRange(offset: 0, count: numberOfVMetrics * 4)
        var heights: [UInt16] = []
        heights.reserveCapacity(glyphCount)
        var lastAdvance: UInt16 = 0
        for index in 0 ..< numberOfVMetrics {
            lastAdvance = try vmtx.uint16(at: index * 4)
            heights.append(lastAdvance)
        }
        for _ in numberOfVMetrics ..< glyphCount {
            heights.append(lastAdvance)
        }
        advanceHeights = heights
    }
}
