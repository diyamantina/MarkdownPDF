import Foundation

/// Reassembles a standalone single-face sfnt from a font program that may be a
/// TrueType/OpenType Collection ('ttcf').
///
/// A collection stores one table directory per face, all pointing into one shared
/// table pool, so no single face is a self-contained sfnt. To embed one face as a
/// lone `FontFile3` `/OpenType` program its tables must be rewritten into an
/// independent sfnt whose directory offsets resolve within the new file. This matters
/// for a name-keyed (non-CID) CFF face inside a collection: it is not a valid
/// `CIDFontType0C` program, so it cannot go out as a bare `CFF ` table, and stamping
/// it `Type1C` under a `CIDFontType0` descendant is a composite/simple mismatch that
/// fails PDF/A and PDF/UA validation. Wrapping the reconstructed single-face sfnt as
/// `/OpenType` is the spec-valid representation (PDF 32000-1, Table 126).
///
/// Each table's bytes are copied verbatim, so their per-table checksums stay valid;
/// the directory is rebuilt in ascending tag order with fresh 4-byte-aligned offsets
/// (the sfnt format requires both), and `head.checkSumAdjustment` is recomputed for
/// the new whole-file layout so the result is self-consistent rather than carrying the
/// collection's stale checksum.
enum SingleFaceSFNTAssembler {
    /// The magic adjustment constant from the OpenType `head` checksum algorithm.
    private static let checkSumMagic: UInt32 = 0xB1B0_AFBA

    /// Builds a standalone sfnt for the face described by `tables`, copying each table's
    /// bytes from `program`.
    ///
    /// - Parameters:
    ///   - program: The full font file (a `'ttcf'` collection or a single sfnt).
    ///   - scalerType: The face's scaler type (`OTTO` for CFF outlines).
    ///   - tables: The selected face's table records, offsets/lengths pointing into
    ///     `program`.
    /// - Throws: `TrueTypeFontError.malformedTable` if the record set is empty or a tag
    ///   is not four bytes; `TrueTypeFontError.invalidTableBounds` if a record points
    ///   outside `program`.
    static func assemble(
        program: Data,
        scalerType: UInt32,
        tables: [TrueTypeFontParser.TableRecord],
    ) throws -> Data {
        guard !tables.isEmpty else {
            throw TrueTypeFontError.malformedTable(tag: "sfnt", reason: "a single-face sfnt needs at least one table")
        }
        // The sfnt directory must list tables in ascending tag order.
        let ordered = tables.sorted { $0.tag < $1.tag }

        // Copy each table's bytes (bounds-checked) and lay them out 4-byte aligned after
        // the directory, recording the new offset each lands at.
        let directoryEnd = 12 + ordered.count * 16
        var body = Data()
        var placed: [(record: TrueTypeFontParser.TableRecord, newOffset: Int)] = []
        var cursor = directoryEnd
        for record in ordered {
            let start = Int(record.offset)
            let length = Int(record.length)
            guard start >= 0, length >= 0, start &+ length <= program.count else {
                throw TrueTypeFontError.invalidTableBounds(
                    tag: record.tag,
                    offset: record.offset,
                    length: record.length,
                    fileLength: program.count,
                )
            }
            let tableStart = program.startIndex + start
            body.append(program.subdata(in: tableStart ..< (tableStart + length)))
            placed.append((record, cursor))
            let padding = (4 - (length % 4)) % 4
            if padding > 0 {
                body.append(contentsOf: repeatElement(UInt8(0), count: padding))
            }
            cursor += length + padding
        }

        // Offset Table + directory, then the copied table bodies.
        var out = Data()
        appendUInt32(scalerType, to: &out)
        appendUInt16(UInt16(ordered.count), to: &out)
        let search = searchValues(itemCount: ordered.count, itemSize: 16)
        appendUInt16(search.searchRange, to: &out)
        appendUInt16(search.entrySelector, to: &out)
        appendUInt16(search.rangeShift, to: &out)
        for entry in placed {
            let tagBytes = Array(entry.record.tag.utf8)
            guard tagBytes.count == 4 else {
                throw TrueTypeFontError.malformedTable(tag: entry.record.tag, reason: "table tag must be four bytes")
            }
            out.append(contentsOf: tagBytes)
            appendUInt32(entry.record.checksum, to: &out)
            appendUInt32(UInt32(entry.newOffset), to: &out)
            appendUInt32(entry.record.length, to: &out)
        }
        out.append(body)

        // Recompute head.checkSumAdjustment for the new layout: zero the field, sum the
        // whole file as big-endian uint32 words, then store 0xB1B0AFBA - sum (mod 2^32).
        if let head = placed.first(where: { $0.record.tag == "head" }) {
            let field = head.newOffset + 8
            if field + 4 <= out.count {
                let base = out.startIndex + field
                for index in 0 ..< 4 {
                    out[base + index] = 0
                }
                let adjustment = checkSumMagic &- wholeFileChecksum(out)
                writeUInt32(adjustment, at: field, in: &out)
            }
        }
        return out
    }

    private static func searchValues(
        itemCount: Int,
        itemSize: Int,
    ) -> (searchRange: UInt16, entrySelector: UInt16, rangeShift: UInt16) {
        var maximumPower = 1
        var selector = 0
        while maximumPower * 2 <= itemCount {
            maximumPower *= 2
            selector += 1
        }
        let searchRange = maximumPower * itemSize
        return (
            searchRange: UInt16(searchRange),
            entrySelector: UInt16(selector),
            rangeShift: UInt16(itemCount * itemSize - searchRange),
        )
    }

    /// Sum of `data` interpreted as big-endian uint32 words, zero-padded to a multiple
    /// of four bytes (the sfnt whole-file checksum).
    private static func wholeFileChecksum(_ data: Data) -> UInt32 {
        let bytes = [UInt8](data)
        var sum: UInt32 = 0
        var offset = 0
        while offset < bytes.count {
            let byte0 = UInt32(bytes[offset])
            let byte1 = offset + 1 < bytes.count ? UInt32(bytes[offset + 1]) : 0
            let byte2 = offset + 2 < bytes.count ? UInt32(bytes[offset + 2]) : 0
            let byte3 = offset + 3 < bytes.count ? UInt32(bytes[offset + 3]) : 0
            sum = sum &+ (byte0 << 24 | byte1 << 16 | byte2 << 8 | byte3)
            offset += 4
        }
        return sum
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func writeUInt32(_ value: UInt32, at offset: Int, in data: inout Data) {
        let base = data.startIndex + offset
        data[base] = UInt8((value >> 24) & 0xFF)
        data[base + 1] = UInt8((value >> 16) & 0xFF)
        data[base + 2] = UInt8((value >> 8) & 0xFF)
        data[base + 3] = UInt8(value & 0xFF)
    }
}
