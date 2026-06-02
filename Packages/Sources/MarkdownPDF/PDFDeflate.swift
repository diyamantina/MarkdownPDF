import Foundation

enum PDFDeflate {
    enum Strategy {
        case stored
        case fixedHuffman
    }

    enum InflateError: Error, Equatable {
        case invalidZlibHeader
        case unsupportedCompressionMethod
        case presetDictionaryUnsupported
        case headerChecksumMismatch
        case checksumMismatch
        case unexpectedEndOfInput
        case invalidBlockType
        case invalidStoredLength
        case invalidHuffmanCode
        case invalidLengthDistancePair
    }

    static func zlibCompressed(_ data: Data, strategy: Strategy = .fixedHuffman) -> Data {
        let input = Array(data)
        var output = Data([0x78, 0x01])
        output.append(rawDeflate(input, strategy: strategy))
        appendBigEndian(adler32(input), to: &output)
        return output
    }

    static func inflateZlib(_ data: Data) throws -> Data {
        let bytes = Array(data)
        guard bytes.count >= 6 else {
            throw InflateError.invalidZlibHeader
        }

        let cmf = bytes[0]
        let flg = bytes[1]
        guard cmf & 0x0F == 8 else {
            throw InflateError.unsupportedCompressionMethod
        }
        guard cmf >> 4 <= 7 else {
            throw InflateError.invalidZlibHeader
        }
        guard flg & 0x20 == 0 else {
            throw InflateError.presetDictionaryUnsupported
        }
        guard ((Int(cmf) << 8) + Int(flg)).isMultiple(of: 31) else {
            throw InflateError.headerChecksumMismatch
        }

        let expectedChecksum = UInt32(bytes[bytes.count - 4]) << 24
            | UInt32(bytes[bytes.count - 3]) << 16
            | UInt32(bytes[bytes.count - 2]) << 8
            | UInt32(bytes[bytes.count - 1])
        var reader = BitReader(bytes: Array(bytes[2 ..< bytes.count - 4]))
        var output: [UInt8] = []
        var isFinalBlock = false

        repeat {
            isFinalBlock = try reader.readBits(1) == 1
            switch try reader.readBits(2) {
            case 0:
                try inflateStoredBlock(reader: &reader, output: &output)
            case 1:
                try inflateFixedHuffmanBlock(reader: &reader, output: &output)
            default:
                throw InflateError.invalidBlockType
            }
        } while !isFinalBlock

        guard adler32(output) == expectedChecksum else {
            throw InflateError.checksumMismatch
        }

        return Data(output)
    }

    private static func rawDeflate(_ input: [UInt8], strategy: Strategy) -> Data {
        switch strategy {
        case .stored:
            storedBlocks(input)
        case .fixedHuffman:
            fixedHuffmanBlock(input)
        }
    }

    private static func storedBlocks(_ input: [UInt8]) -> Data {
        var writer = BitWriter()
        var index = 0

        repeat {
            let count = min(65535, input.count - index)
            let isFinal = index + count >= input.count
            writer.writeBits(isFinal ? 1 : 0, count: 1)
            writer.writeBits(0, count: 2)
            writer.alignToByte()
            writer.writeByte(UInt8(count & 0xFF))
            writer.writeByte(UInt8((count >> 8) & 0xFF))
            let complement = count ^ 0xFFFF
            writer.writeByte(UInt8(complement & 0xFF))
            writer.writeByte(UInt8((complement >> 8) & 0xFF))
            writer.writeBytes(input[index ..< index + count])
            index += count
        } while index < input.count

        return writer.data
    }

