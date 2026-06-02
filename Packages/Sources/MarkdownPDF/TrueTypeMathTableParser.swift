import Foundation

struct TrueTypeMathTableParser {
    private let numGlyphs: UInt16
    private let reader: TrueTypeByteReader

    init(bytes: [UInt8], numGlyphs: UInt16) {
        self.numGlyphs = numGlyphs
        reader = TrueTypeByteReader(table: "MATH", bytes: bytes)
    }

    func parse() throws -> TrueTypeMathTable {
        try reader.requireRange(offset: 0, count: 10)
        let majorVersion = try reader.uint16(at: 0)
        let minorVersion = try reader.uint16(at: 2)
        guard majorVersion == 1, minorVersion == 0 else {
            throw malformed("version must be 1.0")
        }

        let constantsOffset = try requiredSubtableOffset(
            reader.uint16(at: 4),
            parentStart: 0,
            name: "MathConstants",
            minimumSize: 214,
        )
        let glyphInfoOffset = try requiredSubtableOffset(
            reader.uint16(at: 6),
            parentStart: 0,
            name: "MathGlyphInfo",
            minimumSize: 8,
        )
        let variantsOffset = try requiredSubtableOffset(
            reader.uint16(at: 8),
            parentStart: 0,
            name: "MathVariants",
            minimumSize: 10,
        )

        return try TrueTypeMathTable(
            majorVersion: majorVersion,
            minorVersion: minorVersion,
            constants: parseConstants(at: constantsOffset),
            glyphInfo: parseGlyphInfo(at: glyphInfoOffset),
            variants: parseVariants(at: variantsOffset),
        )
    }

    private func parseConstants(at offset: Int) throws -> TrueTypeMathTable.Constants {
        try reader.requireRange(offset: offset, count: 214)
        var valueOffset = offset + 8
        var values: [TrueTypeMathTable.Constants.ValueName: TrueTypeMathTable.MathValueRecord] = [:]
        for name in TrueTypeMathTable.Constants.ValueName.allCases {
            values[name] = try mathValueRecord(at: valueOffset, parentStart: offset, parentName: "MathConstants")
            valueOffset += 4
        }

        return try TrueTypeMathTable.Constants(
            scriptPercentScaleDown: reader.int16(at: offset),
            scriptScriptPercentScaleDown: reader.int16(at: offset + 2),
            delimitedSubFormulaMinHeight: reader.uint16(at: offset + 4),
            displayOperatorMinHeight: reader.uint16(at: offset + 6),
            values: values,
            radicalDegreeBottomRaisePercent: reader.int16(at: valueOffset),
        )
    }

    private func parseGlyphInfo(at offset: Int) throws -> TrueTypeMathTable.GlyphInfo {
        try reader.requireRange(offset: offset, count: 8)
        let italicsOffset = try optionalSubtableOffset(
            reader.uint16(at: offset),
            parentStart: offset,
            name: "MathItalicsCorrectionInfo",
            minimumSize: 4,
        )
        let topAccentOffset = try optionalSubtableOffset(
            reader.uint16(at: offset + 2),
            parentStart: offset,
            name: "MathTopAccentAttachment",
            minimumSize: 4,
        )
        let extendedShapeOffset = try optionalSubtableOffset(
            reader.uint16(at: offset + 4),
            parentStart: offset,
            name: "ExtendedShapeCoverage",
            minimumSize: 4,
        )
        let kernInfoOffset = try optionalSubtableOffset(
            reader.uint16(at: offset + 6),
            parentStart: offset,
            name: "MathKernInfo",
            minimumSize: 4,
        )

        return try TrueTypeMathTable.GlyphInfo(
            italicsCorrections: italicsOffset.map { try parseGlyphValues(at: $0, name: "MathItalicsCorrectionInfo") } ?? [],
            topAccentAttachments: topAccentOffset.map { try parseGlyphValues(at: $0, name: "MathTopAccentAttachment") } ?? [],
            extendedShapeGlyphIDs: extendedShapeOffset.map { try coverageGlyphIDs(at: $0) } ?? [],
            mathKerns: kernInfoOffset.map(parseMathKernInfo) ?? [],
        )
    }

