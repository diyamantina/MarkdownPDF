import Foundation

/// Rewrites a CID-keyed `CFF ` program down to the glyphs a document uses, so a CJK font
/// embeds as a few kilobytes instead of the whole multi-megabyte program. The used
/// charstrings are desubroutinized (see ``CFFCharstringDesubroutinizer``) so the subset
/// carries no global or local subroutine INDEXes and needs no subroutine renumbering; the
/// charset and FDSelect are rebuilt for the compacted glyph ids, preserving each glyph's
/// original CID and Font DICT so the PDF's CID addressing is unchanged.
///
/// Only CID-keyed CFF is handled: the shape of a CJK OpenType font, and the only CFF the
/// engine embeds as a bare `CIDFontType0C` program. A name-keyed CFF embeds as a whole
/// sfnt on a different path and is left to it. Derived from the Adobe CFF specification
/// (Adobe Tech Note 5176).
///
/// The subset carries the glyph outlines and the width fields, but omits the hinting
/// entries (BlueValues, Stem/StdHW/StdVW) and the Top DICT FontBBox: these are spec-legal
/// to default, do not change which pixels a glyph covers, and only affect grid-fitting at
/// small sizes. Width fields are read as integers; a font whose `defaultWidthX`/
/// `nominalWidthX` is a real number would be misread, but the PDF's own `/W` array (from
/// `hmtx`) drives every advance, so the glyph still advances correctly.
enum CFFSubsetter {
    enum SubsetError: Error, Equatable {
        case notCIDKeyed
        case unsupportedFontMatrix
    }

    /// The subset `CFF ` program containing `usedGlyphIDs` (glyph 0, `.notdef`, is always
    /// included). Glyph ids are compacted, so the caller must map its original glyph ids to
    /// the subset's new ids; ``keptGlyphIDs`` returns that ordered mapping.
    static func subset(program: CFFFontProgram, usedGlyphIDs: Set<Int>) throws -> [UInt8] {
        guard program.isCIDKeyed else {
            throw SubsetError.notCIDKeyed
        }
        guard !program.hasExplicitFontMatrix else {
            // The subset re-emits the default FontMatrix only; a font with its own would
            // scale wrong. Decline so the caller embeds the whole (correct) program.
            throw SubsetError.unsupportedFontMatrix
        }
        let kept = keptGlyphIDs(program: program, usedGlyphIDs: usedGlyphIDs)

        // Desubroutinized charstrings, and the per-glyph CID and Font DICT for the rebuilt
        // charset and FDSelect.
        var charStrings: [[UInt8]] = []
        charStrings.reserveCapacity(kept.count)
        var cids: [Int] = []
        var fds: [Int] = []
        for oldGID in kept {
            let fd = program.fdSelect[oldGID]
            let desubroutinizer = CFFCharstringDesubroutinizer(
                globalSubrs: program.globalSubrs,
                localSubrs: program.privateDicts[fd].localSubrs,
            )
            try charStrings.append(desubroutinizer.desubroutinize(program.charStrings[oldGID]))
            cids.append(Int(program.charset[oldGID]))
            fds.append(fd)
        }

        return assemble(program: program, charStrings: charStrings, cids: cids, fds: fds)
    }

    /// The original glyph ids the subset keeps, in the subset's new-id order: glyph 0 first,
    /// then the used glyphs ascending. The index into this array is the subset glyph id.
    static func keptGlyphIDs(program: CFFFontProgram, usedGlyphIDs: Set<Int>) -> [Int] {
        let used = usedGlyphIDs.filter { $0 > 0 && $0 < program.glyphCount }.sorted()
        return [0] + used
    }

    // MARK: - Assembly

