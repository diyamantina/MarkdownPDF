import Foundation

enum PDFSyntax {
    struct Name: Equatable {
        var rawValue: String

        init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        var serialized: String {
            "/" + rawValue.unicodeScalars.map(escapedNameScalar).joined()
        }

        private func escapedNameScalar(_ scalar: UnicodeScalar) -> String {
            if (33 ... 126).contains(scalar.value), !Self.delimiters.contains(scalar.value) {
                return String(Character(scalar))
            }

            return String(scalar).utf8.map { byte in
                String(format: "#%02X", locale: PDFSyntax.serializationLocale, byte)
            }.joined()
        }

        private static let delimiters: Set<UInt32> = [
            0x23,
            0x25,
            0x28,
            0x29,
            0x2F,
            0x3C,
            0x3E,
            0x5B,
            0x5D,
            0x7B,
            0x7D,
        ]
    }

    struct LiteralString: Equatable {
        var rawValue: String

        init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        var serialized: String {
            var output = "("
            for scalar in rawValue.unicodeScalars {
                let byte = PDFTextEncoding.encodedByte(for: scalar)
                switch byte {
                case 0x08:
                    output += "\\b"
                case 0x09:
                    output += "\\t"
                case 0x0A:
                    output += "\\n"
                case 0x0C:
                    output += "\\f"
                case 0x0D:
                    output += "\\r"
                case 0x28:
                    output += "\\("
                case 0x29:
                    output += "\\)"
                case 0x5C:
                    output += "\\\\"
                case 32 ... 126:
                    output += String(decoding: [byte], as: UTF8.self)
                default:
                    // High bytes (0x80-0xFF, e.g. WinAnsi accented Latin and the
                    // CP1252 punctuation block) and other non-printables are
                    // emitted as three-digit octal escapes, the portable literal
                    // string form. Previously these were dropped to "?".
                    let octal = String(byte, radix: 8)
                    output += "\\" + String(repeating: "0", count: 3 - octal.count) + octal
                }
            }
            output += ")"
            return output
        }
    }

    struct HexString: Equatable {
        var bytes: [UInt8]

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        init(twoByteCodes codes: [UInt16]) {
            bytes = codes.flatMap { code in
                [
                    UInt8((code >> 8) & 0xFF),
                    UInt8(code & 0xFF),
                ]
            }
        }

        var serialized: String {
            "<" + bytes.map { byte in
                String(format: "%02X", locale: PDFSyntax.serializationLocale, byte)
            }.joined() + ">"
        }
    }

    struct Reference: Equatable, Hashable {
        var objectNumber: Int
        var generation: Int

        init(objectNumber: Int, generation: Int = 0) {
            self.objectNumber = objectNumber
            self.generation = generation
        }

        var serialized: String {
            "\(objectNumber) \(generation) R"
        }
    }

    struct Number: Equatable {
        var rawValue: Double

        init(_ rawValue: Double) {
            self.rawValue = rawValue
        }

        var serialized: String {
            let rounded = (rawValue * 1000).rounded() / 1000
            return String(format: "%.3f", locale: PDFSyntax.serializationLocale, rounded)
                .replacingOccurrences(of: ".000", with: "")
        }
    }

    struct Array {
        var values: [Value]

        init(_ values: [Value]) {
            self.values = values
        }

        var serialized: String {
            "[\(values.map(\.serialized).joined(separator: " "))]"
        }
    }

    struct Dictionary {
        enum Style {
            case inline
            case multiline
        }

        struct Entry {
            var key: Name
            var value: Value

            init(_ key: String, _ value: Value) {
                self.key = Name(key)
                self.value = value
            }
        }

        var entries: [Entry]

        init(_ entries: [Entry] = []) {
            self.entries = entries
        }

        func serialized(style: Style = .inline) -> String {
            guard !entries.isEmpty else {
                return "<< >>"
            }

            switch style {
            case .inline:
                let body = entries
                    .map { "\($0.key.serialized) \($0.value.serialized)" }
                    .joined(separator: " ")
                return "<< \(body) >>"
            case .multiline:
                return entries.enumerated().map { index, entry in
                    let line = "\(entry.key.serialized) \(entry.value.serialized)"
                    return index == 0 ? "<< \(line)" : line
                }.joined(separator: "\n") + " >>"
            }
        }
    }

