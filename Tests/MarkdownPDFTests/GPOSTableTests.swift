import Foundation
@testable import MarkdownPDF
import Testing

/// Structural + oracle parity witness for the GPOS mark-attachment reader. The anchors
/// it reads from the Noto Naskh fixture must match fontTools, and the offset it derives
/// (baseAnchor - markAnchor) must match the position hb-shape reports for the same mark
/// on the same base.
@Suite("GPOS table")
struct GPOSTableTests {
    private func fixture() throws -> (data: Data, metadata: TrueTypeFontParser.Metadata) {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/NotoNaskhArabic-Regular.ttf")
        let data = try Data(contentsOf: url)
        return try (data, TrueTypeFontParser().parse(data))
    }

    private func gpos(_ data: Data, _ metadata: TrueTypeFontParser.Metadata) throws -> GPOSTable {
        let record = try #require(metadata.table(named: "GPOS"))
        let start = Int(record.offset)
        return try #require(try GPOSTable(fontData: data, gposTableRange: start ..< (start + Int(record.length)), scriptTag: "arab"))
    }

    private func glyphID(_ scalar: UnicodeScalar, _ data: Data, _ metadata: TrueTypeFontParser.Metadata) throws -> UInt16 {
        let mapper = TrueTypeGlyphMapper(data: data, metadata: metadata, missingGlyphPolicy: .useNotdef)
        return try #require(mapper.map(text: String(scalar), fontSize: 1).glyphs.first?.glyphID)
    }

    @Test("Exposes the mark and mkmk feature lookups")
    func exposesMarkFeatures() throws {
        let (data, metadata) = try fixture()
        let gpos = try gpos(data, metadata)
        #expect(gpos.hasMarkPositioning)
        #expect(gpos.orderedLookupIndices(feature: "mark") == [3, 4, 5, 6])
        #expect(gpos.orderedLookupIndices(feature: "mkmk") == [7, 8, 9, 10])
    }

    @Test("Reads the fatha-on-beh anchors and derives hb-shape's exact offset")
    func fathaOnBehMatchesHarfBuzz() throws {
        let (data, metadata) = try fixture()
        let gpos = try gpos(data, metadata)
        let beh = try glyphID(#require(UnicodeScalar(0x0628)), data, metadata) // base
        let fatha = try glyphID(#require(UnicodeScalar(0x064E)), data, metadata) // mark

        // Lookup 5 covers this pair; fontTools ground truth: markAnchor (90, 442),
        // baseAnchor (365, 468).
        let attachment = try #require(gpos.attachment(lookupIndex: 5, mark: fatha, target: beh))
        #expect(attachment.markAnchor == GPOSAnchor(x: 90, y: 442))
        #expect(attachment.targetAnchor == GPOSAnchor(x: 365, y: 468))
        // The offset (baseAnchor - markAnchor) must equal hb-shape's reported @275,26.
        #expect(attachment.targetAnchor.x - attachment.markAnchor.x == 275)
        #expect(attachment.targetAnchor.y - attachment.markAnchor.y == 26)
    }

    @Test("Reports no attachment for an uncovered glyph pair")
    func noAttachmentForUncovered() throws {
        let (data, metadata) = try fixture()
        let gpos = try gpos(data, metadata)
        let beh = try glyphID(#require(UnicodeScalar(0x0628)), data, metadata)
        // beh is not a mark, so it has no mark attachment as the mark argument.
        #expect(gpos.attachment(lookupIndex: 5, mark: beh, target: beh) == nil)
    }

    @Test("A font without GPOS yields a nil reader")
    func nilWhenNoGPOS() throws {
        let data = try fixture().data
        #expect(try GPOSTable(fontData: data, gposTableRange: nil, scriptTag: "arab") == nil)
    }
}
