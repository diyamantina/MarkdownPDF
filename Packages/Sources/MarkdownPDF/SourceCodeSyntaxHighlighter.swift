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
        while index < line.endIndex,
              isNumberBody(line[index])
        {
            index = line.index(after: index)
        }
        return index
    }

    private func isNumberBody(_ character: Character) -> Bool {
        character.isNumber
            || character.isHexLetter
            || character == "."
            || character == "_"
            || character == "+"
            || character == "-"
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
        case "a" ... "f", "A" ... "F", "x", "X":
            true
        default:
            false
        }
    }
}