    private static func assemble(
        program: CFFFontProgram,
        charStrings: [[UInt8]],
        cids: [Int],
        fds: [Int],
    ) -> [UInt8] {
        // Re-emit the ROS strings: a standard-string SID (< 391) is referenced directly; a
        // custom SID's string is added to the subset's String INDEX and given a new SID.
        var newStrings: [[UInt8]] = []
        func resolveSID(_ sid: Int) -> Int {
            guard sid >= 391 else {
                return sid
            }
            let bytes = program.string(sid: sid) ?? []
            newStrings.append(bytes)
            return 391 + newStrings.count - 1
        }
        let registrySID = resolveSID(program.ros.count > 0 ? Int(program.ros[0]) : 0)
        let orderingSID = resolveSID(program.ros.count > 1 ? Int(program.ros[1]) : 0)
        let supplement = program.ros.count > 2 ? Int(program.ros[2]) : 0
        let cidCount = (cids.max() ?? 0) + 1

        // The Font DICTs kept (all of them; Private DICTs are tiny once subroutine-free).
        let charStringsBytes = writeIndex(charStrings)
        let charsetBytes = writeCharset(cids: cids)
        let fdSelectBytes = writeFDSelect(fds: fds)
        let privateDicts = program.privateDicts.map { writePrivateDict($0) }

        /// The Font DICT references its Private DICT by (size, absolute offset); build with a
        /// placeholder offset first so the FDArray INDEX size is fixed, then patch.
        func buildFontDicts(privateOffsets: [Int]) -> [UInt8] {
            let dicts = program.privateDicts.indices.map { index -> [UInt8] in
                var dict = encodeInt(privateDicts[index].count)
                dict += encodeOffset(privateOffsets[index])
                dict += [18] // Private
                return dict
            }
            return writeIndex(dicts)
        }
        let fdArrayPlaceholder = buildFontDicts(privateOffsets: Array(repeating: 0, count: program.privateDicts.count))

        // Fixed-size prefix pieces (Top DICT uses 5-byte offsets, so its size is invariant).
        let header: [UInt8] = [1, 0, 4, 4]
        let nameIndexBytes = writeIndex([program.fontName])
        let stringIndexBytes = writeIndex(newStrings)
        let globalSubrBytes = writeIndex([])

        func buildTopDict(charStringsOffset: Int, charsetOffset: Int, fdArrayOffset: Int, fdSelectOffset: Int) -> [UInt8] {
            var dict: [UInt8] = []
            dict += encodeInt(registrySID) + encodeInt(orderingSID) + encodeInt(supplement) + [12, 30] // ROS
            dict += encodeInt(cidCount) + [12, 34] // CIDCount
            dict += encodeOffset(charsetOffset) + [15] // charset
            dict += encodeOffset(charStringsOffset) + [17] // CharStrings
            dict += encodeOffset(fdArrayOffset) + [12, 36] // FDArray
            dict += encodeOffset(fdSelectOffset) + [12, 37] // FDSelect
            return dict
        }
        let topDictSize = buildTopDict(charStringsOffset: 0, charsetOffset: 0, fdArrayOffset: 0, fdSelectOffset: 0).count
        let topDictIndexSize = writeIndex([[UInt8](repeating: 0, count: topDictSize)]).count

        // Absolute offsets, in layout order: prefix, then CharStrings, charset, FDSelect,
        // FDArray, then the Private DICTs.
        let prefix = header.count + nameIndexBytes.count + topDictIndexSize + stringIndexBytes.count + globalSubrBytes.count
        let charStringsOffset = prefix
        let charsetOffset = charStringsOffset + charStringsBytes.count
        let fdSelectOffset = charsetOffset + charsetBytes.count
        let fdArrayOffset = fdSelectOffset + fdSelectBytes.count
        let privateBase = fdArrayOffset + fdArrayPlaceholder.count
        var privateOffsets: [Int] = []
        var running = privateBase
        for dict in privateDicts {
            privateOffsets.append(running)
            running += dict.count
        }

        let fdArrayBytes = buildFontDicts(privateOffsets: privateOffsets)
        let topDict = buildTopDict(
            charStringsOffset: charStringsOffset,
            charsetOffset: charsetOffset,
            fdArrayOffset: fdArrayOffset,
            fdSelectOffset: fdSelectOffset,
        )
        let topDictIndexBytes = writeIndex([topDict])

        var out: [UInt8] = []
        out.reserveCapacity(running)
        out += header
        out += nameIndexBytes
        out += topDictIndexBytes
        out += stringIndexBytes
        out += globalSubrBytes
        out += charStringsBytes
        out += charsetBytes
        out += fdSelectBytes
        out += fdArrayBytes
        for dict in privateDicts {
            out += dict
        }
        return out
    }

