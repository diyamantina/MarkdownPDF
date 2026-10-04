import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: a PNG is built from a known sample grid by an independent encoder
/// (`TestPNGEncoder`), decoded, and every channel of every pixel is compared for
/// exact equality with values computed straight from the grid formula.
@Suite("PNG decoder")
struct PNGDecoderTests {
    struct Case: Sendable, CustomStringConvertible {
        var colorType: UInt8
        var bitDepth: Int
        var interlaced: Bool
        var compression: TestPNGEncoder.Compression
        var width: Int
        var height: Int
        var withTransparency: Bool

        var description: String {
            "type \(colorType) depth \(bitDepth) interlaced \(interlaced) \(compression) \(width)x\(height) trns \(withTransparency)"
        }
    }

    static let cases: [Case] = {
        let formats: [(UInt8, [Int])] = [(0, [1, 2, 4, 8, 16]), (2, [8, 16]), (3, [1, 2, 4, 8]), (4, [8, 16]), (6, [8, 16])]
        let sizes = [(13, 11), (1, 1), (2, 1), (1, 9), (17, 16)]
        var result: [Case] = []
        for (type, depths) in formats {
            for depth in depths {
                for interlaced in [false, true] {
                    for compression in [TestPNGEncoder.Compression.stored, .dynamicHuffman] {
                        for (width, height) in sizes {
                            for trns in [false, true] where trns == false || [0, 2, 3].contains(type) {
                                result.append(Case(
                                    colorType: type,
                                    bitDepth: depth,
                                    interlaced: interlaced,
                                    compression: compression,
                                    width: width,
                                    height: height,
                                    withTransparency: trns,
                                ))
                            }
                        }
                    }
                }
            }
        }
        return result
    }()

    /// The grid formula; the sample is always below `2^bits`.
    static func value(_ x: Int, _ y: Int, _ channel: Int, bits: Int) -> Int {
        (x * 37 + y * 59 + channel * 101 + x * y * 7 + (x / 3) * 13) % (1 << bits)
    }

    static func palette(entries: Int) -> [UInt8] {
        (0 ..< entries).flatMap { index in
            [UInt8((index * 5) & 0xFF), UInt8((index * 11 + 3) & 0xFF), UInt8((index * 17 + 7) & 0xFF)]
        }
    }

    @Test("Decodes every colour type, depth, interlace and compression to the exact grid", arguments: cases)
    func decodesToTheExactGrid(testCase: Case) throws {
        let bits = testCase.bitDepth
        let key = (
            gray: Self.value(min(2, testCase.width - 1), min(1, testCase.height - 1), 0, bits: bits),
            red: Self.value(0, 0, 0, bits: bits),
            green: Self.value(0, 0, 1, bits: bits),
            blue: Self.value(0, 0, 2, bits: bits),
        )
        var encoder = TestPNGEncoder(
            width: testCase.width,
            height: testCase.height,
            colorType: testCase.colorType,
            bitDepth: bits,
            isInterlaced: testCase.interlaced,
            compression: testCase.compression,
            sample: { x, y, channel in Self.value(x, y, channel, bits: bits) },
        )
        let paletteEntries = 1 << bits
        if testCase.colorType == 3 {
            encoder.palette = Self.palette(entries: paletteEntries)
            // Alpha for the first few entries only; the rest default to opaque.
            if testCase.withTransparency {
                encoder.transparency = (0 ..< min(3, paletteEntries)).map { UInt8($0 * 90) }
            }
        } else if testCase.withTransparency, testCase.colorType == 0 {
            encoder.transparency = [UInt8(key.gray >> 8), UInt8(key.gray & 0xFF)]
        } else if testCase.withTransparency, testCase.colorType == 2 {
            encoder.transparency = [key.red, key.green, key.blue].flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        }

        let raster = try PNGDecoder.decode([UInt8](encoder.encode()))

        #expect(raster.width == testCase.width)
        #expect(raster.height == testCase.height)

        var expectedColor: [UInt8] = []
        var expectedAlpha: [UInt8] = []
        let outputDepth = bits == 16 ? 16 : 8
        func append(_ sample: Int, to bytes: inout [UInt8]) {
            if outputDepth == 16 {
                bytes += [UInt8(sample >> 8), UInt8(sample & 0xFF)]
            } else {
                bytes.append(UInt8(sample))
            }
        }
        let opaque = (1 << outputDepth) - 1
        for y in 0 ..< testCase.height {
            for x in 0 ..< testCase.width {
                switch testCase.colorType {
                case 0:
                    let sample = Self.value(x, y, 0, bits: bits)
                    append(bits < 8 ? sample * (255 / ((1 << bits) - 1)) : sample, to: &expectedColor)
                    append(sample == key.gray ? 0 : opaque, to: &expectedAlpha)
                case 2:
                    let samples = (0 ..< 3).map { Self.value(x, y, $0, bits: bits) }
                    samples.forEach { append($0, to: &expectedColor) }
                    append(samples == [key.red, key.green, key.blue] ? 0 : opaque, to: &expectedAlpha)
                case 3:
                    let index = Self.value(x, y, 0, bits: bits)
                    let entry = Array(Self.palette(entries: paletteEntries)[index * 3 ..< index * 3 + 3])
                    expectedColor += entry
                    expectedAlpha.append(testCase.withTransparency && index < 3 ? UInt8(index * 90) : 255)
                case 4:
                    append(Self.value(x, y, 0, bits: bits), to: &expectedColor)
                    append(Self.value(x, y, 1, bits: bits), to: &expectedAlpha)
                default:
                    (0 ..< 3).forEach { append(Self.value(x, y, $0, bits: bits), to: &expectedColor) }
                    append(Self.value(x, y, 3, bits: bits), to: &expectedAlpha)
                }
            }
        }

        #expect(raster.sampleDepth == outputDepth)
        #expect(raster.colorComponents == (testCase.colorType == 0 || testCase.colorType == 4 ? 1 : 3))
        #expect(raster.color == expectedColor)
        let hasAlpha = testCase.withTransparency || testCase.colorType == 4 || testCase.colorType == 6
        if hasAlpha {
            #expect(raster.alpha == expectedAlpha)
        } else {
            #expect(raster.alpha == nil)
        }
    }