    private static func fixedHuffmanBlock(_ input: [UInt8]) -> Data {
        var writer = BitWriter()
        writer.writeBits(1, count: 1)
        writer.writeBits(1, count: 2)

        for token in lz77Tokens(input) {
            switch token {
            case let .literal(byte):
                writeFixedLiteralLengthSymbol(Int(byte), to: &writer)
            case let .match(length, distance):
                let lengthCode = lengthSymbol(for: length)
                writeFixedLiteralLengthSymbol(lengthCode.symbol, to: &writer)
                writer.writeBits(lengthCode.extraValue, count: lengthCode.extraBitCount)

                let distanceCode = distanceSymbol(for: distance)
                writer.writeBits(reverseBits(distanceCode.symbol, bitCount: 5), count: 5)
                writer.writeBits(distanceCode.extraValue, count: distanceCode.extraBitCount)
            }
        }

        writeFixedLiteralLengthSymbol(256, to: &writer)
        return writer.data
    }

    private static func lz77Tokens(_ input: [UInt8]) -> [Token] {
        guard !input.isEmpty else {
            return []
        }

        var table: [Int: [Int]] = [:]
        var tokens: [Token] = []
        var index = 0

        func hash(at position: Int) -> Int {
            ((Int(input[position]) << 10) ^ (Int(input[position + 1]) << 5) ^ Int(input[position + 2])) & 0x7FFF
        }

        func insert(_ position: Int) {
            guard position + 2 < input.count else {
                return
            }

            let key = hash(at: position)
            var positions = table[key, default: []]
            positions.append(position)
            if positions.count > 512 {
                positions.removeFirst(positions.count - 512)
            }
            table[key] = positions
        }

        while index < input.count {
            var bestLength = 0
            var bestDistance = 0

            if index + 2 < input.count {
                let key = hash(at: index)
                let candidates = table[key] ?? []
                var checkedCandidates = 0

                for candidate in candidates.reversed() {
                    let distance = index - candidate
                    if distance > 32768 {
                        break
                    }

                    checkedCandidates += 1
                    var length = 0
                    while length < 258,
                          index + length < input.count,
                          input[candidate + length] == input[index + length]
                    {
                        length += 1
                    }

                    if length >= 3, length > bestLength {
                        bestLength = length
                        bestDistance = distance
                    }

                    if checkedCandidates >= 128 || bestLength == 258 {
                        break
                    }
                }
            }

            if bestLength >= 3 {
                tokens.append(.match(length: bestLength, distance: bestDistance))
                for position in index ..< min(index + bestLength, input.count) {
                    insert(position)
                }
                index += bestLength
            } else {
                tokens.append(.literal(input[index]))
                insert(index)
                index += 1
            }
        }

        return tokens
    }

    private static func writeFixedLiteralLengthSymbol(_ symbol: Int, to writer: inout BitWriter) {
        let code: Int
        let bitCount: Int

        switch symbol {
        case 0 ... 143:
            code = 0x30 + symbol
            bitCount = 8
        case 144 ... 255:
            code = 0x190 + symbol - 144
            bitCount = 9
        case 256 ... 279:
            code = symbol - 256
            bitCount = 7
        case 280 ... 287:
            code = 0xC0 + symbol - 280
            bitCount = 8
        default:
            preconditionFailure("Invalid fixed Huffman literal/length symbol")
        }

        writer.writeBits(reverseBits(code, bitCount: bitCount), count: bitCount)
    }

    private static func inflateStoredBlock(reader: inout BitReader, output: inout [UInt8]) throws {
        reader.alignToByte()
        let length = try reader.readByteAlignedUInt16()
        let complement = try reader.readByteAlignedUInt16()
        guard length ^ complement == 0xFFFF else {
            throw InflateError.invalidStoredLength
        }

        for _ in 0 ..< length {
            try output.append(reader.readByteAligned())
        }
    }

