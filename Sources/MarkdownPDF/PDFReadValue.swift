/// One PDF object as ``PDFDocumentReader`` reads it back from a file.
indirect enum PDFReadValue: Equatable {
    case null
    case boolean(Bool)
    case number(Double)
    case name(String)
    /// A literal or hexadecimal string, as its bytes.
    case string([UInt8])
    case array([PDFReadValue])
    case dictionary([String: PDFReadValue])
    /// A reference to an indirect object, by object number.
    case reference(Int)
    /// A stream: its dictionary and its bytes as stored, before any filter.
    case stream([String: PDFReadValue], [UInt8])

    var dictionary: [String: PDFReadValue]? {
        switch self {
        case let .dictionary(members), let .stream(members, _):
            members
        default:
            nil
        }
    }

    var array: [PDFReadValue]? {
        if case let .array(items) = self {
            return items
        }
        return nil
    }

    var number: Double? {
        if case let .number(value) = self {
            return value
        }
        return nil
    }

    var name: String? {
        if case let .name(value) = self {
            return value
        }
        return nil
    }

    var bytes: [UInt8]? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }
}