    private func parseGlyphValues(
        at offset: Int,
        name: String,
    ) throws -> [TrueTypeMathTable.GlyphValueRecord] {
        try reader.requireRange(offset: offset, count: 4)
        let coverageOffset = try requiredSubtableOffset(
            reader.uint16(at: offset),
            parentStart: offset,
            name: "\(name) coverage",
            minimumSize: 4,
        )
        let count = try Int(reader.uint16(at: offset + 2))
        try reader.requireRange(offset: offset + 4, count: count * 4)
        let glyphIDs = try coverageGlyphIDs(at: coverageOffset)
        guard glyphIDs.count == count else {
            throw malformed("\(name) count must match its coverage glyph count")
        }

        return try glyphIDs.enumerated().map { index, glyphID in
            try TrueTypeMathTable.GlyphValueRecord(
                glyphID: glyphID,
                value: mathValueRecord(
                    at: offset + 4 + index * 4,
                    parentStart: offset,
                    parentName: name,
                ),
            )
        }
    }

    private func parseMathKernInfo(at offset: Int) throws -> [TrueTypeMathTable.MathKernRecord] {
        try reader.requireRange(offset: offset, count: 4)
        let coverageOffset = try requiredSubtableOffset(
            reader.uint16(at: offset),
            parentStart: offset,
            name: "MathKernInfo coverage",
            minimumSize: 4,
        )
        let count = try Int(reader.uint16(at: offset + 2))
        try reader.requireRange(offset: offset + 4, count: count * 8)
        let glyphIDs = try coverageGlyphIDs(at: coverageOffset)
        guard glyphIDs.count == count else {
            throw malformed("MathKernInfo count must match its coverage glyph count")
        }

        return try glyphIDs.enumerated().map { index, glyphID in
            let recordOffset = offset + 4 + index * 8
            return try TrueTypeMathTable.MathKernRecord(
                glyphID: glyphID,
                topRight: parseOptionalMathKern(
                    offsetValue: reader.uint16(at: recordOffset),
                    parentStart: offset,
                    name: "topRightMathKern",
                ),
                topLeft: parseOptionalMathKern(
                    offsetValue: reader.uint16(at: recordOffset + 2),
                    parentStart: offset,
                    name: "topLeftMathKern",
                ),
                bottomRight: parseOptionalMathKern(
                    offsetValue: reader.uint16(at: recordOffset + 4),
                    parentStart: offset,
                    name: "bottomRightMathKern",
                ),
                bottomLeft: parseOptionalMathKern(
                    offsetValue: reader.uint16(at: recordOffset + 6),
                    parentStart: offset,
                    name: "bottomLeftMathKern",
                ),
            )
        }
    }

    private func parseOptionalMathKern(
        offsetValue: UInt16,
        parentStart: Int,
        name: String,
    ) throws -> TrueTypeMathTable.MathKern? {
        guard let offset = try optionalSubtableOffset(
            offsetValue,
            parentStart: parentStart,
            name: name,
            minimumSize: 2,
        ) else {
            return nil
        }
        try reader.requireRange(offset: offset, count: 2)
        let heightCount = try Int(reader.uint16(at: offset))
        try reader.requireRange(offset: offset + 2, count: heightCount * 4 + (heightCount + 1) * 4)

        let correctionHeights = try (0 ..< heightCount).map { index in
            try mathValueRecord(at: offset + 2 + index * 4, parentStart: offset, parentName: name)
        }
        let kernValues = try (0 ... heightCount).map { index in
            try mathValueRecord(
                at: offset + 2 + heightCount * 4 + index * 4,
                parentStart: offset,
                parentName: name,
            )
        }
        guard zip(correctionHeights, correctionHeights.dropFirst()).allSatisfy({ $0.value < $1.value }) else {
            throw malformed("\(name) correction heights must be strictly increasing")
        }

        return TrueTypeMathTable.MathKern(correctionHeights: correctionHeights, kernValues: kernValues)
    }

