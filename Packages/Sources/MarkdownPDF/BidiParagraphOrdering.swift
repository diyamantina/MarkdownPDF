struct BidiParagraphOrdering {
    enum Direction: Equatable {
        case leftToRight
        case rightToLeft
    }

    struct Paragraph: Equatable {
        var baseDirection: Direction
        var visualRuns: [Run]
    }

    struct Run: Equatable {
        var sourceScalarRange: Range<Int>
        var sourceText: String
        var displayText: String
        var direction: Direction
        var embeddingLevel: Int
    }

    enum ValidationError: Error, Equatable {
        case unsupportedBidiControl(scalar: UnicodeScalar, scalarOffset: Int)
    }

    func order(_ text: String) throws -> Paragraph {
        let units = try bidiUnits(in: text)
        let baseDirection = paragraphBaseDirection(for: units)
        let logicalRuns = logicalRuns(for: units, baseDirection: baseDirection)
        let visualRuns = baseDirection == .leftToRight ? logicalRuns : logicalRuns.reversed()
        return Paragraph(baseDirection: baseDirection, visualRuns: visualRuns.map(displayRun))
    }

    func containsRightToLeftText(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isRightToLeftScalar)
    }

    private func bidiUnits(in text: String) throws -> [BidiUnit] {
        var units: [BidiUnit] = []
        var index = text.startIndex
        var scalarOffset = 0
        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            let unitText = String(text[index ..< nextIndex])
            let scalars = Array(unitText.unicodeScalars)
            let scalarRange = scalarOffset ..< scalarOffset + scalars.count
            if let unsupportedIndex = scalars.firstIndex(where: isUnsupportedBidiControl) {
                let unsupported = scalars[unsupportedIndex]
                throw ValidationError.unsupportedBidiControl(
                    scalar: unsupported,
                    scalarOffset: scalarRange.lowerBound + unsupportedIndex,
                )
            }

            units.append(BidiUnit(
                text: unitText,
                scalarRange: scalarRange,
                bidiClass: bidiClass(for: scalars),
            ))
            scalarOffset = scalarRange.upperBound
            index = nextIndex
        }
        return units
    }

    private func paragraphBaseDirection(for units: [BidiUnit]) -> Direction {
        for unit in units {
            switch unit.bidiClass {
            case .leftToRight:
                return .leftToRight
            case .rightToLeft:
                return .rightToLeft
            case .number, .neutral:
                continue
            }
        }
        return .leftToRight
    }

    private func logicalRuns(for units: [BidiUnit], baseDirection: Direction) -> [Run] {
        var runs: [Run] = []
        for unit in units {
            let direction = resolvedDirection(for: unit.bidiClass, baseDirection: baseDirection)
            let level = embeddingLevel(for: direction, baseDirection: baseDirection)
            if let last = runs.last,
               last.direction == direction,
               last.embeddingLevel == level,
               last.sourceScalarRange.upperBound == unit.scalarRange.lowerBound
            {
                runs[runs.count - 1] = Run(
                    sourceScalarRange: last.sourceScalarRange.lowerBound ..< unit.scalarRange.upperBound,
                    sourceText: last.sourceText + unit.text,
                    displayText: "",
                    direction: direction,
                    embeddingLevel: level,
                )
            } else {
                runs.append(Run(
                    sourceScalarRange: unit.scalarRange,
                    sourceText: unit.text,
                    displayText: "",
                    direction: direction,
                    embeddingLevel: level,
                ))
            }
        }
        return runs
    }

    private func displayRun(_ run: Run) -> Run {
        Run(
            sourceScalarRange: run.sourceScalarRange,
            sourceText: run.sourceText,
            displayText: run.direction == .rightToLeft ? mirroredReversedText(run.sourceText) : run.sourceText,
            direction: run.direction,
            embeddingLevel: run.embeddingLevel,
        )
    }

    private func mirroredReversedText(_ text: String) -> String {
        String(text.reversed().map(mirroredCharacter))
    }

    private func mirroredCharacter(_ character: Character) -> Character {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1
        else {
            return character
        }

        switch scalar.value {
        case 0x28:
            return ")"
        case 0x29:
            return "("
        case 0x3C:
            return ">"
        case 0x3E:
            return "<"
        case 0x5B:
            return "]"
        case 0x5D:
            return "["
        case 0x7B:
            return "}"
        case 0x7D:
            return "{"
        default:
            return character
        }
    }

    private func resolvedDirection(for bidiClass: BidiClass, baseDirection: Direction) -> Direction {
        switch bidiClass {
        case .leftToRight, .number:
            .leftToRight
        case .rightToLeft:
            .rightToLeft
        case .neutral:
            baseDirection
        }
    }

    private func embeddingLevel(for direction: Direction, baseDirection: Direction) -> Int {
        switch (baseDirection, direction) {
        case (.leftToRight, .leftToRight):
            0
        case (.leftToRight, .rightToLeft):
            1
        case (.rightToLeft, .rightToLeft):
            1
        case (.rightToLeft, .leftToRight):
            2
        }
    }

    private func bidiClass(for scalars: [UnicodeScalar]) -> BidiClass {
        if scalars.allSatisfy(isNeutral) {
            return .neutral
        }
        if scalars.allSatisfy(isNumber) {
            return .number
        }
        if scalars.contains(where: isRightToLeftScalar) {
            return .rightToLeft
        }
        if scalars.contains(where: isLeftToRightScalar) {
            return .leftToRight
        }
        return .neutral
    }

    private func isUnsupportedBidiControl(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x061C,
             0x200E ... 0x200F,
             0x202A ... 0x202E,
             0x2066 ... 0x2069:
            true
        default:
            false
        }
    }

    private func isRightToLeftScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0590 ... 0x05FF,
             0x0600 ... 0x06FF,
             0x0750 ... 0x077F,
             0x08A0 ... 0x08FF,
             0xFB1D ... 0xFDFF,
             0xFE70 ... 0xFEFF:
            true
        default:
            false
        }
    }

    private func isNumber(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x30 ... 0x39,
             0x0660 ... 0x0669,
             0x06F0 ... 0x06F9:
            true
        default:
            false
        }
    }

    private func isLeftToRightScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x41 ... 0x5A,
             0x61 ... 0x7A,
             0x00C0 ... 0x024F:
            true
        default:
            false
        }
    }

    private func isNeutral(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x09 ... 0x0D,
             0x20,
             0x21 ... 0x2F,
             0x3A ... 0x40,
             0x5B ... 0x60,
             0x7B ... 0x7E:
            true
        default:
            false
        }
    }
}

private struct BidiUnit: Equatable {
    var text: String
    var scalarRange: Range<Int>
    var bidiClass: BidiClass
}

private enum BidiClass: Equatable {
    case leftToRight
    case rightToLeft
    case number
    case neutral
}
