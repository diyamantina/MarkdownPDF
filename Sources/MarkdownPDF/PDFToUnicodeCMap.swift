import Foundation

struct PDFToUnicodeCMap {
    struct Mapping: Equatable {
        var code: UInt16
        var unicode: String
    }

    var name: String
    var mappings: [Mapping]

    init(name: String = "MarkdownPDF-ToUnicode", mappings: [Mapping]) {
        precondition(!name.isEmpty, "ToUnicode CMaps require a CMap name")
        precondition(!mappings.isEmpty, "ToUnicode CMaps require at least one mapping")
        precondition(
            Set(mappings.map(\.code)).count == mappings.count,
            "ToUnicode CMap codes must be unique",
        )
        precondition(
            mappings.allSatisfy { !$0.unicode.isEmpty },
            "ToUnicode CMap mappings require a Unicode scalar sequence",
        )
        self.name = name
        self.mappings = mappings.sorted { lhs, rhs in
            lhs.code < rhs.code
        }
    }

    init(name: String = "MarkdownPDF-ToUnicode", textMapping: TrueTypeGlyphMapper.TextMapping) throws {
        let mappings = try Self.uniqueMappings(from: textMapping.glyphs)
        guard !mappings.isEmpty else {
            throw PDFToUnicodeCMapError.emptyMapping
        }
        self.init(name: name, mappings: mappings)
    }

    var pdfStream: PDFSyntax.Stream {
        PDFSyntax.Stream(dictionary: PDFSyntax.Dictionary(), data: data)
    }

    var data: Data {
        Data(serialized.utf8)
    }

    var serialized: String {
        var lines = [
            "/CIDInit /ProcSet findresource begin",
            "12 dict begin",
            "begincmap",
            "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def",
            "/CMapName \(PDFSyntax.Name(name).serialized) def",
            "/CMapType 2 def",
            "1 begincodespacerange",
            "<0000> <FFFF>",
            "endcodespacerange",
        ]

        for section in mappingSections {
            switch section {
            case let .bfchar(chunk):
                lines.append("\(chunk.count) beginbfchar")
                lines.append(contentsOf: chunk.map { mapping in
                    "\(Self.hex(mapping.code)) \(Self.hex(mapping.unicode))"
                })
                lines.append("endbfchar")
            case let .bfrange(chunk):
                lines.append("\(chunk.count) beginbfrange")
                lines.append(contentsOf: chunk.map { range in
                    "\(Self.hex(range.startCode)) \(Self.hex(range.endCode)) \(Self.hex(range.startUnicode))"
                })
                lines.append("endbfrange")
            }
        }

        lines.append(contentsOf: [
            "endcmap",
            "CMapName currentdict /CMap defineresource pop",
            "end",
            "end",
            "",
        ])

        return lines.joined(separator: "\n")
    }

    private var mappingSections: [MappingSection] {
        var sections: [MappingSection] = []
        var currentKind: MappingEntry.Kind?
        var currentEntries: [MappingEntry] = []

        func flushCurrentEntries() {
            guard !currentEntries.isEmpty else {
                return
            }
            switch currentKind {
            case .bfchar:
                sections.append(.bfchar(currentEntries.compactMap(\.bfcharMapping)))
            case .bfrange:
                sections.append(.bfrange(currentEntries.compactMap(\.bfrangeMapping)))
            case nil:
                break
            }
            currentEntries.removeAll()
        }

        for entry in Self.mappingEntries(for: mappings) {
            if currentKind != entry.kind || currentEntries.count == 100 {
                flushCurrentEntries()
                currentKind = entry.kind
            }
            currentEntries.append(entry)
        }
        flushCurrentEntries()
        return sections
    }

    private static func mappingEntries(for mappings: [Mapping]) -> [MappingEntry] {
        var entries: [MappingEntry] = []
        var index = 0
        while index < mappings.count {
            var rangeEndIndex = index
            while rangeEndIndex + 1 < mappings.count,
                  canContinueRange(from: mappings[rangeEndIndex], to: mappings[rangeEndIndex + 1])
            {
                rangeEndIndex += 1
            }

            if rangeEndIndex > index {
                entries.append(
                    .bfrange(
                        RangeMapping(
                            startCode: mappings[index].code,
                            endCode: mappings[rangeEndIndex].code,
                            startUnicode: mappings[index].unicode,
                        ),
                    ),
                )
                index = rangeEndIndex + 1
            } else {
                entries.append(.bfchar(mappings[index]))
                index += 1
            }
        }
        return entries
    }

    private static func canContinueRange(from current: Mapping, to next: Mapping) -> Bool {
        guard current.code < UInt16.max, current.code + 1 == next.code else {
            return false
        }
        guard let currentScalar = singleBasicMultilingualPlaneScalar(current.unicode),
              let nextScalar = singleBasicMultilingualPlaneScalar(next.unicode)
        else {
            return false
        }
        return currentScalar < 0xFFFF && currentScalar + 1 == nextScalar
    }

    private static func singleBasicMultilingualPlaneScalar(_ string: String) -> UInt32? {
        let scalars = Array(string.unicodeScalars)
        guard scalars.count == 1, let scalar = scalars.first, scalar.value <= 0xFFFF else {
            return nil
        }
        return scalar.value
    }

    private static func uniqueMappings(from glyphs: [TrueTypeGlyphMapper.Glyph]) throws -> [Mapping] {
        var mappingsByCode: [UInt16: String] = [:]
        for glyph in glyphs {
            let unicode = String(glyph.scalar)
            if let existing = mappingsByCode[glyph.pdfCharacterCode] {
                guard existing == unicode else {
                    throw PDFToUnicodeCMapError.conflictingMapping(
                        code: glyph.pdfCharacterCode,
                        existing: existing,
                        duplicate: unicode,
                    )
                }
            } else {
                mappingsByCode[glyph.pdfCharacterCode] = unicode
            }
        }
        return mappingsByCode.map { code, unicode in
            Mapping(code: code, unicode: unicode)
        }
    }

    private static func hex(_ code: UInt16) -> String {
        String(format: "<%04X>", locale: serializationLocale, code)
    }

    private static func hex(_ string: String) -> String {
        let body = string.utf16.map { unit in
            String(format: "%04X", locale: serializationLocale, unit)
        }.joined()
        return "<\(body)>"
    }

    private static let serializationLocale = Locale(identifier: "en_US_POSIX")
}

private enum MappingEntry {
    enum Kind {
        case bfchar
        case bfrange
    }

    case bfchar(PDFToUnicodeCMap.Mapping)
    case bfrange(RangeMapping)

    var kind: Kind {
        switch self {
        case .bfchar:
            .bfchar
        case .bfrange:
            .bfrange
        }
    }

    var bfcharMapping: PDFToUnicodeCMap.Mapping? {
        switch self {
        case let .bfchar(mapping):
            mapping
        case .bfrange:
            nil
        }
    }

    var bfrangeMapping: RangeMapping? {
        switch self {
        case .bfchar:
            nil
        case let .bfrange(range):
            range
        }
    }
}

private struct RangeMapping {
    var startCode: UInt16
    var endCode: UInt16
    var startUnicode: String
}

private enum MappingSection {
    case bfchar([PDFToUnicodeCMap.Mapping])
    case bfrange([RangeMapping])
}
