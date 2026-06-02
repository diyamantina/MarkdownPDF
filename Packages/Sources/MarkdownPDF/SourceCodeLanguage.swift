import Foundation

enum SourceCodeLanguage: Equatable {
    case swift
    case cFamily
    case python
    case json

    init?(hint: String?) {
        guard let rawHint = hint?
            .split(whereSeparator: \.isWhitespace)
            .first?
            .lowercased()
        else {
            return nil
        }

        let normalized = rawHint.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch normalized {
        case "swift":
            self = .swift
        case "c", "h", "cc", "cpp", "c++", "hpp", "metal", "msl", "java", "javascript", "js", "typescript", "ts", "rust", "rs", "go", "csharp", "cs":
            self = .cFamily
        case "python", "py":
            self = .python
        case "json":
            self = .json
        default:
            return nil
        }
    }

    var keywords: Set<String> {
        switch self {
        case .swift:
            [
                "actor", "as", "associatedtype", "async", "await", "break",
                "case", "catch", "class", "continue", "defer", "do", "else",
                "enum", "extension", "false", "for", "func", "guard", "if",
                "import", "in", "init", "inout", "let", "nil", "private",
                "protocol", "public", "return", "self", "static", "struct",
                "switch", "throw", "throws", "true", "try", "var", "where",
                "while",
            ]
        case .cFamily:
            [
                "auto", "bool", "break", "case", "class", "const", "continue",
                "default", "device", "do", "double", "else", "enum", "false",
                "float", "float2", "float3", "float4", "for", "func", "if",
                "int", "kernel", "let", "long", "namespace", "private",
                "public", "return", "short", "static", "struct", "switch",
                "template", "this", "thread", "true", "uint", "using", "var",
                "void", "while",
            ]
        case .python:
            [
                "and", "as", "async", "await", "break", "class", "continue",
                "def", "elif", "else", "except", "False", "finally", "for",
                "from", "if", "import", "in", "is", "lambda", "None", "not",
                "or", "pass", "raise", "return", "True", "try", "while",
                "with", "yield",
            ]
        case .json:
            ["false", "null", "true"]
        }
    }

    var supportsSlashLineComments: Bool {
        switch self {
        case .swift, .cFamily:
            true
        case .json, .python:
            false
        }
    }

    var supportsHashLineComments: Bool {
        switch self {
        case .python:
            true
        case .swift, .cFamily, .json:
            false
        }
    }

    var supportsBlockComments: Bool {
        switch self {
        case .swift, .cFamily:
            true
        case .json, .python:
            false
        }
    }

    var operatorCharacters: Set<Character> {
        ["=", "+", "-", "*", "/", "%", "<", ">", "!", "&", "|", "^", "~", "?", ":", "."]
    }

    var punctuationCharacters: Set<Character> {
        ["{", "}", "[", "]", "(", ")", ",", ";"]
    }
}
