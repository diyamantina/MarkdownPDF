import Foundation
@testable import MarkdownPDF
import Testing

/// Crafted-byte reproductions for the GPOS value-record decoding that a real font's
/// narrow value formats cannot exercise: multi-slot SinglePos format 2 strides,
/// multi-record PairPos format 1 strides, class-matrix strides, and the device-offset
/// slots that occupy bytes without carrying a placement. Built from hand-assembled bytes
/// so a wrong stride is caught here even when no bundled font would reveal it.
@Suite("GPOS value-record strides")
struct GPOSValueRecordStrideTests {
    private final class Builder {
        var bytes: [UInt8] = []
        var count: Int {
            bytes.count
        }

        func u16(_ value: Int) {
            bytes.append(UInt8((value >> 8) & 0xFF))
            bytes.append(UInt8(value & 0xFF))
        }

        func s16(_ value: Int) {
            u16(value & 0xFFFF)
        }

        func tag(_ text: String) {
            bytes.append(contentsOf: Array(text.utf8))
        }

        func patch16(at offset: Int, _ value: Int) {
            bytes[offset] = UInt8((value >> 8) & 0xFF)
            bytes[offset + 1] = UInt8(value & 0xFF)
        }
    }

    /// A minimal GPOS with script `hebr`, feature `mark`, and four lookups:
    /// 0: SinglePos fmt 2, valueFormat 0x0005 (xPlacement+xAdvance), two values.
    /// 1: PairPos fmt 1, vf1 0x0005, vf2 0x0002, one pair set with two records.
    /// 2: PairPos fmt 2, vf1 0x0001, vf2 0x0001, 2x2 class matrix.
    /// 3: SinglePos fmt 2, valueFormat 0x0011 (xPlacement + xPlaDevice), two values.
    private static func craftedGPOS() -> Data {
        let b = Builder()
        // Header
        b.u16(1)
        b.u16(0) // version 1.0
        let scriptListSlot = b.count
        b.u16(0)
        let featureListSlot = b.count
        b.u16(0)
        let lookupListSlot = b.count
        b.u16(0)

        // ScriptList
        b.patch16(at: scriptListSlot, b.count)
        let scriptList = b.count
        b.u16(1) // scriptCount
        b.tag("hebr")
        b.u16(scriptList + 10 - scriptList) // wrong placeholder, patch below
        let scriptRecordOffsetSlot = b.count - 2
        b.patch16(at: scriptRecordOffsetSlot, b.count - scriptList)
        // Script table
        let script = b.count
        b.u16(4) // defaultLangSysOffset (right after this table's 4-byte header)
        b.u16(0) // langSysCount
        precondition(b.count == script + 4)
        // LangSys
        b.u16(0) // lookupOrderOffset
        b.u16(0xFFFF) // requiredFeatureIndex
        b.u16(1) // featureIndexCount
        b.u16(0) // feature index 0

        // FeatureList
        b.patch16(at: featureListSlot, b.count)
        let featureList = b.count
        b.u16(1) // featureCount
        b.tag("mark")
        b.u16(8) // offset to feature table from featureList (2 + 6 record bytes)
        precondition(b.count - featureList == 8)
        b.u16(0) // featureParamsOffset
        b.u16(4) // lookupIndexCount
        b.u16(0)
        b.u16(1)
        b.u16(2)
        b.u16(3)

        // LookupList
        b.patch16(at: lookupListSlot, b.count)
        let lookupList = b.count
        b.u16(4)
        let lookupOffsetSlots = (0 ..< 4).map { index -> Int in
            _ = index
            let slot = b.count
            b.u16(0)
            return slot
        }

        // Lookup 0: SinglePos fmt 2, vf 0x0005
        b.patch16(at: lookupOffsetSlots[0], b.count - lookupList)
        var lookup = b.count
        b.u16(1)
        b.u16(0)
        b.u16(1)
        b.u16(8) // type, flag, subtableCount, offset
        precondition(b.count == lookup + 8)
        var sub = b.count
        b.u16(2) // format 2
        let cov0Slot = b.count
        b.u16(0)
        b.u16(0x0005) // valueFormat: xPlacement + xAdvance
        b.u16(2) // valueCount
        b.s16(7)
        b.s16(9) // value[0]: xpl 7, xadv 9
        b.s16(-3)
        b.s16(4) // value[1]: xpl -3, xadv 4
        b.patch16(at: cov0Slot, b.count - sub)
        b.u16(1)
        b.u16(2)
        b.u16(100)
        b.u16(101) // coverage fmt1, glyphs 100, 101

        // Lookup 1: PairPos fmt 1, vf1 0x0005 (2 slots), vf2 0x0002 (1 slot)
        b.patch16(at: lookupOffsetSlots[1], b.count - lookupList)
        lookup = b.count
        b.u16(2)
        b.u16(0)
        b.u16(1)
        b.u16(8)
        sub = b.count
        b.u16(1) // format 1
        let cov1Slot = b.count
        b.u16(0)
        b.u16(0x0005) // vf1
        b.u16(0x0002) // vf2
        b.u16(1) // pairSetCount
        let pairSetSlot = b.count
        b.u16(0)
        b.patch16(at: pairSetSlot, b.count - sub)
        // PairSet: 2 records, record size 2 + (2+1)*2 = 8
        b.u16(2)
        b.u16(300)
        b.s16(11)
        b.s16(13)
        b.s16(17) // second 300: v1(xpl 11, xadv 13), v2(ypl 17)
        b.u16(301)
        b.s16(-5)
        b.s16(6)
        b.s16(-7) // second 301: v1(xpl -5, xadv 6), v2(ypl -7)
        b.patch16(at: cov1Slot, b.count - sub)
        b.u16(1)
        b.u16(1)
        b.u16(200) // coverage: glyph 200

        // Lookup 2: PairPos fmt 2, vf1 0x0001, vf2 0x0001, 2x2 matrix
        b.patch16(at: lookupOffsetSlots[2], b.count - lookupList)
        lookup = b.count
        b.u16(2)
        b.u16(0)
        b.u16(1)
        b.u16(8)
        sub = b.count
        b.u16(2) // format 2
        let cov2Slot = b.count
        b.u16(0)
        b.u16(0x0001)
        b.u16(0x0001) // vf1, vf2
        let cd1Slot = b.count
        b.u16(0)
        let cd2Slot = b.count
        b.u16(0)
        b.u16(2)
        b.u16(2) // class1Count, class2Count
        // matrix rows: each cell = v1 (1 slot) + v2 (1 slot) = 4 bytes
        b.s16(10)
        b.s16(-10) // [0][0]
        b.s16(20)
        b.s16(-20) // [0][1]
        b.s16(30)
        b.s16(-30) // [1][0]
        b.s16(40)
        b.s16(-40) // [1][1]
        b.patch16(at: cd1Slot, b.count - sub)
        b.u16(1)
        b.u16(400)
        b.u16(1)
        b.u16(1) // classdef fmt1: glyph 400 -> class 1
        b.patch16(at: cd2Slot, b.count - sub)
        b.u16(2)
        b.u16(1)
        b.u16(500)
        b.u16(501)
        b.u16(1) // classdef fmt2: 500-501 -> class 1
        b.patch16(at: cov2Slot, b.count - sub)
        b.u16(1)
        b.u16(1)
        b.u16(400) // coverage: glyph 400

        // Lookup 3: SinglePos fmt 2, vf 0x0011 (xPlacement + xPlaDevice)
        b.patch16(at: lookupOffsetSlots[3], b.count - lookupList)
        lookup = b.count
        b.u16(1)
        b.u16(0)
        b.u16(1)
        b.u16(8)
        sub = b.count
        b.u16(2)
        let cov3Slot = b.count
        b.u16(0)
        b.u16(0x0011) // xPlacement + xPlaDevice: 2 slots, 1 positional field
        b.u16(2)
        b.s16(21)
        b.u16(0x0044) // value[0]: xpl 21, device offset junk
        b.s16(-8)
        b.u16(0x0055) // value[1]: xpl -8, device offset junk
        b.patch16(at: cov3Slot, b.count - sub)
        b.u16(1)
        b.u16(2)
        b.u16(600)
        b.u16(601)

        return Data(b.bytes)
    }

