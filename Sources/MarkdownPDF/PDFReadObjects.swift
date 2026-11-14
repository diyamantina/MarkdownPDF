import Foundation

/// The indirect objects of a PDF file, found through its cross-reference table and
/// read on demand, for ``PDFDocumentReader``.
struct PDFReadObjects {
    let bytes: [UInt8]
    /// The byte offset of each object in use, by object number.
    let offsets: [Int: Int]
    /// The trailer dictionary of the newest cross-reference section.
    let trailer: [String: PDFReadValue]

    init(bytes: [UInt8]) throws {
        self.bytes = bytes
        guard bytes.starts(with: Array("%PDF-".utf8)) else {
            throw PDFDocumentReader.ReadError.malformed("the file does not start with %PDF-")
        }
        guard let marker = Self.lastIndex(of: Array("startxref".utf8), in: bytes) else {
            throw PDFDocumentReader.ReadError.malformed("the file has no startxref")
        }
        var scanner = PDFReadScanner(bytes, at: marker + 9)
        guard let start = try scanner.value(allowReferences: false).number.map({ Int($0) }) else {
            throw PDFDocumentReader.ReadError.malformed("startxref is not followed by an offset")
        }

        var offsets: [Int: Int] = [:]
        var newestTrailer: [String: PDFReadValue]?
        var next: Int? = start
        var visited = Set<Int>()
        while let offset = next {
            guard offset >= 0, offset < bytes.count, visited.insert(offset).inserted else {
                throw PDFDocumentReader.ReadError.malformed("a cross-reference offset points nowhere")
            }
            var section = PDFReadScanner(bytes, at: offset)
            section.skipWhitespace()
            guard section.consume("xref") else {
                throw PDFDocumentReader.ReadError.unsupported("a cross-reference stream")
            }
            while true {
                section.skipWhitespace()
                if section.consume("trailer") {
                    break
                }
                guard let first = try section.value(allowReferences: false).number, let count = try section.value(allowReferences: false).number else {
                    throw PDFDocumentReader.ReadError.malformed("a cross-reference subsection has no header")
                }
                for index in 0 ..< Int(count) {
                    guard let position = try section.value(allowReferences: false).number, try section.value(allowReferences: false).number != nil else {
                        throw PDFDocumentReader.ReadError.malformed("a cross-reference entry is not two numbers")
                    }
                    section.skipWhitespace()
                    let inUse = section.consume("n")
                    if !inUse, !section.consume("f") {
                        throw PDFDocumentReader.ReadError.malformed("a cross-reference entry is neither in use nor free")
                    }
                    // An older section never overrides a newer one.
                    let number = Int(first) + index
                    if inUse, offsets[number] == nil {
                        offsets[number] = Int(position)
                    }
                }
            }
            guard let trailer = try section.value().dictionary else {
                throw PDFDocumentReader.ReadError.malformed("the trailer is not a dictionary")
            }
            if trailer["Encrypt"] != nil {
                throw PDFDocumentReader.ReadError.unsupported("an encrypted file")
            }
            newestTrailer = newestTrailer ?? trailer
            next = trailer["Prev"]?.number.map { Int($0) }
        }
        guard let newestTrailer else {
            throw PDFDocumentReader.ReadError.malformed("the file has no trailer")
        }
        self.offsets = offsets
        trailer = newestTrailer
    }

    private static func lastIndex(of needle: [UInt8], in bytes: [UInt8]) -> Int? {
        guard bytes.count >= needle.count else {
            return nil
        }
        var index = bytes.count - needle.count
        while index >= 0 {
            if bytes[index] == needle[0], Array(bytes[index ..< index + needle.count]) == needle {
                return index
            }
            index -= 1
        }
        return nil
    }

    /// The object `value` stands for: itself, or the object a reference names. A
    /// reference to an object the file does not hold is null, as the format says.
    func resolve(_ value: PDFReadValue?) throws -> PDFReadValue {
        var current = value ?? .null
        var hops = 0
        while case let .reference(number) = current {
            guard let offset = offsets[number] else {
                return .null
            }
            hops += 1
            guard hops < 32, offset < bytes.count else {
                throw PDFDocumentReader.ReadError.malformed("object \(number) cannot be reached")
            }
            var scanner = PDFReadScanner(bytes, at: offset)
            current = try scanner.indirectObject { lengthObject in
                try resolve(.reference(lengthObject)).number.map { Int($0) }
            }
        }
        return current
    }

    /// `value` resolved, when it is a dictionary or a stream.
    func dictionary(_ value: PDFReadValue?, what: String) throws -> [String: PDFReadValue] {
        guard let dictionary = try resolve(value).dictionary else {
            throw PDFDocumentReader.ReadError.malformed("\(what) is missing or is not a dictionary")
        }
        return dictionary
    }

    /// The bytes of a stream after its filter. Only no filter and `FlateDecode` are read.
    func streamData(_ value: PDFReadValue?) throws -> [UInt8] {
        guard case let .stream(members, body) = try resolve(value) else {
            throw PDFDocumentReader.ReadError.malformed("a stream is expected and something else is there")
        }
        let filter = try resolve(members["Filter"])
        let names: [String] = filter.array?.compactMap(\.name) ?? filter.name.map { [$0] } ?? []
        switch names {
        case []:
            return body
        case ["FlateDecode"]:
            if try resolve(members["DecodeParms"]) != .null {
                throw PDFDocumentReader.ReadError.unsupported("a FlateDecode stream with a predictor")
            }
            do {
                return try Array(PDFDeflate.inflateZlib(Data(body)))
            } catch {
                throw PDFDocumentReader.ReadError.malformed("a FlateDecode stream does not inflate")
            }
        default:
            throw PDFDocumentReader.ReadError.unsupported("the stream filter \(names.joined(separator: ", "))")
        }
    }
}