    indirect enum Value {
        case name(Name)
        case int(Int)
        case number(Double)
        case bool(Bool)
        case literalString(LiteralString)
        case hexString(HexString)
        case array(Array)
        case dictionary(Dictionary)
        case reference(Reference)
        case null

        var serialized: String {
            switch self {
            case let .name(name):
                name.serialized
            case let .int(value):
                "\(value)"
            case let .number(value):
                Number(value).serialized
            case let .bool(value):
                value ? "true" : "false"
            case let .literalString(string):
                string.serialized
            case let .hexString(string):
                string.serialized
            case let .array(array):
                array.serialized
            case let .dictionary(dictionary):
                dictionary.serialized()
            case let .reference(reference):
                reference.serialized
            case .null:
                "null"
            }
        }

        static func pdfName(_ rawValue: String) -> Value {
            .name(Name(rawValue))
        }

        static func pdfString(_ rawValue: String) -> Value {
            .literalString(LiteralString(rawValue))
        }

        static func pdfArray(_ values: [Value]) -> Value {
            .array(Array(values))
        }

        static func pdfDictionary(_ entries: [Dictionary.Entry]) -> Value {
            .dictionary(Dictionary(entries))
        }
    }

    struct Stream {
        var dictionary: Dictionary
        var data: Data

        var serialized: Data {
            var dictionaryWithLength = dictionary
            dictionaryWithLength.entries.removeAll { entry in
                entry.key.rawValue == "Length"
            }
            dictionaryWithLength.entries.append(.init("Length", .int(data.count)))

            var output = Data()
            output.appendString(dictionaryWithLength.serialized())
            output.appendString("\nstream\n")
            output.append(data)
            output.appendString("\nendstream")
            return output
        }
    }

    struct IndirectObject {
        var reference: Reference
        var body: Data

        var serialized: Data {
            var output = Data()
            output.appendString("\(reference.objectNumber) \(reference.generation) obj\n")
            output.append(body)
            output.appendString("\nendobj\n")
            return output
        }
    }

    struct XrefTable {
        struct Entry: Equatable {
            var objectNumber: Int
            var offset: Int
            var generation: Int
            var inUse: Bool

            static let freeObjectZero = Entry(
                objectNumber: 0,
                offset: 0,
                generation: 65535,
                inUse: false,
            )

            var serialized: String {
                let marker = inUse ? "n" : "f"
                return String(
                    format: "%010d %05d \(marker) \n",
                    locale: PDFSyntax.serializationLocale,
                    offset,
                    generation,
                )
            }
        }

        private(set) var entries: [Entry]

        init(objectOffsets: [(reference: Reference, offset: Int)]) {
            entries = [.freeObjectZero]
            entries += objectOffsets.map { object in
                Entry(
                    objectNumber: object.reference.objectNumber,
                    offset: object.offset,
                    generation: object.reference.generation,
                    inUse: true,
                )
            }
            precondition(
                entries.map(\.objectNumber) == Swift.Array(0 ..< entries.count),
                "PDF xref entries must be consecutive from object 0",
            )
        }

        var serialized: String {
            var output = "xref\n0 \(entries.count)\n"
            for entry in entries {
                output += entry.serialized
            }
            return output
        }
    }

    struct Trailer {
        var size: Int
        var root: Reference
        var info: Reference?
        var fileID: (original: HexString, modified: HexString)?

        var serialized: String {
            var entries: [Dictionary.Entry] = [
                .init("Size", .int(size)),
                .init("Root", .reference(root)),
            ]
            if let info {
                entries.append(.init("Info", .reference(info)))
            }
            if let fileID {
                entries.append(.init("ID", .pdfArray([
                    .hexString(fileID.original),
                    .hexString(fileID.modified),
                ])))
            }

            return """
            trailer
            \(Dictionary(entries).serialized())
            """
        }
    }

    struct FileEnvelope {
        var objects: [IndirectObject]
        var root: Reference
        var info: Reference?
        var fileID: (original: HexString, modified: HexString)?

        var serialized: Data {
            let objectReferences = Set(objects.map(\.reference))
            precondition(objectReferences.contains(root), "PDF root reference must point to an emitted object")
            if let info {
                precondition(objectReferences.contains(info), "PDF info reference must point to an emitted object")
            }

            var output = Data()
            output.appendString("%PDF-1.4\n%\u{00E2}\u{00E3}\u{00CF}\u{00D3}\n")

            var objectOffsets: [(reference: Reference, offset: Int)] = []
            for object in objects {
                objectOffsets.append((reference: object.reference, offset: output.count))
                output.append(object.serialized)
            }

            let xrefStart = output.count
            let xref = XrefTable(objectOffsets: objectOffsets)
            output.appendString(xref.serialized)
            output.appendString(Trailer(size: xref.entries.count, root: root, info: info, fileID: fileID).serialized)
            output.appendString("\nstartxref\n\(xrefStart)\n%%EOF")
            return output
        }
    }

    private static let serializationLocale = Locale(identifier: "en_US_POSIX")
}

extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