    @Test("Value-record strides decode exactly (multi-slot, multi-record, device bits)")
    func strides() throws {
        let gposData = Self.craftedGPOS()
        let gpos = try #require(try GPOSTable(fontData: gposData, gposTableRange: 0 ..< gposData.count, scriptTag: "hebr"))

        // fieldCount / slotCount
        #expect(GPOSValueRecord.fieldCount(valueFormat: 0x0005) == 2)
        #expect(GPOSValueRecord.slotCount(valueFormat: 0x0005) == 2)
        #expect(GPOSValueRecord.fieldCount(valueFormat: 0x0011) == 1)
        #expect(GPOSValueRecord.slotCount(valueFormat: 0x0011) == 2)
        #expect(GPOSValueRecord.slotCount(valueFormat: 0x00FF) == 8)

        // Lookup 0: SinglePos fmt 2 stride over 2-slot records
        guard case let .single(single) = gpos.lookupKind(at: 0) else {
            Issue.record("lookup 0 must parse as single")
            return
        }
        #expect(single[0].value(for: 100) == GPOSValueRecord(xPlacement: 7, yPlacement: 0, xAdvance: 9, yAdvance: 0))
        #expect(single[0].value(for: 101) == GPOSValueRecord(xPlacement: -3, yPlacement: 0, xAdvance: 4, yAdvance: 0))
        #expect(single[0].value(for: 102) == nil)

        // Lookup 1: PairPos fmt 1 record stride 2 + (slots1+slots2)*2
        guard case let .pair(pair1) = gpos.lookupKind(at: 1) else {
            Issue.record("lookup 1 must parse as pair")
            return
        }
        #expect(pair1[0].pairValues(first: 200, second: 300) == GPOSTable.PairPosSubtable.PairCell(
            first: GPOSValueRecord(xPlacement: 11, yPlacement: 0, xAdvance: 13, yAdvance: 0),
            second: GPOSValueRecord(xPlacement: 0, yPlacement: 17, xAdvance: 0, yAdvance: 0),
        ))
        #expect(pair1[0].pairValues(first: 200, second: 301) == GPOSTable.PairPosSubtable.PairCell(
            first: GPOSValueRecord(xPlacement: -5, yPlacement: 0, xAdvance: 6, yAdvance: 0),
            second: GPOSValueRecord(xPlacement: 0, yPlacement: -7, xAdvance: 0, yAdvance: 0),
        ))
        #expect(pair1[0].pairValues(first: 200, second: 302) == nil)

        // Lookup 2: PairPos fmt 2 class-matrix stride (v1+v2 per cell)
        guard case let .pair(pair2) = gpos.lookupKind(at: 2) else {
            Issue.record("lookup 2 must parse as pair")
            return
        }
        #expect(pair2[0].pairValues(first: 400, second: 500)?.first == GPOSValueRecord(xPlacement: 40, yPlacement: 0, xAdvance: 0, yAdvance: 0))
        #expect(pair2[0].pairValues(first: 400, second: 500)?.second == GPOSValueRecord(xPlacement: -40, yPlacement: 0, xAdvance: 0, yAdvance: 0))
        #expect(pair2[0].pairValues(first: 400, second: 999)?.first == GPOSValueRecord(xPlacement: 30, yPlacement: 0, xAdvance: 0, yAdvance: 0))

        // Lookup 3: device-offset slots are skipped, positional field still lands
        guard case let .single(single3) = gpos.lookupKind(at: 3) else {
            Issue.record("lookup 3 must parse as single")
            return
        }
        #expect(single3[0].value(for: 600) == GPOSValueRecord(xPlacement: 21, yPlacement: 0, xAdvance: 0, yAdvance: 0))
        #expect(single3[0].value(for: 601) == GPOSValueRecord(xPlacement: -8, yPlacement: 0, xAdvance: 0, yAdvance: 0))
    }
}
