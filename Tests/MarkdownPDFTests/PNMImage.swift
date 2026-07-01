import Foundation

struct PNMImage {
    struct InkBox: Equatable {
        var left: Int
        var top: Int
        var right: Int
        var bottom: Int

        var width: Int {
            right - left + 1
        }

        var height: Int {
            bottom - top + 1
        }
    }

    struct InkMetrics {
        var nonWhitePixelCount: Int
        var box: InkBox?
    }

    var width: Int
    var height: Int
    var samplesPerPixel: Int
    var samples: [UInt8]

    init(data: Data) throws {
        let bytes = [UInt8](data)
        var cursor = 0

        let magic = try Self.readToken(from: bytes, cursor: &cursor)
        switch magic {
        case "P5":
            samplesPerPixel = 1
        case "P6":
            samplesPerPixel = 3
        default:
            throw PNMImageError.unsupportedMagic(magic)
        }

        let widthToken = try Self.readToken(from: bytes, cursor: &cursor)
        let heightToken = try Self.readToken(from: bytes, cursor: &cursor)
        let maxValueToken = try Self.readToken(from: bytes, cursor: &cursor)

        guard let parsedWidth = Int(widthToken),
              let parsedHeight = Int(heightToken),
              let maxValue = Int(maxValueToken),
              parsedWidth > 0,
              parsedHeight > 0,
              maxValue == 255
        else {
            throw PNMImageError.invalidHeader
        }

        width = parsedWidth
        height = parsedHeight
        try Self.consumeRasterSeparator(from: bytes, cursor: &cursor)

        let expectedCount = width * height * samplesPerPixel
        guard bytes.count - cursor == expectedCount else {
            throw PNMImageError.invalidRasterSize(expected: expectedCount, actual: bytes.count - cursor)
        }

        samples = Array(bytes[cursor...])
    }

    func inkMetrics(threshold: UInt8 = 250) -> InkMetrics {
        var count = 0
        var box: InkBox?

        for y in 0 ..< height {
            for x in 0 ..< width where isInkPixel(x: x, y: y, threshold: threshold) {
                count += 1
                if var current = box {
                    current.left = min(current.left, x)
                    current.top = min(current.top, y)
                    current.right = max(current.right, x)
                    current.bottom = max(current.bottom, y)
                    box = current
                } else {
                    box = InkBox(left: x, top: y, right: x, bottom: y)
                }
            }
        }

        return InkMetrics(nonWhitePixelCount: count, box: box)
    }

    private func isInkPixel(x: Int, y: Int, threshold: UInt8) -> Bool {
        let offset = ((y * width) + x) * samplesPerPixel
        if samplesPerPixel == 1 {
            return samples[offset] < threshold
        }

        return samples[offset] < threshold
            || samples[offset + 1] < threshold
            || samples[offset + 2] < threshold
    }

    private static func readToken(from bytes: [UInt8], cursor: inout Int) throws -> String {
        skipWhitespaceAndComments(from: bytes, cursor: &cursor)

        guard cursor < bytes.count else {
            throw PNMImageError.truncatedHeader
        }

        let start = cursor
        while cursor < bytes.count, !isWhitespace(bytes[cursor]) {
            cursor += 1
        }

        return String(decoding: bytes[start ..< cursor], as: UTF8.self)
    }

    private static func skipWhitespaceAndComments(from bytes: [UInt8], cursor: inout Int) {
        while cursor < bytes.count {
            if isWhitespace(bytes[cursor]) {
                cursor += 1
            } else if bytes[cursor] == poundSign {
                skipComment(from: bytes, cursor: &cursor)
            } else {
                return
            }
        }
    }

    private static func skipComment(from bytes: [UInt8], cursor: inout Int) {
        while cursor < bytes.count, bytes[cursor] != newline {
            cursor += 1
        }
    }

    private static func consumeRasterSeparator(from bytes: [UInt8], cursor: inout Int) throws {
        guard cursor < bytes.count, isWhitespace(bytes[cursor]) else {
            throw PNMImageError.truncatedHeader
        }

        if bytes[cursor] == carriageReturn, cursor + 1 < bytes.count, bytes[cursor + 1] == newline {
            cursor += 2
        } else {
            cursor += 1
        }
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == space || byte == tab || byte == newline || byte == carriageReturn
    }

    private static let space = UInt8(ascii: " ")
    private static let tab = UInt8(ascii: "\t")
    private static let newline = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")
    private static let poundSign = UInt8(ascii: "#")
}

private enum PNMImageError: Error {
    case unsupportedMagic(String)
    case invalidHeader
    case truncatedHeader
    case invalidRasterSize(expected: Int, actual: Int)
}
