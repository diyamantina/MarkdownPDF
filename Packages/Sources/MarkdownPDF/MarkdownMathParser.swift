import Foundation

struct MarkdownMathParser {
    struct ParsedFormula: Equatable {
        var root: MarkdownMathNode
        var linearizedText: String
    }

    enum ParseError: Error, Equatable {
        case emptyFormula
        case duplicateScript(Character)
        case missingScriptBody(Character)
        case missingRequiredGroup(String)
        case missingRightDelimiter
        case missingDelimiter(String)
        case unmatchedGroup
        case unexpectedGroupClose
        case unsupportedControlWord(String)
    }

    func parse(_ source: String) throws -> ParsedFormula {
        var scanner = Scanner(source: source)
        let root = try scanner.parse()
        return ParsedFormula(root: root, linearizedText: MarkdownMathLinearizer().linearize(root))
    }

    private struct Scanner {
        var source: String
        var index: String.Index

        init(source: String) {
            self.source = source
            index = source.startIndex
        }

        mutating func parse() throws -> MarkdownMathNode {
            let root = try parseSequence(until: nil)
            guard !root.isEmptyMathSequence else {
                throw ParseError.emptyFormula
            }
            return root
        }

        private mutating func parseSequence(
            until terminator: Character?,
            stopAtRightDelimiter: Bool = false,
        ) throws -> MarkdownMathNode {
            var nodes: [MarkdownMathNode] = []

            while index < source.endIndex {
                let character = source[index]
                if stopAtRightDelimiter, controlWord(at: index)?.command == "right" {
                    return compactSequence(nodes)
                }
                if let terminator, character == terminator {
                    index = source.index(after: index)
                    return compactSequence(nodes)
                }
                if character == "}" {
                    throw ParseError.unexpectedGroupClose
                }

                try nodes.append(parseAtomWithScripts())
            }

            if terminator != nil {
                throw ParseError.unmatchedGroup
            }
            if stopAtRightDelimiter {
                throw ParseError.missingRightDelimiter
            }

            return compactSequence(nodes)
        }

        private mutating func parseAtomWithScripts() throws -> MarkdownMathNode {
            var base = try parseAtom()
            var subscriptNode: MarkdownMathNode?
            var superscriptNode: MarkdownMathNode?

            while index < source.endIndex {
                let marker = source[index]
                guard marker == "^" || marker == "_" else {
                    break
                }

                index = source.index(after: index)
                let script = try parseScriptBody(marker)
                if marker == "^" {
                    guard superscriptNode == nil else {
                        throw ParseError.duplicateScript(marker)
                    }
                    superscriptNode = script
                } else {
                    guard subscriptNode == nil else {
                        throw ParseError.duplicateScript(marker)
                    }
                    subscriptNode = script
                }
            }

            if subscriptNode != nil || superscriptNode != nil {
                base = .scripts(base: base, subscript: subscriptNode, superscript: superscriptNode)
            }
            return base
        }

        private mutating func parseAtom() throws -> MarkdownMathNode {
            guard index < source.endIndex else {
                throw ParseError.emptyFormula
            }

            let character = source[index]
            if character == "{" {
                index = source.index(after: index)
                return try parseSequence(until: "}")
            }
            if character == "\\" {
                return try parseControlWord()
            }
            if character == "^" || character == "_" {
                throw ParseError.missingScriptBody(character)
            }
            if character.isWhitespace {
                return parseWhitespace()
            }

            index = source.index(after: index)
            return .text(String(character))
        }

        private mutating func parseWhitespace() -> MarkdownMathNode {
            while index < source.endIndex, source[index].isWhitespace {
                index = source.index(after: index)
            }
            return .text(" ")
        }

        private mutating func parseControlWord() throws -> MarkdownMathNode {
            index = source.index(after: index)
            let commandStart = index
            while index < source.endIndex, source[index].isLetter {
                index = source.index(after: index)
            }

            let command = String(source[commandStart ..< index])
            if command.isEmpty {
                return try parseEscapedPunctuation()
            }

            switch command {
            case "frac":
                return try .fraction(
                    numerator: parseRequiredGroup(for: command),
                    denominator: parseRequiredGroup(for: command),
                )
            case "sqrt":
                return try .radical(radicand: parseRequiredGroup(for: command))
            case "left":
                return try parseDelimitedExpression()
            case "right", "begin", "end", "newcommand", "operatorname":
                throw ParseError.unsupportedControlWord(command)
            default:
                guard let symbol = Self.symbols[command] else {
                    throw ParseError.unsupportedControlWord(command)
                }
                return .symbol(
                    display: symbol.display,
                    linearized: symbol.linearized,
                    isBigOperator: symbol.isBigOperator,
                )
            }
        }

        private mutating func parseDelimitedExpression() throws -> MarkdownMathNode {
            skipWhitespace()
            let opening = try parseDelimiter(for: "left")
            let body = try parseSequence(until: nil, stopAtRightDelimiter: true)
            guard controlWord(at: index)?.command == "right" else {
                throw ParseError.missingRightDelimiter
            }

            try consumeControlWord("right")
            skipWhitespace()
            let closing = try parseDelimiter(for: "right")
            return compactSequence([opening, body, closing])
        }

        private mutating func skipWhitespace() {
            while index < source.endIndex, source[index].isWhitespace {
                index = source.index(after: index)
            }
        }

