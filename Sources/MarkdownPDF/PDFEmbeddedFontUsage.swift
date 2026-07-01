struct PDFEmbeddedFontUsage: Equatable {
    var resource: PDFEmbeddedFontResource
    var glyphs: [TrueTypeGlyphMapper.Glyph]
    var toUnicodeMappings: [PDFToUnicodeCMap.Mapping]

    init(resource: PDFEmbeddedFontResource, mapping: ShapedTextMapping) throws {
        self.resource = resource
        glyphs = []
        toUnicodeMappings = []
        try append(mapping: mapping)
    }

    mutating func append(_ usage: PDFEmbeddedFontUsage) throws {
        glyphs.append(contentsOf: usage.glyphs)
        toUnicodeMappings = try Self.mergedMappings(
            existing: toUnicodeMappings,
            newMappings: usage.toUnicodeMappings,
        )
    }

    mutating func append(mapping: ShapedTextMapping) throws {
        let mappedGlyphs = try Self.mappedGlyphs(from: mapping)
        glyphs.append(contentsOf: mappedGlyphs.map(\.glyph))
        toUnicodeMappings = try Self.mergedMappings(
            existing: toUnicodeMappings,
            newMappings: mappedGlyphs.map(\.toUnicodeMapping),
        )
    }

    private static func mappedGlyphs(from mapping: ShapedTextMapping) throws -> [MappedGlyph] {
        var mappedGlyphs: [MappedGlyph] = []
        for cluster in mapping.clusters {
            let unicodeSequences = try toUnicodeSequences(for: cluster)
            for (glyph, unicodeScalars) in zip(cluster.glyphs, unicodeSequences) {
                let unicode = string(from: unicodeScalars)
                mappedGlyphs.append(
                    MappedGlyph(
                        glyph: TrueTypeGlyphMapper.Glyph(
                            scalar: glyph.cmapScalar ?? subsetCMapScalar(
                                for: glyph.pdfCharacterCode,
                                unicodeScalars: unicodeScalars,
                            ),
                            glyphID: glyph.glyphID,
                            cid: glyph.cid,
                            pdfCharacterCode: glyph.pdfCharacterCode,
                            advanceWidth: glyph.advanceWidth,
                            width: glyph.advance,
                        ),
                        toUnicodeMapping: PDFToUnicodeCMap.Mapping(
                            code: glyph.pdfCharacterCode,
                            unicode: unicode,
                        ),
                    ),
                )
            }
        }
        return mappedGlyphs
    }

    private static func toUnicodeSequences(for cluster: ShapedTextMapping.Cluster) throws -> [[UnicodeScalar]] {
        let glyphCount = cluster.glyphs.count
        let scalars = cluster.toUnicodeScalars
        let scalarCount = scalars.count

        if glyphCount == scalarCount {
            return scalars.map { [$0] }
        }
        if glyphCount == 1 {
            return [scalars]
        }
        guard glyphCount < scalarCount else {
            throw PDFEmbeddedFontError.unsupportedShapedToUnicodeCluster(
                sourceRange: cluster.sourceScalarRange,
                glyphCount: glyphCount,
                scalarCount: scalarCount,
            )
        }

        let firstSequenceLength = scalarCount - glyphCount + 1
        var sequences = [Array(scalars[0 ..< firstSequenceLength])]
        sequences.append(contentsOf: scalars[firstSequenceLength...].map { [$0] })
        return sequences
    }

    private static func mergedMappings(
        existing: [PDFToUnicodeCMap.Mapping],
        newMappings: [PDFToUnicodeCMap.Mapping],
    ) throws -> [PDFToUnicodeCMap.Mapping] {
        var mappingsByCode = Dictionary(uniqueKeysWithValues: existing.map { ($0.code, $0.unicode) })
        for mapping in newMappings {
            if let existing = mappingsByCode[mapping.code] {
                guard existing != mapping.unicode else { continue }
                // A glyph shared between a base character and a precomposed sub/superscript that
                // folded onto it (see #221) is not a real conflict: a single glyph can only carry
                // one ToUnicode value, so collapse both to the common base character.
                let folded = foldingSubSuperscripts(existing)
                guard folded == foldingSubSuperscripts(mapping.unicode) else {
                    throw PDFEmbeddedFontError.conflictingToUnicodeMapping(
                        code: mapping.code,
                        existing: existing,
                        duplicate: mapping.unicode,
                    )
                }
                mappingsByCode[mapping.code] = folded
            } else {
                mappingsByCode[mapping.code] = mapping.unicode
            }
        }
        return mappingsByCode
            .map { code, unicode in PDFToUnicodeCMap.Mapping(code: code, unicode: unicode) }
            .sorted { lhs, rhs in lhs.code < rhs.code }
    }

    private static func subsetCMapScalar(
        for code: UInt16,
        unicodeScalars: [UnicodeScalar],
    ) -> UnicodeScalar {
        if unicodeScalars.count == 1, let scalar = unicodeScalars.first {
            return scalar
        }
        return UnicodeScalar(0x100000 + UInt32(code)) ?? "\u{FFFD}"
    }

    private static func foldingSubSuperscripts(_ string: String) -> String {
        String(String.UnicodeScalarView(string.unicodeScalars.map { TrueTypeGlyphMapper.subSuperscriptBase[$0] ?? $0 }))
    }

    private static func string(from scalars: [UnicodeScalar]) -> String {
        String(String.UnicodeScalarView(scalars))
    }

    private struct MappedGlyph {
        var glyph: TrueTypeGlyphMapper.Glyph
        var toUnicodeMapping: PDFToUnicodeCMap.Mapping
    }
}
