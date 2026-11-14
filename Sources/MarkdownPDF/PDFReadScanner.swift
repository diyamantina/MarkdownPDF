/// Reads PDF syntax from bytes: objects for ``PDFDocumentReader`` and, with
/// ``nextOperation()``, the operators of a content stream with their operands.
struct PDFReadScanner {
    let bytes: [UInt8]
    var position: Int

    init(_ bytes: [UInt8], at position: Int = 0) {
        self.bytes = bytes
        self.position = position
    }

    var isAtEnd: Bool {
        position >= bytes.count
    }

    // MARK: Lexical helpers

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x00 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D || byte == 0x20
    }

    private static func isDelimiter(_ byte: UInt8) -> Bool {
        // ( ) < > [ ] { } / %
        [0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25].contains(byte)
    }

    /// Moves past white space and comments.
    mutating func skipWhitespace() {
        while position < bytes.count {
            let byte = bytes[position]
            if Self.isWhitespace(byte) {
                position += 1
            } else if byte == 0x25 {
                while position < bytes.count, bytes[position] != 0x0A, bytes[position] != 0x0D {
                    position += 1
                }
            } else {
                return
            }
        }
    }

    /// The run of regular characters at the position: a number, a keyword or an operator.
    private mutating func word() -> String {
        let start = position
        while position < bytes.count, !Self.isWhitespace(bytes[position]), !Self.isDelimiter(bytes[position]) {
            position += 1
        }
        return String(decoding: bytes[start ..< position], as: UTF8.self)
    }

    /// True, and consumed, when the bytes at the position are `keyword`.
    mutating func consume(_ keyword: String) -> Bool {
        let wanted = Array(keyword.utf8)
        guard position + wanted.count <= bytes.count, Array(bytes[position ..< position + wanted.count]) == wanted else {
            return false
        }
        position += wanted.count
        return true
    }

    // MARK: Objects

    /// Reads one object. `allowReferences` is false inside a content stream, where
    /// `1 0 R` cannot occur and two numbers are just two operands.
    mutating func value(allowReferences: Bool = true) throws -> PDFReadValue {
        skipWhitespace()
        guard position < bytes.count else {
            throw PDFDocumentReader.ReadError.malformed("the file ends inside an object")
        }
        switch bytes[position] {
        case 0x2F:
            position += 1
            return try .name(nameText())
        case 0x28:
            return try .string(literalString())
        case 0x5B:
            position += 1
            var items: [PDFReadValue] = []
            while true {
                skipWhitespace()
                guard position < bytes.count else {
                    throw PDFDocumentReader.ReadError.malformed("an array is not closed")
                }
                if bytes[position] == 0x5D {
                    position += 1
                    return .array(items)
                }
                try items.append(value(allowReferences: allowReferences))
            }
        case 0x3C:
            if position + 1 < bytes.count, bytes[position + 1] == 0x3C {
                position += 2
                return try .dictionary(dictionaryBody(allowReferences: allowReferences))
            }
            return try .string(hexString())
        default:
            return try numberOrKeyword(allowReferences: allowReferences)
        }
    }

    private mutating func numberOrKeyword(allowReferences: Bool) throws -> PDFReadValue {
        let start = position
        let text = word()
        switch text {
        case "true": return .boolean(true)
        case "false": return .boolean(false)
        case "null": return .null
        default: break
        }
        guard let number = Double(text) else {
            position = start
            throw PDFDocumentReader.ReadError.malformed("unexpected '\(text.isEmpty ? String(UnicodeScalar(bytes[start])) : text)' where an object should be")
        }
        // `12 0 R` is a reference: look ahead for a generation number and the R.
        if allowReferences, number >= 0, number == number.rounded() {
            let afterNumber = position
            skipWhitespace()
            if Double(word()) != nil {
                skipWhitespace()
                if word() == "R" {
                    return .reference(Int(number))
                }
            }
            position = afterNumber
        }
        return .number(number)
    }

    private mutating func nameText() throws -> String {
        var name: [UInt8] = []
        while position < bytes.count, !Self.isWhitespace(bytes[position]), !Self.isDelimiter(bytes[position]) {
            if bytes[position] == 0x23, position + 2 < bytes.count,
               let high = Self.hexValue(bytes[position + 1]), let low = Self.hexValue(bytes[position + 2])
            {
                name.append(high << 4 | low)
                position += 3
            } else {
                name.append(bytes[position])
                position += 1
            }
        }
        return String(decoding: name, as: UTF8.self)
    }

    private mutating func dictionaryBody(allowReferences: Bool) throws -> [String: PDFReadValue] {
        var members: [String: PDFReadValue] = [:]
        while true {
            skipWhitespace()
            guard position < bytes.count else {
                throw PDFDocumentReader.ReadError.malformed("a dictionary is not closed")
            }
            if consume(">>") {
                return members
            }
            guard bytes[position] == 0x2F else {
                throw PDFDocumentReader.ReadError.malformed("a dictionary key is not a name")
            }
            position += 1
            let key = try nameText()
            members[key] = try value(allowReferences: allowReferences)
        }
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30 ... 0x39: byte - 0x30
        case 0x41 ... 0x46: byte - 0x41 + 10
        case 0x61 ... 0x66: byte - 0x61 + 10
        default: nil
        }
    }

    private mutating func hexString() throws -> [UInt8] {
        position += 1
        var digits: [UInt8] = []
        while position < bytes.count, bytes[position] != 0x3E {
            if let digit = Self.hexValue(bytes[position]) {
                digits.append(digit)
            } else if !Self.isWhitespace(bytes[position]) {
                throw PDFDocumentReader.ReadError.malformed("a hexadecimal string holds a character that is not a digit")
            }
            position += 1
        }
        guard position < bytes.count else {
            throw PDFDocumentReader.ReadError.malformed("a hexadecimal string is not closed")
        }
        position += 1
        if !digits.count.isMultiple(of: 2) {
            digits.append(0)
        }
        return stride(from: 0, to: digits.count, by: 2).map { digits[$0] << 4 | digits[$0 + 1] }
    }

    /// A literal string, with its escapes resolved (ISO 32000-1, 7.3.4.2).
    private mutating func literalString() throws -> [UInt8] {
        position += 1
        var output: [UInt8] = []
        var depth = 1
        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            switch byte {
            case 0x28:
                depth += 1
                output.append(byte)
            case 0x29:
                depth -= 1
                if depth == 0 {
                    return output
                }
                output.append(byte)
            case 0x5C:
                guard position < bytes.count else {
                    break
                }
                let escaped = bytes[position]
                position += 1
                switch escaped {
                case 0x6E: output.append(0x0A)
                case 0x72: output.append(0x0D)
                case 0x74: output.append(0x09)
                case 0x62: output.append(0x08)
                case 0x66: output.append(0x0C)
                case 0x30 ... 0x37:
                    var code = Int(escaped - 0x30)
                    var digits = 1
                    while digits < 3, position < bytes.count, (0x30 ... 0x37).contains(bytes[position]) {
                        code = code * 8 + Int(bytes[position] - 0x30)
                        position += 1
                        digits += 1
                    }
                    output.append(UInt8(truncatingIfNeeded: code))
                case 0x0D:
                    // A backslash at the end of a line continues the string.
                    if position < bytes.count, bytes[position] == 0x0A {
                        position += 1
                    }
                case 0x0A:
                    break
                default:
                    output.append(escaped)
                }
            default:
                output.append(byte)
            }
        }
        throw PDFDocumentReader.ReadError.malformed("a string is not closed")
    }

    // MARK: Indirect objects

    /// Reads `N G obj ... endobj` at the position and returns its value, a stream included.
    /// `length` resolves a `/Length` that is a reference.
    mutating func indirectObject(length: (Int) throws -> Int?) throws -> PDFReadValue {
        skipWhitespace()
        guard Double(word()) != nil else {
            throw PDFDocumentReader.ReadError.malformed("an object does not start with its number")
        }
        skipWhitespace()
        _ = word()
        skipWhitespace()
        guard consume("obj") else {
            throw PDFDocumentReader.ReadError.malformed("an object lacks the obj keyword")
        }
        let object = try value()
        skipWhitespace()
        guard case let .dictionary(members) = object, consume("stream") else {
            return object
        }
        if position < bytes.count, bytes[position] == 0x0D {
            position += 1
        }
        if position < bytes.count, bytes[position] == 0x0A {
            position += 1
        }
        let count: Int? = switch members["Length"] {
        case let .number(value)?: Int(value)
        case let .reference(number)?: try length(number)
        default: nil
        }
        guard let count, count >= 0, position + count <= bytes.count else {
            throw PDFDocumentReader.ReadError.malformed("a stream has no usable length")
        }
        let body = Array(bytes[position ..< position + count])
        position += count
        return .stream(members, body)
    }

    // MARK: Content streams

    /// The next operator of a content stream with the operands before it, or nil at
    /// the end. An inline image is not supported and ends the scan with an error.
    mutating func nextOperation() throws -> (operator: String, operands: [PDFReadValue])? {
        var operands: [PDFReadValue] = []
        while true {
            skipWhitespace()
            guard position < bytes.count else {
                return nil
            }
            let byte = bytes[position]
            let startsOperand = byte == 0x2F || byte == 0x28 || byte == 0x5B || byte == 0x3C
                || byte == 0x2B || byte == 0x2D || byte == 0x2E || (0x30 ... 0x39).contains(byte)
            if startsOperand {
                try operands.append(value(allowReferences: false))
                continue
            }
            let start = position
            let name = word()
            switch name {
            case "true": operands.append(.boolean(true))
            case "false": operands.append(.boolean(false))
            case "null": operands.append(.null)
            case "BI": throw PDFDocumentReader.ReadError.unsupported("an inline image in a content stream")
            case "":
                position = start + 1
                throw PDFDocumentReader.ReadError.malformed("a content stream holds a stray delimiter")
            default:
                return (name, operands)
            }
        }
    }
}
