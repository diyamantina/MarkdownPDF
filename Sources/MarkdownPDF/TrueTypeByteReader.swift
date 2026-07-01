import Foundation

struct TrueTypeByteReader {
    var table: String
    var bytes: [UInt8]

    var count: Int {
        bytes.count
    }

    func requireRange(offset: Int, count: Int) throws {
        guard offset >= 0, count >= 0, offset <= bytes.count, count <= bytes.count - offset else {
            throw TrueTypeFontError.truncated(
                table: table,
                offset: offset,
                needed: count,
                tableLength: bytes.count,
            )
        }
    }

    func tag(at offset: Int) throws -> String {
        try requireRange(offset: offset, count: 4)
        let tagBytes = Array(bytes[offset ..< offset + 4])
        if let tag = String(bytes: tagBytes, encoding: .ascii) {
            return tag
        }
        return tagBytes.map { String(format: "%02X", locale: Locale(identifier: "en_US_POSIX"), $0) }.joined()
    }

    func uint16(at offset: Int) throws -> UInt16 {
        try requireRange(offset: offset, count: 2)
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    func int16(at offset: Int) throws -> Int16 {
        try Int16(bitPattern: uint16(at: offset))
    }

    func uint32(at offset: Int) throws -> UInt32 {
        try requireRange(offset: offset, count: 4)
        return UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }

    func fixed16Dot16(at offset: Int) throws -> Double {
        let rawValue = try Int32(bitPattern: uint32(at: offset))
        return Double(rawValue) / 65536
    }
}
