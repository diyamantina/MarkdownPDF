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

        // Refine the base placements with the mark feature's chained-context (type 8)
        // lookups, which re-position a mark in the context of its neighbours: Hebrew holam
        // is nudged when it follows a bare consonant, and a vowel and meteg under one
        // letter are split apart. Fonts without type-8 in the mark feature (Arabic) find
        // no such lookup and the run is left exactly as attached above.
        applyChainedContext(markLookups, glyphIDs: glyphIDs, isMark: isMark, gpos: gpos, into: &placements)
        return placements
    }

    /// Runs the chained-context (type 8) lookups among `lookups` in feature order,
    /// applying each match's nested lookups to `placements`. A type-1 nested lookup adds
    /// its value record; a type-4 nested lookup re-anchors the mark onto its base; a
    /// type-2 nested lookup adds the first-glyph pair value. The mark features that reach
    /// here do not set mark-ignoring lookup flags, so every glyph participates in the
    /// match (no skipping).
    private static func applyChainedContext(
        _ lookups: [UInt16],
        glyphIDs: [UInt16],
        isMark: [Bool],
        gpos: GPOSTable,
        into placements: inout [Placement],
    ) {
        for lookupIndex in lookups {
            guard case let .chainedContext(subtables) = gpos.lookupKind(at: lookupIndex) else {
                continue
            }
            for subtable in subtables {
                for start in glyphIDs.indices where matches(subtable, at: start, glyphIDs: glyphIDs) {
                    for record in subtable.sequenceLookups {
                        let position = start + record.sequenceIndex
                        guard glyphIDs.indices.contains(position) else {
                            continue
                        }
                        applyNested(
                            record.lookupIndex, at: position,
                            glyphIDs: glyphIDs, isMark: isMark, gpos: gpos, into: &placements,
                        )
                    }
                }
            }
        }
    }

    /// Whether the chained-context subtable matches with its input starting at `start`:
    /// the input, backtrack (reading backwards), and lookahead coverage sets each cover
    /// the glyph at their position.
    private static func matches(
        _ subtable: GPOSTable.ChainedContextSubtable,
        at start: Int,
        glyphIDs: [UInt16],
    ) -> Bool {
        let inputLength = subtable.inputCoverage.count
        guard inputLength > 0, start + inputLength <= glyphIDs.count else {
            return false
        }
        for offset in 0 ..< inputLength where !subtable.inputCoverage[offset].contains(glyphIDs[start + offset]) {
            return false
        }
        for (offset, coverage) in subtable.backtrackCoverage.enumerated() {
            let position = start - 1 - offset
            guard position >= 0, coverage.contains(glyphIDs[position]) else {
                return false
            }
        }
        for (offset, coverage) in subtable.lookaheadCoverage.enumerated() {
            let position = start + inputLength + offset
            guard position < glyphIDs.count, coverage.contains(glyphIDs[position]) else {
                return false
            }
        }
        return true
    }

    /// Applies the nested lookup `lookupIndex` to the glyph at `position`.
    private static func applyNested(
        _ lookupIndex: UInt16,
        at position: Int,
        glyphIDs: [UInt16],
        isMark: [Bool],
        gpos: GPOSTable,
        into placements: inout [Placement],
    ) {
        switch gpos.lookupKind(at: lookupIndex) {
        case let .single(subtables):
            for subtable in subtables {
                if let value = subtable.value(for: glyphIDs[position]) {
                    placements[position] = Placement(
                        xOffset: placements[position].xOffset + value.xPlacement,
                        yOffset: placements[position].yOffset + value.yPlacement,
                    )
                    return
                }
            }
        case .markAttachment:
            // Re-anchor the mark onto the nearest preceding base under this lookup,
            // overwriting the earlier attachment (the context selects a different anchor).
            guard let baseIndex = (0 ..< position).last(where: { !isMark[$0] }),
                  let attachment = gpos.attachment(lookupIndex: lookupIndex, mark: glyphIDs[position], target: glyphIDs[baseIndex])
            else {
                return
            }
            placements[position] = Placement(
                xOffset: Int(attachment.targetAnchor.x) - Int(attachment.markAnchor.x),
                yOffset: Int(attachment.targetAnchor.y) - Int(attachment.markAnchor.y),
            )
        case let .pair(subtables):
            guard position + 1 < glyphIDs.count else {
                return
            }
            for subtable in subtables {
                if let value = subtable.firstValue(first: glyphIDs[position], second: glyphIDs[position + 1]) {
                    placements[position] = Placement(
                        xOffset: placements[position].xOffset + value.xPlacement,
                        yOffset: placements[position].yOffset + value.yPlacement,
                    )
                    return
                }
            }
        case .chainedContext, .unsupported, .none:
            // A nested context-of-context, or a type this reader does not model, is not
            // applied; the mark keeps its base attachment.
            break
        }
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
