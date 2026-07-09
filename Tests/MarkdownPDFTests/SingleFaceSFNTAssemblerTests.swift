import Foundation
@testable import MarkdownPDF
import Testing

/// Unit witness for the single-face sfnt reconstruction (#49) that lets a name-keyed
/// CFF face inside a collection embed as a spec-valid `/OpenType` `FontFile3` instead
/// of a false-conformance `Type1C`. A collection shares its table pool across per-face
/// directories, so a lone face must be rewritten into an independent sfnt: every
/// table's bytes preserved, the directory rebuilt with valid offsets and checksums in
/// ascending tag order, and the `'ttcf'` wrapper dropped.
@Suite("Single-face sfnt assembler")
struct SingleFaceSFNTAssemblerTests {
    @Test("Rebuilds a collection face into a standalone, checksum-valid sfnt")
    func rebuildsCollectionFaceIntoStandaloneSFNT() throws {
        // Two genuinely different faces; select the second so a bug that always grabbed
        // face 0 would surface as the cmap-format mismatch checked below.
        let standalone = SyntheticTrueTypeFont.data(cmapFormat: 12)
        let collection = SyntheticTrueTypeFont.makeCollection(faces: [
            SyntheticTrueTypeFont.data(cmapFormat: 4),
            standalone,
        ])
        let faceInCollection = try TrueTypeFontParser().parse(collection, faceIndex: 1)

        let rebuilt = try SingleFaceSFNTAssembler.assemble(
            program: collection,
            scalerType: faceInCollection.scalerType,
            tables: faceInCollection.tables,
        )

        // No longer a collection: a plain sfnt whose directory sits at offset 0.
        #expect(!rebuilt.starts(with: [0x74, 0x74, 0x63, 0x66]))
        // Reparses with checksum validation on, proving every table's bytes survived
        // and the rebuilt directory offsets resolve within the new file.
        let reparsed = try TrueTypeFontParser().parse(rebuilt, validateChecksums: true)
        let single = try TrueTypeFontParser().parse(standalone, validateChecksums: true)
        #expect(reparsed.scalerType == single.scalerType)
        #expect(reparsed.tables.map(\.tag).sorted() == single.tables.map(\.tag).sorted())
        #expect(reparsed.tables.map(\.length).sorted() == single.tables.map(\.length).sorted())
        #expect(reparsed.maxp.numGlyphs == single.maxp.numGlyphs)
        // The selected face's cmap (format 12) came through, not face 0's (format 4).
        #expect(reparsed.cmap.selectedUnicodeFormat == 12)
        #expect(reparsed.head == single.head)
        #expect(reparsed.hhea == single.hhea)
        #expect(reparsed.hmtx == single.hmtx)
    }

    @Test("Writes the table directory in ascending tag order")
    func writesDirectoryInAscendingTagOrder() throws {
        let single = SyntheticTrueTypeFont.data(cmapFormat: 4)
        let metadata = try TrueTypeFontParser().parse(single)

        let rebuilt = try SingleFaceSFNTAssembler.assemble(
            program: single,
            scalerType: metadata.scalerType,
            tables: metadata.tables,
        )

        let reparsed = try TrueTypeFontParser().parse(rebuilt, validateChecksums: true)
        #expect(reparsed.tables.map(\.tag) == reparsed.tables.map(\.tag).sorted())
    }

    @Test("Rejects a table record pointing outside the program")
    func rejectsOutOfBoundsTableRecord() throws {
        let single = SyntheticTrueTypeFont.data(cmapFormat: 4)
        let metadata = try TrueTypeFontParser().parse(single)
        let outOfBounds = TrueTypeFontParser.TableRecord(
            tag: "cmap",
            checksum: 0,
            offset: UInt32(single.count),
            length: 16,
        )

        #expect(throws: TrueTypeFontError.self) {
            _ = try SingleFaceSFNTAssembler.assemble(
                program: single,
                scalerType: metadata.scalerType,
                tables: [outOfBounds],
            )
        }
    }

    @Test("Rejects an empty table set")
    func rejectsEmptyTableSet() throws {
        let single = SyntheticTrueTypeFont.data(cmapFormat: 4)
        let metadata = try TrueTypeFontParser().parse(single)

        #expect(throws: TrueTypeFontError.self) {
            _ = try SingleFaceSFNTAssembler.assemble(
                program: single,
                scalerType: metadata.scalerType,
                tables: [],
            )
        }
    }
}