        private mutating func parseDelimiter(for command: String) throws -> MarkdownMathNode {
            guard index < source.endIndex else {
                throw ParseError.missingDelimiter(command)
            }

            if source[index] == "\\" {
                let slash = index
                index = source.index(after: index)
                let commandStart = index
                while index < source.endIndex, source[index].isLetter {
                    index = source.index(after: index)
                }

                if commandStart == index {
                    return try parseEscapedDelimiter(for: command)
                }

                let delimiterCommand = String(source[commandStart ..< index])
                guard let display = Self.namedDelimiters[delimiterCommand] else {
                    index = slash
                    throw ParseError.missingDelimiter(command)
                }
                return display.map(MarkdownMathNode.text) ?? .sequence([])
            }

            let character = source[index]
            index = source.index(after: index)
            guard let display = Self.characterDelimiters[character] else {
                throw ParseError.missingDelimiter(command)
            }
            return display.map(MarkdownMathNode.text) ?? .sequence([])
        }

        private mutating func parseEscapedDelimiter(for command: String) throws -> MarkdownMathNode {
            guard index < source.endIndex else {
                throw ParseError.missingDelimiter(command)
            }

            let character = source[index]
            index = source.index(after: index)
            guard let display = Self.characterDelimiters[character] else {
                throw ParseError.missingDelimiter(command)
            }
            return display.map(MarkdownMathNode.text) ?? .sequence([])
        }

        private func controlWord(at start: String.Index) -> (command: String, end: String.Index)? {
            guard start < source.endIndex, source[start] == "\\" else {
                return nil
            }

            var cursor = source.index(after: start)
            let commandStart = cursor
            while cursor < source.endIndex, source[cursor].isLetter {
                cursor = source.index(after: cursor)
            }
            guard commandStart < cursor else {
                return nil
            }

            return (String(source[commandStart ..< cursor]), cursor)
        }

        private mutating func consumeControlWord(_ expected: String) throws {
            guard let word = controlWord(at: index),
                  word.command == expected
            else {
                throw ParseError.unsupportedControlWord(expected)
            }

            index = word.end
        }

        private mutating func parseEscapedPunctuation() throws -> MarkdownMathNode {
            guard index < source.endIndex else {
                throw ParseError.unsupportedControlWord("")
            }

            let character = source[index]
            index = source.index(after: index)
            switch character {
            case "{", "}", "_", "^", "\\", "$":
                return .text(String(character))
            default:
                throw ParseError.unsupportedControlWord(String(character))
            }
        }

        private mutating func parseRequiredGroup(for command: String) throws -> MarkdownMathNode {
            guard index < source.endIndex, source[index] == "{" else {
                throw ParseError.missingRequiredGroup(command)
            }

            index = source.index(after: index)
            return try parseSequence(until: "}")
        }

        private mutating func parseScriptBody(_ marker: Character) throws -> MarkdownMathNode {
            guard index < source.endIndex else {
                throw ParseError.missingScriptBody(marker)
            }

            if source[index] == "{" {
                index = source.index(after: index)
                return try parseSequence(until: "}")
            }
            return try parseAtom()
        }

        private func compactSequence(_ nodes: [MarkdownMathNode]) -> MarkdownMathNode {
            let nonEmpty = nodes.filter { !$0.isEmptyMathSequence }
            if nonEmpty.count == 1, let first = nonEmpty.first {
                return first
            }
            return .sequence(nonEmpty)
        }

        private static let symbols: [String: (display: String, linearized: String, isBigOperator: Bool)] = [
            "alpha": ("alpha", "alpha", false),
            "beta": ("beta", "beta", false),
            "gamma": ("gamma", "gamma", false),
            "delta": ("delta", "delta", false),
            "epsilon": ("epsilon", "epsilon", false),
            "theta": ("theta", "theta", false),
            "lambda": ("lambda", "lambda", false),
            "mu": ("mu", "mu", false),
            "pi": ("pi", "pi", false),
            "sigma": ("sigma", "sigma", false),
            "phi": ("phi", "phi", false),
            "omega": ("omega", "omega", false),
            "Gamma": ("Gamma", "Gamma", false),
            "Delta": ("Delta", "Delta", false),
            "Theta": ("Theta", "Theta", false),
            "Lambda": ("Lambda", "Lambda", false),
            "Pi": ("Pi", "Pi", false),
            "Sigma": ("Sigma", "Sigma", false),
            "Phi": ("Phi", "Phi", false),
            "Omega": ("Omega", "Omega", false),
            "leq": ("<=", "<=", false),
            "geq": (">=", ">=", false),
            "neq": ("!=", "!=", false),
            "times": ("x", "x", false),
            "cdot": ("*", "*", false),
            "pm": ("+/-", "+/-", false),
            "infty": ("infinity", "infinity", false),
            "rightarrow": ("->", "->", false),
            "to": ("->", "->", false),
            "sum": ("sum", "sum", true),
            "prod": ("prod", "prod", true),
            "int": ("int", "int", true),
        ]

        private static let characterDelimiters: [Character: String?] = [
            "(": "(",
            ")": ")",
            "[": "[",
            "]": "]",
            "{": "{",
            "}": "}",
            "|": "|",
            "/": "/",
            "<": "<",
            ">": ">",
            ".": nil,
        ]

        private static let namedDelimiters: [String: String?] = [
            "langle": "<",
            "rangle": ">",
            "vert": "|",
            "lvert": "|",
            "rvert": "|",
            "backslash": "\\",
        ]
    }
}

private extension MarkdownMathNode {
    var isEmptyMathSequence: Bool {
        if case let .sequence(children) = self {
            children.isEmpty
        } else {
            false
        }
    }
}