    private func parseVariants(at offset: Int) throws -> TrueTypeMathTable.Variants {
        try reader.requireRange(offset: offset, count: 10)
        let minConnectorOverlap = try reader.uint16(at: offset)
        let verticalCoverageOffset = try optionalSubtableOffset(
            reader.uint16(at: offset + 2),
            parentStart: offset,
            name: "vertical variants coverage",
            minimumSize: 4,
        )
        let horizontalCoverageOffset = try optionalSubtableOffset(
            reader.uint16(at: offset + 4),
            parentStart: offset,
            name: "horizontal variants coverage",
            minimumSize: 4,
        )
        let verticalCount = try Int(reader.uint16(at: offset + 6))
        let horizontalCount = try Int(reader.uint16(at: offset + 8))
        try reader.requireRange(offset: offset + 10, count: (verticalCount + horizontalCount) * 2)

        let verticalGlyphIDs = try coverageGlyphIDs(
            coverageOffset: verticalCoverageOffset,
            expectedCount: verticalCount,
            name: "vertical variants",
        )
        let horizontalGlyphIDs = try coverageGlyphIDs(
            coverageOffset: horizontalCoverageOffset,
            expectedCount: horizontalCount,
            name: "horizontal variants",
        )

        let verticalConstructions = try parseConstructions(
            glyphIDs: verticalGlyphIDs,
            offsetsStart: offset + 10,
            parentStart: offset,
            name: "vertical variants",
        )
        let horizontalConstructions = try parseConstructions(
            glyphIDs: horizontalGlyphIDs,
            offsetsStart: offset + 10 + verticalCount * 2,
            parentStart: offset,
            name: "horizontal variants",
        )

        return TrueTypeMathTable.Variants(
            minConnectorOverlap: minConnectorOverlap,
            verticalConstructions: verticalConstructions,
            horizontalConstructions: horizontalConstructions,
        )
    }

    private func coverageGlyphIDs(
        coverageOffset: Int?,
        expectedCount: Int,
        name: String,
    ) throws -> [UInt16] {
        guard let coverageOffset else {
            guard expectedCount == 0 else {
                throw malformed("\(name) coverage is null but count is positive")
            }
            return []
        }
        let glyphIDs = try coverageGlyphIDs(at: coverageOffset)
        guard glyphIDs.count == expectedCount else {
            throw malformed("\(name) count must match its coverage glyph count")
        }
        return glyphIDs
    }

    private func parseConstructions(
        glyphIDs: [UInt16],
        offsetsStart: Int,
        parentStart: Int,
        name: String,
    ) throws -> [TrueTypeMathTable.GlyphConstruction] {
        try glyphIDs.enumerated().map { index, glyphID in
            let constructionOffset = try requiredSubtableOffset(
                reader.uint16(at: offsetsStart + index * 2),
                parentStart: parentStart,
                name: "\(name) construction",
                minimumSize: 4,
            )
            return try parseGlyphConstruction(at: constructionOffset, glyphID: glyphID)
        }
    }

    private func parseGlyphConstruction(
        at offset: Int,
        glyphID: UInt16,
    ) throws -> TrueTypeMathTable.GlyphConstruction {
        try reader.requireRange(offset: offset, count: 4)
        let assemblyOffsetValue = try reader.uint16(at: offset)
        let variantCount = try Int(reader.uint16(at: offset + 2))
        try reader.requireRange(offset: offset + 4, count: variantCount * 4)

        let variants = try (0 ..< variantCount).map { index in
            let variantOffset = offset + 4 + index * 4
            return try TrueTypeMathTable.GlyphVariant(
                glyphID: checkedGlyphID(at: variantOffset, name: "variant glyph"),
                advanceMeasurement: reader.uint16(at: variantOffset + 2),
            )
        }
        let assembly = try parseOptionalGlyphAssembly(offsetValue: assemblyOffsetValue, parentStart: offset)
        return TrueTypeMathTable.GlyphConstruction(glyphID: glyphID, assembly: assembly, variants: variants)
    }

    private func parseOptionalGlyphAssembly(
        offsetValue: UInt16,
        parentStart: Int,
    ) throws -> TrueTypeMathTable.GlyphAssembly? {
        guard let offset = try optionalSubtableOffset(
            offsetValue,
            parentStart: parentStart,
            name: "GlyphAssembly",
            minimumSize: 6,
        ) else {
            return nil
        }
        let italicsCorrection = try mathValueRecord(at: offset, parentStart: offset, parentName: "GlyphAssembly")
        let partCount = try Int(reader.uint16(at: offset + 4))
        try reader.requireRange(offset: offset + 6, count: partCount * 10)
        let parts = try (0 ..< partCount).map { index in
            let partOffset = offset + 6 + index * 10
            return try TrueTypeMathTable.GlyphPart(
                glyphID: checkedGlyphID(at: partOffset, name: "assembly part glyph"),
                startConnectorLength: reader.uint16(at: partOffset + 2),
                endConnectorLength: reader.uint16(at: partOffset + 4),
                fullAdvance: reader.uint16(at: partOffset + 6),
                partFlags: reader.uint16(at: partOffset + 8),
            )
        }
        return TrueTypeMathTable.GlyphAssembly(italicsCorrection: italicsCorrection, parts: parts)
    }

