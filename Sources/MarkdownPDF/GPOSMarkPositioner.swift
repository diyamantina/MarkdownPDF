import Foundation

/// Places combining marks on their base and on preceding marks via GPOS mark
/// attachment, independent of script (Arabic harakat, Hebrew niqqud, and so on).
///
/// Given the glyph ids of a shaped run in logical order, it returns each glyph's
/// placement offset in font units: the `mark` feature attaches a mark to the nearest
/// preceding non-mark base, and `mkmk` stacks a mark on the mark immediately before it,
/// adding that mark's placement. Bases and unattached marks get a zero offset. The
/// offset is `targetAnchor - markAnchor`: in the drawn (visual) order a mark sits at
/// the same pen as its base (marks do not advance), so that offset aligns the anchors.
enum GPOSMarkPositioner {
    struct Placement: Equatable {
        var xOffset: Int
        var yOffset: Int

        static let zero = Placement(xOffset: 0, yOffset: 0)
    }

    /// The placement offset for each glyph of `glyphIDs` (parallel to the input). Marks
    /// are told from bases by `gdef`; a mark the font has no anchor for keeps a zero
    /// offset (its nominal position).
    static func placements(for glyphIDs: [UInt16], gpos: GPOSTable, gdef: GDEFTable) -> [Placement] {
        var placements = [Placement](repeating: .zero, count: glyphIDs.count)
        let isMark = glyphIDs.map { gdef.isMark($0) }

        // Attach each mark to the nearest preceding base glyph (mark-to-base).
        let markLookups = gpos.orderedLookupIndices(feature: "mark")
        if !markLookups.isEmpty {
            for index in glyphIDs.indices where isMark[index] {
                guard let baseIndex = (0 ..< index).last(where: { !isMark[$0] }) else {
                    continue
                }
                if let offset = attachmentOffset(markLookups, mark: glyphIDs[index], target: glyphIDs[baseIndex], gpos: gpos) {
                    placements[index] = Placement(xOffset: offset.x, yOffset: offset.y)
                }
            }
        }

        // Stack each mark on the mark immediately before it (mark-to-mark). Only the
        // immediately preceding glyph is a candidate: a base between two marks means
        // they sit on different letters, not stacked, so mkmk must not reach across it.
        let mkmkLookups = gpos.orderedLookupIndices(feature: "mkmk")
        if !mkmkLookups.isEmpty {
            for index in glyphIDs.indices where isMark[index] && index > 0 && isMark[index - 1] {
                let priorMark = index - 1
                if let offset = attachmentOffset(mkmkLookups, mark: glyphIDs[index], target: glyphIDs[priorMark], gpos: gpos) {
                    placements[index] = Placement(
                        xOffset: placements[priorMark].xOffset + offset.x,
                        yOffset: placements[priorMark].yOffset + offset.y,
                    )
                }
            }
        }
        return placements
    }

    /// The placement offset of `mark` onto `target` across `lookups` in order (the first
    /// lookup that attaches them wins), or nil when none does.
    private static func attachmentOffset(
        _ lookups: [UInt16],
        mark: UInt16,
        target: UInt16,
        gpos: GPOSTable,
    ) -> (x: Int, y: Int)? {
        for lookupIndex in lookups {
            if let attachment = gpos.attachment(lookupIndex: lookupIndex, mark: mark, target: target) {
                return (
                    x: Int(attachment.targetAnchor.x) - Int(attachment.markAnchor.x),
                    y: Int(attachment.targetAnchor.y) - Int(attachment.markAnchor.y),
                )
            }
        }
        return nil
    }
}
