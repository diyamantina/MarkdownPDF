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
        case invalidDynamicHeader
        case overSubscribedCode
        case incompleteCodeLengths
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
                try inflateHuffmanBlock(
                    literalLengthTable: fixedLiteralLengthTable,
                    distanceTable: fixedDistanceTable,
                    reader: &reader,
                    output: &output,
                )
            case 2:
                let tables = try readDynamicTables(reader: &reader)
                try inflateHuffmanBlock(
                    literalLengthTable: tables.literalLength,
                    distanceTable: tables.distance,
                    reader: &reader,
                    output: &output,
                )
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

    private static func inflateHuffmanBlock(
        literalLengthTable: HuffmanTable,
        distanceTable: HuffmanTable,
        reader: inout BitReader,
        output: inout [UInt8],
    ) throws {
        while true {
            let symbol = try literalLengthTable.decode(from: &reader)
            switch symbol {
            case 0 ... 255:
                output.append(UInt8(symbol))
            case 256:
                return
            case 257 ... 285:
                let lengthIndex = symbol - 257
                let lengthExtra = try reader.readBits(lengthExtraBits[lengthIndex])
                let length = lengthBases[lengthIndex] + lengthExtra
                let distanceSymbol = try distanceTable.decode(from: &reader)
                guard distanceSymbol < distanceBases.count else {
                    throw InflateError.invalidLengthDistancePair
                }
                let distanceExtra = try reader.readBits(distanceExtraBits[distanceSymbol])
                let distance = distanceBases[distanceSymbol] + distanceExtra
                guard distance > 0, distance <= output.count else {
                    throw InflateError.invalidLengthDistancePair
                }

                var source = output.count - distance
                for _ in 0 ..< length {
                    output.append(output[source])
                    source += 1
                }
            default:
                throw InflateError.invalidHuffmanCode
            }
        }
    }

    /// Reads a dynamic block header (RFC 1951 section 3.2.7): the code-length code,
    /// then the run-length coded literal/length and distance code lengths.
    private static func readDynamicTables(
        reader: inout BitReader,
    ) throws -> (literalLength: HuffmanTable, distance: HuffmanTable) {
        let literalLengthCount = try reader.readBits(5) + 257
        let distanceCount = try reader.readBits(5) + 1
        let codeLengthCount = try reader.readBits(4) + 4
        guard literalLengthCount <= 286, distanceCount <= 30 else {
            throw InflateError.invalidDynamicHeader
        }

        var codeLengthLengths = [Int](repeating: 0, count: 19)
        for index in 0 ..< codeLengthCount {
            codeLengthLengths[codeLengthOrder[index]] = try reader.readBits(3)
        }
        let codeLengthTable = try HuffmanTable(codeLengths: codeLengthLengths)

        var lengths: [Int] = []
        lengths.reserveCapacity(literalLengthCount + distanceCount)
        while lengths.count < literalLengthCount + distanceCount {
            let symbol = try codeLengthTable.decode(from: &reader)
            switch symbol {
            case 0 ... 15:
                lengths.append(symbol)
            case 16:
                guard let previous = lengths.last else {
                    throw InflateError.invalidDynamicHeader
                }
                try lengths.append(contentsOf: repeatElement(previous, count: reader.readBits(2) + 3))
            case 17:
                try lengths.append(contentsOf: repeatElement(0, count: reader.readBits(3) + 3))
            case 18:
                try lengths.append(contentsOf: repeatElement(0, count: reader.readBits(7) + 11))
            default:
                throw InflateError.invalidHuffmanCode
            }
        }
        guard lengths.count == literalLengthCount + distanceCount, lengths[256] != 0 else {
            throw InflateError.invalidDynamicHeader
        }

        return try (
            literalLength: HuffmanTable(codeLengths: Array(lengths[0 ..< literalLengthCount])),
            distance: HuffmanTable(codeLengths: Array(lengths[literalLengthCount...])),
        )
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

    /// Reads DEFLATE bits least-significant first. Bytes load on demand, so fewer
    /// than eight bits ever stay buffered and a byte-aligned read can resume at
    /// `byteIndex` after dropping them.
    private struct BitReader {
        var bytes: [UInt8]
        var byteIndex = 0
        private var buffer = 0
        private var bufferedBitCount = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func readBits(_ count: Int) throws -> Int {
            while bufferedBitCount < count {
                guard byteIndex < bytes.count else {
                    throw InflateError.unexpectedEndOfInput
                }
                buffer |= Int(bytes[byteIndex]) << bufferedBitCount
                byteIndex += 1
                bufferedBitCount += 8
            }
            let value = buffer & ((1 << count) - 1)
            buffer >>= count
            bufferedBitCount -= count
            return value
        }

        mutating func alignToByte() {
            buffer = 0
            bufferedBitCount = 0
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
    }

    /// A canonical Huffman decoder in the shape of RFC 1951 section 3.2.2: code
    /// counts per length plus symbols sorted by (length, value). Decoding walks one
    /// bit at a time and needs no per-code allocation.
    private struct HuffmanTable {
        private static let maximumCodeLength = 15

        private var countsByLength: [Int]
        private var symbols: [Int]

        init(codeLengths: [Int]) throws {
            var counts = [Int](repeating: 0, count: Self.maximumCodeLength + 1)
            for length in codeLengths {
                guard length <= Self.maximumCodeLength else {
                    throw InflateError.invalidHuffmanCode
                }
                counts[length] += 1
            }

            var left = 1
            for length in 1 ... Self.maximumCodeLength {
                left = (left << 1) - counts[length]
                guard left >= 0 else {
                    throw InflateError.overSubscribedCode
                }
            }

            var offsets = [Int](repeating: 0, count: Self.maximumCodeLength + 2)
            for length in 1 ... Self.maximumCodeLength {
                offsets[length + 1] = offsets[length] + counts[length]
            }
            var sorted = [Int](repeating: 0, count: codeLengths.count)
            for (symbol, length) in codeLengths.enumerated() where length > 0 {
                sorted[offsets[length]] = symbol
                offsets[length] += 1
            }

            countsByLength = counts
            symbols = sorted
        }

        func decode(from reader: inout BitReader) throws -> Int {
            var code = 0
            var first = 0
            var index = 0
            for length in 1 ... Self.maximumCodeLength {
                code |= try reader.readBits(1)
                let count = countsByLength[length]
                if code - count < first {
                    return symbols[index + (code - first)]
                }
                index += count
                first = (first + count) << 1
                code <<= 1
            }

            throw InflateError.invalidHuffmanCode
        }
    }

    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

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

    private static let fixedLiteralLengthTable = makeFixedTable(
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

    private static let fixedDistanceTable = makeFixedTable(codeLengths: Array(repeating: 5, count: 32))

    /// The fixed codes of RFC 1951 section 3.2.6 are valid by construction, so a
    /// failure here is a programming error, not bad input.
    private static func makeFixedTable(codeLengths: [Int]) -> HuffmanTable {
        guard let table = try? HuffmanTable(codeLengths: codeLengths) else {
            preconditionFailure("the fixed DEFLATE code lengths are a complete prefix code")
        }
        return table
    }
}
