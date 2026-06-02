struct LineBreakOpportunityDetector {
    enum Kind: Equatable {
        case allowed
        case mandatory
    }

    struct Opportunity: Equatable {
        var scalarOffset: Int
        var kind: Kind
    }

    func opportunities(in text: String) -> [Opportunity] {
        let characters = classifiedCharacters(in: text)
        guard !characters.isEmpty else {
            return []
        }

        var opportunities: [Opportunity] = []
        for index in characters.indices {
            let current = characters[index]
            if current.kind == .newline {
                opportunities.append(Opportunity(scalarOffset: current.upperScalarOffset, kind: .mandatory))
                continue
            }

            let nextIndex = characters.index(after: index)
            guard nextIndex < characters.endIndex else {
                continue
            }

            if canBreak(after: current, before: characters[nextIndex]) {
                opportunities.append(Opportunity(scalarOffset: current.upperScalarOffset, kind: .allowed))
            }
        }
        return opportunities
    }

    func segments(in text: String) -> [String] {
        let characters = classifiedCharacters(in: text)
        guard !characters.isEmpty else {
            return []
        }

        var segments: [String] = []
        var buffer = ""
        for index in characters.indices {
            let current = characters[index]
            if current.kind == .newline {
                if !buffer.isEmpty {
                    segments.append(buffer)
                    buffer = ""
                }
                segments.append("\n")
                continue
            }

            buffer += current.text
            let nextIndex = characters.index(after: index)
            if nextIndex < characters.endIndex,
               canBreak(after: current, before: characters[nextIndex])
            {
                segments.append(buffer)
                buffer = ""
            }
        }

        if !buffer.isEmpty {
            segments.append(buffer)
        }
        return segments
    }

    private func classifiedCharacters(in text: String) -> [ClassifiedCharacter] {
        var characters: [ClassifiedCharacter] = []
        var index = text.startIndex
        var scalarOffset = 0
        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            let rawText = String(text[index ..< nextIndex])
            let scalars = Array(rawText.unicodeScalars)
            let upperScalarOffset = scalarOffset + scalars.count
            characters.append(ClassifiedCharacter(
                text: normalizedText(for: rawText),
                kind: kind(for: scalars),
                upperScalarOffset: upperScalarOffset,
            ))
            scalarOffset = upperScalarOffset
            index = nextIndex
        }
        return characters
    }

    private func canBreak(after current: ClassifiedCharacter, before next: ClassifiedCharacter) -> Bool {
        if next.kind == .combiningMark || next.kind == .closingPunctuation || next.kind == .japaneseNonStarter {
            return false
        }
        if current.kind == .openingPunctuation {
            return false
        }
        if current.kind == .closingPunctuation, next.kind == .cjkBreakable {
            return true
        }
        if current.kind == .space {
            return true
        }
        let currentAllowsCJKBreak = current.kind == .cjkBreakable || current.kind == .japaneseNonStarter
        let nextAllowsCJKBreak = next.kind == .cjkBreakable || next.kind == .japaneseNonStarter
        return currentAllowsCJKBreak && nextAllowsCJKBreak
    }

    private func normalizedText(for text: String) -> String {
        text == "\t" ? " " : text
    }

    private func kind(for scalars: [UnicodeScalar]) -> CharacterKind {
        if scalars.contains(where: isNewline) {
            return .newline
        }
        if scalars.allSatisfy(isHorizontalSpace) {
            return .space
        }
        if scalars.allSatisfy(isCombiningMark) {
            return .combiningMark
        }
        if scalars.contains(where: isOpeningPunctuation) {
            return .openingPunctuation
        }
        if scalars.contains(where: isClosingPunctuation) {
            return .closingPunctuation
        }
        if scalars.contains(where: isJapaneseNonStarter) {
            return .japaneseNonStarter
        }
        if scalars.contains(where: isCJKBreakableScalar) {
            return .cjkBreakable
        }
        return .other
    }

    private func isNewline(_ scalar: UnicodeScalar) -> Bool {
        scalar.value == 0x0A || scalar.value == 0x0D
    }

    private func isHorizontalSpace(_ scalar: UnicodeScalar) -> Bool {
        scalar.value == 0x20 || scalar.value == 0x09
    }

    private func isCombiningMark(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0300 ... 0x036F,
             0x1AB0 ... 0x1AFF,
             0x1DC0 ... 0x1DFF,
             0x20D0 ... 0x20FF,
             0xFE20 ... 0xFE2F,
             0x0E31,
             0x0E34 ... 0x0E3A,
             0x0E47 ... 0x0E4E,
             0x17B4 ... 0x17D3:
            true
        default:
            false
        }
    }

    private func isCJKBreakableScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3040 ... 0x30FF,
             0x3400 ... 0x4DBF,
             0x4E00 ... 0x9FFF,
             0xF900 ... 0xFAFF,
             0x20000 ... 0x2EBEF,
             0x2EBF0 ... 0x2EE5D,
             0x2F800 ... 0x2FA1F,
             0x30000 ... 0x3134F,
             0x31350 ... 0x323AF:
            true
        default:
            false
        }
    }

    private func isJapaneseNonStarter(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3041, 0x3043, 0x3045, 0x3047, 0x3049,
             0x3063,
             0x3083, 0x3085, 0x3087,
             0x308E, 0x3095, 0x3096,
             0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9,
             0x30C3,
             0x30E3, 0x30E5, 0x30E7,
             0x30EE, 0x30F5, 0x30F6,
             0x30FC,
             0x31F0 ... 0x31FF:
            true
        default:
            false
        }
    }

    private func isOpeningPunctuation(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x28, 0x5B, 0x7B,
             0x3008, 0x300A, 0x300C, 0x300E, 0x3010, 0x3014, 0x3016, 0x3018, 0x301A,
             0xFF08, 0xFF3B, 0xFF5B:
            true
        default:
            false
        }
    }

    private func isClosingPunctuation(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x21, 0x29, 0x2C, 0x2E, 0x3A, 0x3B, 0x3F, 0x5D, 0x7D,
             0x3001, 0x3002, 0x3009, 0x300B, 0x300D, 0x300F,
             0x3011, 0x3015, 0x3017, 0x3019, 0x301B,
             0xFF01, 0xFF09, 0xFF0C, 0xFF0E, 0xFF1A, 0xFF1B, 0xFF1F, 0xFF3D, 0xFF5D:
            true
        default:
            false
        }
    }
}

private struct ClassifiedCharacter: Equatable {
    var text: String
    var kind: CharacterKind
    var upperScalarOffset: Int
}

private enum CharacterKind: Equatable {
    case newline
    case space
    case combiningMark
    case cjkBreakable
    case japaneseNonStarter
    case openingPunctuation
    case closingPunctuation
    case other
}