    private static func inflateFixedHuffmanBlock(reader: inout BitReader, output: inout [UInt8]) throws {
        while true {
            let symbol = try fixedLiteralLengthTable.decode(from: &reader)
            switch symbol {
            case 0 ... 255:
                output.append(UInt8(symbol))
            case 256:
                return
            case 257 ... 285:
                let lengthIndex = symbol - 257
                let lengthExtra = try reader.readBits(lengthExtraBits[lengthIndex])
                let length = lengthBases[lengthIndex] + lengthExtra
                let distanceSymbol = try fixedDistanceTable.decode(from: &reader)
                guard distanceSymbol < distanceBases.count else {
                    throw InflateError.invalidLengthDistancePair
                }
                let distanceExtra = try reader.readBits(distanceExtraBits[distanceSymbol])
                let distance = distanceBases[distanceSymbol] + distanceExtra
                guard distance > 0, distance <= output.count else {
                    throw InflateError.invalidLengthDistancePair
                }

                for _ in 0 ..< length {
                    output.append(output[output.count - distance])
                }
            default:
                throw InflateError.invalidHuffmanCode
            }
        }
    }

    private static func lengthSymbol(for length: Int) -> SymbolCode {
        for index in 0 ..< lengthBases.count {
            let base = lengthBases[index]
            let extraBitCount = lengthExtraBits[index]
            let maximum = base + (1 << extraBitCount) - 1
            if length <= maximum {
                return SymbolCode(
                    symbol: 257 + index,
                    extraValue: length - base,
                    extraBitCount: extraBitCount,
                )
            }
        }

        preconditionFailure("Invalid DEFLATE match length")
    }

    private static func distanceSymbol(for distance: Int) -> SymbolCode {
        for index in 0 ..< distanceBases.count {
            let base = distanceBases[index]
            let extraBitCount = distanceExtraBits[index]
            let maximum = base + (1 << extraBitCount) - 1
            if distance <= maximum {
                return SymbolCode(
                    symbol: index,
                    extraValue: distance - base,
                    extraBitCount: extraBitCount,
                )
            }
        }

        preconditionFailure("Invalid DEFLATE match distance")
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        let modulus = 65521
        var low = 1
        var high = 0

        for byte in bytes {
            low = (low + Int(byte)) % modulus
            high = (high + low) % modulus
        }

        return UInt32((high << 16) | low)
    }