    @Test("Every filter type decodes on its own", arguments: [UInt8(0), 1, 2, 3, 4])
    func everyFilterTypeDecodes(filter: UInt8) throws {
        let encoder = TestPNGEncoder(
            width: 9,
            height: 7,
            colorType: 6,
            bitDepth: 8,
            filtering: .fixed(filter),
            sample: { x, y, channel in Self.value(x, y, channel, bits: 8) },
        )
        let raster = try PNGDecoder.decode([UInt8](encoder.encode()))
        for y in 0 ..< 7 {
            for x in 0 ..< 9 {
                for channel in 0 ..< 3 {
                    #expect(raster.color[(y * 9 + x) * 3 + channel] == UInt8(Self.value(x, y, channel, bits: 8)))
                }
                #expect(raster.alpha?[y * 9 + x] == UInt8(Self.value(x, y, 3, bits: 8)))
            }
        }
    }

    @Test("Malformed files are rejected with a typed error")
    func malformedFilesAreRejected() throws {
        let valid = [UInt8](
            TestPNGEncoder(
                width: 4,
                height: 4,
                colorType: 6,
                bitDepth: 8,
                sample: { x, y, channel in Self.value(x, y, channel, bits: 8) },
            ).encode(),
        )

        #expect(throws: PNGDecoder.DecodeError.notPNG) { try PNGDecoder.decode([]) }
        #expect(throws: PNGDecoder.DecodeError.notPNG) { try PNGDecoder.decode(Array("not a png file at all".utf8)) }
        #expect(throws: PNGDecoder.DecodeError.truncated) { try PNGDecoder.decode(Array(valid.prefix(valid.count - 20))) }
        #expect(throws: PNGDecoder.DecodeError.truncated) { try PNGDecoder.decode(Array(valid.prefix(20))) }

        var corruptedCRC = valid
        corruptedCRC[29] ^= 0xFF // inside the IHDR CRC field
        #expect(throws: PNGDecoder.DecodeError.checksumMismatch) { try PNGDecoder.decode(corruptedCRC) }

        // A header that claims an impossible depth for the colour type.
        let badDepth = TestPNGEncoder(width: 2, height: 2, colorType: 2, bitDepth: 8, sample: { _, _, _ in 0 })
        var header = [UInt8](badDepth.encode())
        header[24] = 4
        let crc = TestPNGEncoder.crc32(Array(header[12 ..< 29]))
        header.replaceSubrange(29 ..< 33, with: [UInt8(crc >> 24), UInt8((crc >> 16) & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF)])
        #expect(throws: PNGDecoder.DecodeError.invalidHeader) { try PNGDecoder.decode(header) }

        // A palette image with no PLTE chunk.
        let noPalette = TestPNGEncoder(width: 2, height: 2, colorType: 3, bitDepth: 8, sample: { _, _, _ in 0 })
        #expect(throws: PNGDecoder.DecodeError.missingPalette) { try PNGDecoder.decode([UInt8](noPalette.encode())) }

        // A palette index beyond the palette.
        var shortPalette = TestPNGEncoder(width: 2, height: 2, colorType: 3, bitDepth: 8, sample: { _, _, _ in 9 })
        shortPalette.palette = [1, 2, 3, 4, 5, 6]
        #expect(throws: PNGDecoder.DecodeError.invalidImageData) { try PNGDecoder.decode([UInt8](shortPalette.encode())) }
    }

    @Test("A forged huge header is refused before allocating")
    func forgedHugeHeaderIsRefused() throws {
        let encoder = TestPNGEncoder(width: 2, height: 2, colorType: 2, bitDepth: 8, sample: { _, _, _ in 0 })
        var bytes = [UInt8](encoder.encode())
        bytes.replaceSubrange(16 ..< 24, with: [0x7F, 0xFF, 0xFF, 0xFF, 0x7F, 0xFF, 0xFF, 0xFF])
        let crc = TestPNGEncoder.crc32(Array(bytes[12 ..< 29]))
        bytes.replaceSubrange(29 ..< 33, with: [UInt8(crc >> 24), UInt8((crc >> 16) & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF)])
        #expect(throws: PNGDecoder.DecodeError.invalidHeader) { try PNGDecoder.decode(bytes) }
    }

    @Test("CRC-32 matches the PNG specification check value")
    func crc32MatchesTheCheckValue() {
        #expect(PNGDecoder.crc32(Array("123456789".utf8)[...]) == 0xCBF4_3926)
    }
}
