import Foundation

/// A test-only PNG encoder, independent of the production decoder. A sample
/// function defines the pixel grid; the encoder packs it, applies the scanline
/// filters, optionally interlaces with Adam7, and wraps the result in chunks.
struct TestPNGEncoder {
    enum Compression {
        case stored
        case dynamicHuffman
    }

    enum Filtering {
        case none
        /// Cycles through all five filter types, row by row.
        case cycling
        case fixed(UInt8)
    }

    var width: Int
    var height: Int
    var colorType: UInt8
    var bitDepth: Int
    var isInterlaced = false
    var compression = Compression.dynamicHuffman
    var filtering = Filtering.cycling
    var palette: [UInt8]?
    var transparency: [UInt8]?
    /// The sample (0 ..< 2^bitDepth) of `channel` at pixel (`x`, `y`).
    var sample: (_ x: Int, _ y: Int, _ channel: Int) -> Int

    var channels: Int {
        switch colorType {
        case 2: 3
        case 4: 2
        case 6: 4
        default: 1
        }
    }

    func encode() -> Data {
        var header: [UInt8] = []
        header += be32(UInt32(width)) + be32(UInt32(height))
        header += [UInt8(bitDepth), colorType, 0, 0, isInterlaced ? 1 : 0]

        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.append(chunk("IHDR", header))
        if let palette {
            png.append(chunk("PLTE", palette))
        }
        if let transparency {
            png.append(chunk("tRNS", transparency))
        }
        let raw = scanlines()
        let compressed = switch compression {
        case .stored: Self.zlibStored(raw)
        case .dynamicHuffman: TestDynamicDeflate.zlib(raw)
        }
        // Split the stream across two IDAT chunks so chunk joining is exercised.
        let half = compressed.count / 2
        png.append(chunk("IDAT", Array(compressed[0 ..< half])))
        png.append(chunk("IDAT", Array(compressed[half...])))
        png.append(chunk("IEND", []))
        return png
    }

    // MARK: Scanlines

    private func scanlines() -> [UInt8] {
        var rowIndex = 0
        var output: [UInt8] = []
        if !isInterlaced {
            appendImage(
                xs: Array(0 ..< width),
                ys: Array(0 ..< height),
                rowIndex: &rowIndex,
                to: &output,
            )
            return output
        }

        let passes: [(x: Int, y: Int, dx: Int, dy: Int)] = [
            (0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2),
        ]
        for pass in passes {
            let xs = Array(stride(from: pass.x, to: width, by: pass.dx))
            let ys = Array(stride(from: pass.y, to: height, by: pass.dy))
            guard !xs.isEmpty, !ys.isEmpty else {
                continue
            }
            appendImage(xs: xs, ys: ys, rowIndex: &rowIndex, to: &output)
        }
        return output
    }

    private func appendImage(xs: [Int], ys: [Int], rowIndex: inout Int, to output: inout [UInt8]) {
        let bitsPerPixel = channels * bitDepth
        let bytesPerPixel = max(1, bitsPerPixel / 8)
        var previous = [UInt8](repeating: 0, count: (xs.count * bitsPerPixel + 7) / 8)
        for y in ys {
            var bits: [Int] = []
            for x in xs {
                for channel in 0 ..< channels {
                    let value = sample(x, y, channel)
                    for bit in stride(from: bitDepth - 1, through: 0, by: -1) {
                        bits.append((value >> bit) & 1)
                    }
                }
            }
            var row = [UInt8](repeating: 0, count: previous.count)
            for (index, bit) in bits.enumerated() {
                row[index / 8] |= UInt8(bit << (7 - index % 8))
            }

            let type: UInt8 = switch filtering {
            case .none: 0
            case .cycling: UInt8(rowIndex % 5)
            case let .fixed(value): value
            }
            rowIndex += 1
            output.append(type)
            for index in row.indices {
                let left = index >= bytesPerPixel ? Int(row[index - bytesPerPixel]) : 0
                let up = Int(previous[index])
                let upLeft = index >= bytesPerPixel ? Int(previous[index - bytesPerPixel]) : 0
                let predictor: Int = switch type {
                case 1: left
                case 2: up
                case 3: (left + up) / 2
                case 4: Self.paeth(left, up, upLeft)
                default: 0
                }
                output.append(UInt8((Int(row[index]) - predictor) & 0xFF))
            }
            previous = row
        }
    }

    private static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c
        let pa = abs(p - a)
        let pb = abs(p - b)
        let pc = abs(p - c)
        if pa <= pb, pa <= pc {
            return a
        }
        return pb <= pc ? b : c
    }

    // MARK: Chunks

    func chunk(_ type: String, _ data: [UInt8]) -> Data {
        let typeBytes = Array(type.utf8)
        var bytes = be32(UInt32(data.count)) + typeBytes + data
        bytes += be32(Self.crc32(typeBytes + data))
        return Data(bytes)
    }

    private func be32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    static func zlibStored(_ bytes: [UInt8]) -> [UInt8] {
        var stream: [UInt8] = [0x78, 0x01]
        var index = 0
        repeat {
            let count = min(bytes.count - index, 65535)
            let isFinal = index + count == bytes.count
            stream += [isFinal ? 1 : 0, UInt8(count & 0xFF), UInt8(count >> 8), UInt8(~count & 0xFF), UInt8((~count >> 8) & 0xFF)]
            stream += bytes[index ..< index + count]
            index += count
        } while index < bytes.count

        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let checksum = b << 16 | a
        stream += [UInt8(checksum >> 24), UInt8((checksum >> 16) & 0xFF), UInt8((checksum >> 8) & 0xFF), UInt8(checksum & 0xFF)]
        return stream
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 {
                crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
