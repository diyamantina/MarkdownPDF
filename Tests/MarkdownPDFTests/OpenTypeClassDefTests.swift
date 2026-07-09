import Foundation
@testable import MarkdownPDF
import Testing

/// Unit witness for the shared OpenType ClassDef reader (formats 1 and 2), the primitive
/// GDEF glyph classes and class-based contextual lookups are built on.
@Suite("OpenType ClassDef")
struct OpenTypeClassDefTests {
    @Test("Format 1 assigns classes to a contiguous glyph run, 0 elsewhere")
    func format1ContiguousRun() throws {
        // format=1, startGlyphID=10, glyphCount=3, classValues=[1, 2, 3].
        let bytes: [UInt8] = [0, 1, 0, 10, 0, 3, 0, 1, 0, 2, 0, 3]
        let reader = TrueTypeByteReader(table: "test", bytes: bytes)
        let classDef = try OpenTypeClassDef.parse(reader: reader, offset: 0)

        #expect(classDef.classValue(for: 9) == 0)
        #expect(classDef.classValue(for: 10) == 1)
        #expect(classDef.classValue(for: 11) == 2)
        #expect(classDef.classValue(for: 12) == 3)
        #expect(classDef.classValue(for: 13) == 0)
    }

    @Test("Format 2 assigns classes by range, 0 outside every range")
    func format2Ranges() throws {
        // format=2, rangeCount=2, ranges: 20...25 -> class 4, 30...30 -> class 1.
        let bytes: [UInt8] = [0, 2, 0, 2, 0, 20, 0, 25, 0, 4, 0, 30, 0, 30, 0, 1]
        let reader = TrueTypeByteReader(table: "test", bytes: bytes)
        let classDef = try OpenTypeClassDef.parse(reader: reader, offset: 0)

        #expect(classDef.classValue(for: 19) == 0)
        #expect(classDef.classValue(for: 20) == 4)
        #expect(classDef.classValue(for: 23) == 4)
        #expect(classDef.classValue(for: 25) == 4)
        #expect(classDef.classValue(for: 26) == 0)
        #expect(classDef.classValue(for: 30) == 1)
        #expect(classDef.classValue(for: 31) == 0)
    }

    @Test("Rejects an unordered format-2 range")
    func rejectsUnorderedRange() throws {
        // A range whose end precedes its start (25...20) is malformed.
        let bytes: [UInt8] = [0, 2, 0, 1, 0, 25, 0, 20, 0, 4]
        let reader = TrueTypeByteReader(table: "test", bytes: bytes)
        #expect(throws: GSUBTable.GSUBTableError.self) {
            _ = try OpenTypeClassDef.parse(reader: reader, offset: 0)
        }
    }

    @Test("Rejects an unknown ClassDef format")
    func rejectsUnknownFormat() throws {
        let bytes: [UInt8] = [0, 3, 0, 0]
        let reader = TrueTypeByteReader(table: "test", bytes: bytes)
        #expect(throws: GSUBTable.GSUBTableError.self) {
            _ = try OpenTypeClassDef.parse(reader: reader, offset: 0)
        }
    }
}
