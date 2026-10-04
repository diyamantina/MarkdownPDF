import Foundation

/// A test-only DEFLATE encoder that writes one dynamic-Huffman block, built
/// independently of the production code so it can witness the inflater.
///
/// Codes are balanced and complete (RFC 1951 section 3.2.2): for `n` symbols
/// and `L = ceil(log2 n)`, `2^L - n` symbols get `L - 1` bits and the rest `L`.
/// The code-length alphabet exercises symbols 16, 17 and 18, and the data
/// exercises length/distance matches.
enum TestDynamicDeflate {
    static func zlib(_ input: [UInt8]) -> [UInt8] {
        var writer = BitWriter()
        writer.write(1, count: 1) // final block
        writer.write(2, count: 2) // dynamic Huffman

        let tokens = tokenize(input)
        let literalLengths = balancedLengths(count: 286)
        let distanceLengths = balancedLengths(count: 30)
        let literalCodes = canonicalCodes(literalLengths)
        let distanceCodes = canonicalCodes(distanceLengths)

        let lengthSequence = literalLengths + distanceLengths
        let runs = runLengthEncode(lengthSequence)
        let codeLengthLengths = balancedLengths(count: 19)
        let codeLengthCodes = canonicalCodes(codeLengthLengths)

        writer.write(286 - 257, count: 5)
        writer.write(30 - 1, count: 5)
        writer.write(19 - 4, count: 4)
        let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
        for symbol in order {
            writer.write(codeLengthLengths[symbol], count: 3)
        }
        for run in runs {
            writer.writeCode(codeLengthCodes[run.symbol], length: codeLengthLengths[run.symbol])
            if run.extraBits > 0 {
                writer.write(run.extraValue, count: run.extraBits)
            }
        }

        for token in tokens {
            switch token {
            case let .literal(byte):
                writer.writeCode(literalCodes[Int(byte)], length: literalLengths[Int(byte)])
            case let .match(length, distance):
                let lengthSymbol = lengthSymbol(for: length)
                writer.writeCode(literalCodes[lengthSymbol.symbol], length: literalLengths[lengthSymbol.symbol])
                writer.write(lengthSymbol.extraValue, count: lengthSymbol.extraBits)
                let distanceSymbol = distanceSymbol(for: distance)
                writer.writeCode(distanceCodes[distanceSymbol.symbol], length: distanceLengths[distanceSymbol.symbol])
                writer.write(distanceSymbol.extraValue, count: distanceSymbol.extraBits)
            }
        }
        writer.writeCode(literalCodes[256], length: literalLengths[256])

        var output: [UInt8] = [0x78, 0x9C]
        output += writer.bytes()
        let checksum = adler32(input)
        output += [UInt8(checksum >> 24), UInt8((checksum >> 16) & 0xFF), UInt8((checksum >> 8) & 0xFF), UInt8(checksum & 0xFF)]
        return output
    }

    // MARK: Tokens

    private enum Token {
        case literal(UInt8)
        case match(length: Int, distance: Int)
    }

    /// Runs of one byte become distance-1 matches; every fourth distinct byte
    /// pair repeats at distance 2, so both distance codes occur.
    private static func tokenize(_ input: [UInt8]) -> [Token] {
        var tokens: [Token] = []
        var index = 0
        while index < input.count {
            if index >= 1 {
                var run = 0
                while index + run < input.count, run < 258, input[index + run] == input[index - 1] {
                    run += 1
                }
                if run >= 3 {
                    tokens.append(.match(length: run, distance: 1))
                    index += run
                    continue
                }
            }
            if index >= 2, index + 3 <= input.count,
               input[index] == input[index - 2], input[index + 1] == input[index - 1], input[index + 2] == input[index]
            {
                tokens.append(.match(length: 3, distance: 2))
                index += 3
                continue
            }
            tokens.append(.literal(input[index]))
            index += 1
        }
        return tokens
    }

    private static let lengthBases = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBases = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
    ]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    private static func lengthSymbol(for length: Int) -> (symbol: Int, extraBits: Int, extraValue: Int) {
        var index = lengthBases.count - 1
        while lengthBases[index] > length {
            index -= 1
        }
        return (257 + index, lengthExtra[index], length - lengthBases[index])
    }

    private static func distanceSymbol(for distance: Int) -> (symbol: Int, extraBits: Int, extraValue: Int) {
        var index = distanceBases.count - 1
        while distanceBases[index] > distance {
            index -= 1
        }
        return (index, distanceExtra[index], distance - distanceBases[index])
    }

    // MARK: Codes

    private static func balancedLengths(count: Int) -> [Int] {
        var bits = 1
        while (1 << bits) < count {
            bits += 1
        }
        let short = (1 << bits) - count
        return (0 ..< count).map { $0 < short ? bits - 1 : bits }
    }

    private static func canonicalCodes(_ lengths: [Int]) -> [Int] {
        var codes = [Int](repeating: 0, count: lengths.count)
        var code = 0
        for length in 1 ... 15 {
            for symbol in lengths.indices where lengths[symbol] == length {
                codes[symbol] = code
                code += 1
            }
            code <<= 1
        }
        return codes
    }

    private struct Run {
        var symbol: Int
        var extraBits: Int
        var extraValue: Int
    }

    private static func runLengthEncode(_ lengths: [Int]) -> [Run] {
        var runs: [Run] = []
        var index = 0
        while index < lengths.count {
            let value = lengths[index]
            var count = 1
            while index + count < lengths.count, lengths[index + count] == value {
                count += 1
            }
            var remaining = count
            if value == 0 {
                while remaining >= 11 {
                    let take = min(remaining, 138)
                    runs.append(Run(symbol: 18, extraBits: 7, extraValue: take - 11))
                    remaining -= take
                }
                while remaining >= 3 {
                    let take = min(remaining, 10)
                    runs.append(Run(symbol: 17, extraBits: 3, extraValue: take - 3))
                    remaining -= take
                }
            } else if remaining >= 4 {
                runs.append(Run(symbol: value, extraBits: 0, extraValue: 0))
                remaining -= 1
                while remaining >= 3 {
                    let take = min(remaining, 6)
                    runs.append(Run(symbol: 16, extraBits: 2, extraValue: take - 3))
                    remaining -= take
                }
            }
            for _ in 0 ..< remaining {
                runs.append(Run(symbol: value, extraBits: 0, extraValue: 0))
            }
            index += count
        }
        return runs
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return b << 16 | a
    }

    private struct BitWriter {
        private var storage: [UInt8] = []
        private var current = 0
        private var count = 0

        /// Writes `value` least-significant bit first (header fields, extra bits).
        mutating func write(_ value: Int, count bitCount: Int) {
            for bit in 0 ..< bitCount {
                append((value >> bit) & 1)
            }
        }

        /// Writes a Huffman code most-significant bit first.
        mutating func writeCode(_ code: Int, length: Int) {
            for bit in stride(from: length - 1, through: 0, by: -1) {
                append((code >> bit) & 1)
            }
        }

        private mutating func append(_ bit: Int) {
            current |= bit << count
            count += 1
            if count == 8 {
                storage.append(UInt8(current))
                current = 0
                count = 0
            }
        }

        func bytes() -> [UInt8] {
            count == 0 ? storage : storage + [UInt8(current)]
        }
    }
}