    private static func appendBigEndian(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func reverseBits(_ value: Int, bitCount: Int) -> Int {
        var reversed = 0
        for index in 0 ..< bitCount {
            reversed = (reversed << 1) | ((value >> index) & 1)
        }
        return reversed
    }

    private enum Token: Equatable {
        case literal(UInt8)
        case match(length: Int, distance: Int)
    }

    private struct SymbolCode {
        var symbol: Int
        var extraValue: Int
        var extraBitCount: Int
    }

    private struct BitWriter {
        private var bytes: [UInt8] = []
        private var currentByte: UInt8 = 0
        private var bitCount = 0

        var data: Data {
            var copy = self
            copy.flushPartialByte()
            return Data(copy.bytes)
        }

        mutating func writeBits(_ value: Int, count: Int) {
            guard count > 0 else {
                return
            }

            for index in 0 ..< count {
                if ((value >> index) & 1) == 1 {
                    currentByte |= UInt8(1 << bitCount)
                }
                bitCount += 1

                if bitCount == 8 {
                    flushFullByte()
                }
            }
        }

        mutating func alignToByte() {
            flushPartialByte()
        }

        mutating func writeByte(_ byte: UInt8) {
            if bitCount == 0 {
                bytes.append(byte)
            } else {
                writeBits(Int(byte), count: 8)
            }
        }

        mutating func writeBytes(_ bytes: ArraySlice<UInt8>) {
            for byte in bytes {
                writeByte(byte)
            }
        }

        private mutating func flushFullByte() {
            bytes.append(currentByte)
            currentByte = 0
            bitCount = 0
        }

        private mutating func flushPartialByte() {
            guard bitCount > 0 else {
                return
            }

            flushFullByte()
        }
    }

    private struct BitReader {
        var bytes: [UInt8]
        var byteIndex = 0
        var bitIndex = 0

        mutating func readBits(_ count: Int) throws -> Int {
            guard count > 0 else {
                return 0
            }

            var value = 0
            for index in 0 ..< count {
                value |= try readBit() << index
            }
            return value
        }

        mutating func alignToByte() {
            if bitIndex > 0 {
                bitIndex = 0
                byteIndex += 1
            }
        }

        mutating func readByteAligned() throws -> UInt8 {
            alignToByte()
            guard byteIndex < bytes.count else {
                throw InflateError.unexpectedEndOfInput
            }

            defer {
                byteIndex += 1
            }
            return bytes[byteIndex]
        }

        mutating func readByteAlignedUInt16() throws -> Int {
            let low = try Int(readByteAligned())
            let high = try Int(readByteAligned())
            return low | (high << 8)
        }

        private mutating func readBit() throws -> Int {
            guard byteIndex < bytes.count else {
                throw InflateError.unexpectedEndOfInput
            }

            let bit = (bytes[byteIndex] >> UInt8(bitIndex)) & 1
            bitIndex += 1
            if bitIndex == 8 {
                bitIndex = 0
                byteIndex += 1
            }
            return Int(bit)
        }
    }

    private struct HuffmanTable {
        private struct Key: Hashable {
            var bitCount: Int
            var code: Int
        }

        private var symbolsByKey: [Key: Int]
        private var maximumBitCount: Int

        init(codeLengths: [Int]) {
            maximumBitCount = codeLengths.max() ?? 0
            var countsByLength: [Int: Int] = [:]
            for length in codeLengths where length > 0 {
                countsByLength[length, default: 0] += 1
            }

            var nextCodeByLength: [Int: Int] = [:]
            var code = 0
            for bitCount in 1 ... maximumBitCount {
                code = (code + (countsByLength[bitCount - 1] ?? 0)) << 1
                nextCodeByLength[bitCount] = code
            }

            symbolsByKey = [:]
            for (symbol, bitCount) in codeLengths.enumerated() where bitCount > 0 {
                let canonicalCode = nextCodeByLength[bitCount] ?? 0
                nextCodeByLength[bitCount] = canonicalCode + 1
                symbolsByKey[
                    Key(
                        bitCount: bitCount,
                        code: reverseBits(canonicalCode, bitCount: bitCount),
                    ),
                ] = symbol
            }
        }

        func decode(from reader: inout BitReader) throws -> Int {
            var code = 0
            for bitCount in 1 ... maximumBitCount {
                code |= try reader.readBits(1) << (bitCount - 1)
                if let symbol = symbolsByKey[Key(bitCount: bitCount, code: code)] {
                    return symbol
                }
            }

            throw InflateError.invalidHuffmanCode
        }
    }

    private static let lengthBases = [
        3, 4, 5, 6, 7, 8, 9, 10,
        11, 13, 15, 17,
        19, 23, 27, 31,
        35, 43, 51, 59,
        67, 83, 99, 115,
        131, 163, 195, 227,
        258,
    ]

    private static let lengthExtraBits = [
        0, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 1,
        2, 2, 2, 2,
        3, 3, 3, 3,
        4, 4, 4, 4,
        5, 5, 5, 5,
        0,
    ]

    private static let distanceBases = [
        1, 2, 3, 4,
        5, 7,
        9, 13,
        17, 25,
        33, 49,
        65, 97,
        129, 193,
        257, 385,
        513, 769,
        1025, 1537,
        2049, 3073,
        4097, 6145,
        8193, 12289,
        16385, 24577,
    ]

    private static let distanceExtraBits = [
        0, 0, 0, 0,
        1, 1,
        2, 2,
        3, 3,
        4, 4,
        5, 5,
        6, 6,
        7, 7,
        8, 8,
        9, 9,
        10, 10,
        11, 11,
        12, 12,
        13, 13,
    ]

    private static let fixedLiteralLengthTable = HuffmanTable(
        codeLengths: (0 ... 287).map { symbol in
            switch symbol {
            case 0 ... 143:
                8
            case 144 ... 255:
                9
            case 256 ... 279:
                7
            default:
                8
            }
        },
    )

    private static let fixedDistanceTable = HuffmanTable(codeLengths: Array(repeating: 5, count: 32))
}