    private func coverageGlyphIDs(at offset: Int) throws -> [UInt16] {
        try reader.requireRange(offset: offset, count: 4)
        let format = try reader.uint16(at: offset)
        switch format {
        case 1:
            let count = try Int(reader.uint16(at: offset + 2))
            try reader.requireRange(offset: offset + 4, count: count * 2)
            return try (0 ..< count).map { index in
                try checkedGlyphID(at: offset + 4 + index * 2, name: "coverage glyph")
            }
        case 2:
            let rangeCount = try Int(reader.uint16(at: offset + 2))
            try reader.requireRange(offset: offset + 4, count: rangeCount * 6)
            var glyphIDs: [UInt16] = []
            for index in 0 ..< rangeCount {
                let rangeOffset = offset + 4 + index * 6
                let startGlyphID = try checkedGlyphID(at: rangeOffset, name: "coverage start glyph")
                let endGlyphID = try checkedGlyphID(at: rangeOffset + 2, name: "coverage end glyph")
                let startCoverageIndex = try Int(reader.uint16(at: rangeOffset + 4))
                guard startGlyphID <= endGlyphID else {
                    throw malformed("coverage range start exceeds end")
                }
                guard startCoverageIndex == glyphIDs.count else {
                    throw malformed("coverage range start index is not contiguous")
                }
                glyphIDs.append(contentsOf: startGlyphID ... endGlyphID)
            }
            return glyphIDs
        default:
            throw malformed("coverage format \(format) is unsupported")
        }
    }

    private func mathValueRecord(
        at offset: Int,
        parentStart: Int,
        parentName: String,
    ) throws -> TrueTypeMathTable.MathValueRecord {
        try reader.requireRange(offset: offset, count: 4)
        let value = try reader.int16(at: offset)
        let deviceOffset = try reader.uint16(at: offset + 2)
        if deviceOffset != 0 {
            _ = try requiredSubtableOffset(
                deviceOffset,
                parentStart: parentStart,
                name: "\(parentName) device table",
                minimumSize: 2,
            )
        }
        return TrueTypeMathTable.MathValueRecord(value: value, deviceOffset: deviceOffset)
    }

    private func checkedGlyphID(at offset: Int, name: String) throws -> UInt16 {
        let glyphID = try reader.uint16(at: offset)
        guard glyphID < numGlyphs else {
            throw malformed("\(name) \(glyphID) exceeds maxp.numGlyphs \(numGlyphs)")
        }
        return glyphID
    }

    private func requiredSubtableOffset(
        _ offsetValue: UInt16,
        parentStart: Int,
        name: String,
        minimumSize: Int,
    ) throws -> Int {
        guard let offset = try optionalSubtableOffset(
            offsetValue,
            parentStart: parentStart,
            name: name,
            minimumSize: minimumSize,
        ) else {
            throw malformed("\(name) offset must not be null")
        }
        return offset
    }

    private func optionalSubtableOffset(
        _ offsetValue: UInt16,
        parentStart: Int,
        name: String,
        minimumSize: Int,
    ) throws -> Int? {
        guard offsetValue != 0 else {
            return nil
        }
        let offset = parentStart + Int(offsetValue)
        guard offset >= parentStart else {
            throw malformed("\(name) offset wraps the parent table")
        }
        do {
            try reader.requireRange(offset: offset, count: minimumSize)
        } catch let error as TrueTypeFontError {
            throw malformed("\(name) offset is out of range: \(error.errorDescription ?? String(describing: error))")
        }
        return offset
    }

    private func malformed(_ reason: String) -> TrueTypeFontError {
        TrueTypeFontError.malformedTable(tag: "MATH", reason: reason)
    }
}
