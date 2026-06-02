import Foundation

struct SourceCodeSyntaxHighlighter {
    private let language: SourceCodeLanguage
    private var isInsideBlockComment = false

    init(language: SourceCodeLanguage) {
        self.language = language
    }

    mutating func tokens(for line: String) -> [SourceCodeToken] {
        var tokens: [SourceCodeToken] = []
        var index = line.startIndex

        while index < line.endIndex {
            if isInsideBlockComment {
                let tokenEnd = line.range(of: "*/", range: index ..< line.endIndex)?.upperBound ?? line.endIndex
                tokens.append(SourceCodeToken(text: String(line[index ..< tokenEnd]), kind: .comment))
                isInsideBlockComment = tokenEnd == line.endIndex
                index = tokenEnd
                continue
            }

            if starts(with: "//", in: line, at: index), language.supportsSlashLineComments {
                tokens.append(SourceCodeToken(text: String(line[index...]), kind: .comment))
                break
            }

            if line[index] == "#", language.supportsHashLineComments {
                tokens.append(SourceCodeToken(text: String(line[index...]), kind: .comment))
                break
            }

            if starts(with: "/*", in: line, at: index), language.supportsBlockComments {
                let tokenEnd = line.range(of: "*/", range: index ..< line.endIndex)?.upperBound ?? line.endIndex
                tokens.append(SourceCodeToken(text: String(line[index ..< tokenEnd]), kind: .comment))
                isInsideBlockComment = tokenEnd == line.endIndex
                index = tokenEnd
                continue
            }

            let character = line[index]
            if character == "\"" || character == "'" {
                let tokenEnd = stringLiteralEnd(in: line, from: index, quote: character)
                tokens.append(SourceCodeToken(text: String(line[index ..< tokenEnd]), kind: .string))
                index = tokenEnd
            } else if character.isNumber || isNumberStart(character, in: line, at: index) {
                let tokenEnd = numberEnd(in: line, from: index)
                tokens.append(SourceCodeToken(text: String(line[index ..< tokenEnd]), kind: .number))
                index = tokenEnd
            } else if isIdentifierStart(character) {
                let tokenEnd = identifierEnd(in: line, from: index)
                let text = String(line[index ..< tokenEnd])
                let kind: SourceCodeTokenKind = language.keywords.contains(text) ? .keyword : .identifier
                tokens.append(SourceCodeToken(text: text, kind: kind))
                index = tokenEnd
            } else if language.operatorCharacters.contains(character) {
                tokens.append(SourceCodeToken(text: String(character), kind: .operatorToken))
                index = line.index(after: index)
            } else if language.punctuationCharacters.contains(character) {
                tokens.append(SourceCodeToken(text: String(character), kind: .punctuation))
                index = line.index(after: index)
            } else {
                tokens.append(SourceCodeToken(text: String(character), kind: .text))
                index = line.index(after: index)
            }
        }

        return coalesced(tokens)
    }

    private func starts(with prefix: String, in line: String, at index: String.Index) -> Bool {
        line[index...].hasPrefix(prefix)
    }

    private func stringLiteralEnd(
        in line: String,
        from start: String.Index,
        quote: Character,
    ) -> String.Index {
        var index = line.index(after: start)
        var isEscaped = false

        while index < line.endIndex {
            let character = line[index]
            let next = line.index(after: index)

            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == quote {
                return next
            }
            index = next
        }

        return line.endIndex
    }

    private func isNumberStart(
        _ character: Character,
        in line: String,
        at index: String.Index,
    ) -> Bool {
        guard character == "." else {
            return false
        }
        let next = line.index(after: index)
        return next < line.endIndex && line[next].isNumber
    }

    private func numberEnd(in line: String, from start: String.Index) -> String.Index {
        var index = start

        if line[index] == "." {
            index = line.index(after: index)
            while index < line.endIndex, isDecimalBody(line[index]) {
                index = line.index(after: index)
            }
            return exponentEnd(in: line, from: index)
        }

        if starts(with: "0x", in: line, at: index) || starts(with: "0X", in: line, at: index) {
            index = line.index(index, offsetBy: 2)
            while index < line.endIndex, isHexBody(line[index]) {
                index = line.index(after: index)
            }
            return index
        }

        while index < line.endIndex, isDecimalBody(line[index]) {
            index = line.index(after: index)
        }

        if index < line.endIndex,
           line[index] == ".",
           hasDecimalDigitAfterDot(in: line, at: index)
        {
            index = line.index(after: index)
            while index < line.endIndex, isDecimalBody(line[index]) {
                index = line.index(after: index)
            }
        }

        return exponentEnd(in: line, from: index)
    }

    private func exponentEnd(in line: String, from start: String.Index) -> String.Index {
        guard start < line.endIndex,
              line[start] == "e" || line[start] == "E"
        else {
            return start
        }

        var digitStart = line.index(after: start)
        if digitStart < line.endIndex,
           line[digitStart] == "+" || line[digitStart] == "-"
        {
            digitStart = line.index(after: digitStart)
        }

        guard digitStart < line.endIndex, line[digitStart].isNumber else {
            return start
        }

        var index = digitStart
        while index < line.endIndex, isDecimalBody(line[index]) {
            index = line.index(after: index)
        }
        return index
    }

    private func hasDecimalDigitAfterDot(in line: String, at dotIndex: String.Index) -> Bool {
        let next = line.index(after: dotIndex)
        return next < line.endIndex && line[next].isNumber
    }

    private func isDecimalBody(_ character: Character) -> Bool {
        character.isNumber || character == "_"
    }

    private func isHexBody(_ character: Character) -> Bool {
        character.isNumber || character.isHexLetter || character == "_"
    }

    private func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character == "$" || character.isLetter
    }

    private func identifierEnd(in line: String, from start: String.Index) -> String.Index {
        var index = start
        while index < line.endIndex,
              isIdentifierBody(line[index])
        {
            index = line.index(after: index)
        }
        return index
    }

    private func isIdentifierBody(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }

    private func coalesced(_ tokens: [SourceCodeToken]) -> [SourceCodeToken] {
        tokens.reduce(into: []) { result, token in
            if let last = result.last, last.kind == token.kind {
                result[result.count - 1] = SourceCodeToken(
                    text: last.text + token.text,
                    kind: last.kind,
                )
            } else {
                result.append(token)
            }
        }
    }
}

private extension Character {
    var isLetter: Bool {
        unicodeScalars.allSatisfy(CharacterSet.letters.contains)
    }

    var isNumber: Bool {
        unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
    }

    var isHexLetter: Bool {
        switch self {
        case "a" ... "f", "A" ... "F":
            true
        default:
            false
        }
    }
}