    // MARK: - Section writers

    /// A CFF INDEX: count (uint16), offSize, count+1 one-based offsets, then the objects.
    private static func writeIndex(_ objects: [[UInt8]]) -> [UInt8] {
        guard !objects.isEmpty else {
            return [0, 0]
        }
        let dataSize = objects.reduce(0) { $0 + $1.count }
        let offSize = byteWidth(for: dataSize + 1)
        var out: [UInt8] = []
        out += bigEndian16(objects.count)
        out.append(UInt8(offSize))
        var offset = 1
        appendOffset(offset, size: offSize, to: &out)
        for object in objects {
            offset += object.count
            appendOffset(offset, size: offSize, to: &out)
        }
        for object in objects {
            out += object
        }
        return out
    }

    /// Charset format 0: the format byte, then one CID (uint16) per glyph after `.notdef`
    /// (glyph 0 is implicitly CID 0 and is not stored).
    private static func writeCharset(cids: [Int]) -> [UInt8] {
        var out: [UInt8] = [0]
        for cid in cids.dropFirst() {
            out += bigEndian16(cid)
        }
        return out
    }

    /// FDSelect format 0: the format byte, then one Font DICT index per glyph.
    private static func writeFDSelect(fds: [Int]) -> [UInt8] {
        var out: [UInt8] = [0]
        for fd in fds {
            out.append(UInt8(truncatingIfNeeded: fd))
        }
        return out
    }

    /// A Private DICT carrying only the two width fields (a subset has no local subrs, so
    /// no `Subrs` operator); the widths keep the charstrings' width operands meaningful.
    private static func writePrivateDict(_ privateDict: CFFFontProgram.PrivateDict) -> [UInt8] {
        var out: [UInt8] = []
        out += encodeInt(privateDict.defaultWidthX) + [20]
        out += encodeInt(privateDict.nominalWidthX) + [21]
        return out
    }

    // MARK: - Encoding helpers

    private static func byteWidth(for value: Int) -> Int {
        if value <= 0xFF {
            1
        } else if value <= 0xFFFF {
            2
        } else if value <= 0xFFFFFF {
            3
        } else {
            4
        }
    }

    private static func appendOffset(_ value: Int, size: Int, to out: inout [UInt8]) {
        for shift in stride(from: (size - 1) * 8, through: 0, by: -8) {
            out.append(UInt8((value >> shift) & 0xFF))
        }
    }

    private static func bigEndian16(_ value: Int) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    /// A DICT integer operand in its most compact encoding.
    private static func encodeInt(_ value: Int) -> [UInt8] {
        switch value {
        case -107 ... 107:
            [UInt8(value + 139)]
        case 108 ... 1131:
            [UInt8((value - 108) / 256 + 247), UInt8((value - 108) % 256)]
        case -1131 ... -108:
            [UInt8((-value - 108) / 256 + 251), UInt8((-value - 108) % 256)]
        case -32768 ... 32767:
            [28, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        default:
            encodeOffset(value)
        }
    }

    /// A DICT integer as the fixed five-byte 32-bit form, so an offset's encoded size does
    /// not depend on its value and the layout can be computed in a single pass.
    private static func encodeOffset(_ value: Int) -> [UInt8] {
        [29, UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
