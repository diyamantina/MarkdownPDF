import Foundation

/// A portable PNG decoder for the renderer's image path.
///
/// It reads every PNG colour type and bit depth (greyscale, truecolour, palette,
/// greyscale with alpha, truecolour with alpha, at 1 to 16 bits where the format
/// allows them), both interlace methods, all five scanline filters, and the
/// `tRNS` transparency chunk. The result is a plain raster of 8 or 16 bit
/// samples with an optional alpha plane, ready to be written as a PDF image
/// XObject and a soft mask.
///
/// It is pure Swift over byte arrays, so it builds everywhere the core target
/// does. Ancillary colour-management chunks (`gAMA`, `cHRM`, `iCCP`, `sRGB`) are
/// ignored: samples are written as device colour, exactly as stored.
enum PNGDecoder {
    /// Decoded pixels. Samples are `sampleDepth` bits wide (8 or 16, big-endian
    /// when 16). Sub-byte greyscale and palette images are widened to 8 bits, the
    /// greyscale values scaled exactly (`v * 255 / (2^depth - 1)`).
    struct Raster: Equatable {
        var width: Int
        var height: Int
        var sampleDepth: Int
        /// 1 for greyscale, 3 for RGB.
        var colorComponents: Int
        /// `width * height * colorComponents` samples, row-major, interleaved.
        var color: [UInt8]
        /// One sample per pixel at `sampleDepth`, or nil when the image is opaque.
        var alpha: [UInt8]?

        var bytesPerSample: Int {
            sampleDepth / 8
        }
    }

    enum DecodeError: Error, Equatable {
        case notPNG
        case truncated
        case invalidChunk
        case checksumMismatch
        case invalidHeader
        case unsupportedFormat
        case missingPalette
        case missingImageData
        case invalidImageData
    }

    static func decode(_ bytes: [UInt8]) throws -> Raster {
        let parsed = try parseChunks(bytes)
        let header = parsed.header

        let compressed = parsed.imageData
        guard !compressed.isEmpty else {
            throw DecodeError.missingImageData
        }
        let inflated: [UInt8]
        do {
            inflated = try [UInt8](PDFDeflate.inflateZlib(Data(compressed)))
        } catch {
            throw DecodeError.invalidImageData
        }

        let packed = try unfilteredPixels(inflated, header: header)
        return try raster(packed: packed, header: header, parsed: parsed)
    }

    // MARK: Chunks

    struct Header: Equatable {
        var width: Int
        var height: Int
        var bitDepth: Int
        var colorType: Int
        var isInterlaced: Bool

        var channels: Int {
            switch colorType {
            case 2: 3
            case 4: 2
            case 6: 4
            default: 1
            }
        }

        var bitsPerPixel: Int {
            channels * bitDepth
        }

        func rowByteCount(width: Int) -> Int {
            (width * bitsPerPixel + 7) / 8
        }
    }

    private struct ParsedChunks {
        var header: Header
        var palette: [UInt8]?
        var transparency: [UInt8]?
        var imageData: [UInt8]
    }

    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// The largest pixel count accepted, so a forged header cannot demand an
    /// absurd allocation. It is far above any printable figure.
    private static let maximumPixelCount = 1 << 28

    private static func parseChunks(_ bytes: [UInt8]) throws -> ParsedChunks {
        guard bytes.count >= signature.count, Array(bytes[0 ..< signature.count]) == signature else {
            throw DecodeError.notPNG
        }

        var header: Header?
        var palette: [UInt8]?
        var transparency: [UInt8]?
        var imageData: [UInt8] = []
        var index = signature.count
        var sawEnd = false

        while index < bytes.count, !sawEnd {
            guard index + 12 <= bytes.count else {
                throw DecodeError.truncated
            }
            let length = Int(readUInt32(bytes, index))
            let typeStart = index + 4
            let dataStart = index + 8
            guard length <= 0x7FFF_FFFF, dataStart + length + 4 <= bytes.count else {
                throw DecodeError.truncated
            }
            let type = Array(bytes[typeStart ..< dataStart])
            let data = bytes[dataStart ..< dataStart + length]
            let storedCRC = readUInt32(bytes, dataStart + length)
            let isCritical = type[0] & 0x20 == 0
            if isCritical || type == Array("tRNS".utf8) {
                guard crc32(bytes[typeStart ..< dataStart + length]) == storedCRC else {
                    throw DecodeError.checksumMismatch
                }
            }

            switch String(decoding: type, as: UTF8.self) {
            case "IHDR":
                guard header == nil, length == 13 else {
                    throw DecodeError.invalidChunk
                }
                header = try parseHeader(Array(data))
            case "PLTE":
                guard length % 3 == 0, length > 0, length <= 768 else {
                    throw DecodeError.invalidChunk
                }
                palette = Array(data)
            case "tRNS":
                transparency = Array(data)
            case "IDAT":
                guard header != nil else {
                    throw DecodeError.invalidChunk
                }
                imageData.append(contentsOf: data)
            case "IEND":
                sawEnd = true
            default:
                if isCritical {
                    throw DecodeError.unsupportedFormat
                }
            }
            index = dataStart + length + 4
        }

        guard let header else {
            throw DecodeError.invalidHeader
        }
        guard sawEnd else {
            throw DecodeError.truncated
        }
        return ParsedChunks(header: header, palette: palette, transparency: transparency, imageData: imageData)
    }

    private static func parseHeader(_ data: [UInt8]) throws -> Header {
        let width = Int(readUInt32(data, 0))
        let height = Int(readUInt32(data, 4))
        let depth = Int(data[8])
        let colorType = Int(data[9])
        guard width > 0, height > 0, width <= 0x7FFF_FFFF, height <= 0x7FFF_FFFF,
              width <= maximumPixelCount / height
        else {
            throw DecodeError.invalidHeader
        }
        let allowedDepths: [Int]
        switch colorType {
        case 0: allowedDepths = [1, 2, 4, 8, 16]
        case 2, 4, 6: allowedDepths = [8, 16]
        case 3: allowedDepths = [1, 2, 4, 8]
        default: throw DecodeError.invalidHeader
        }
        guard allowedDepths.contains(depth), data[10] == 0, data[11] == 0, data[12] <= 1 else {
            throw DecodeError.invalidHeader
        }
        return Header(width: width, height: height, bitDepth: depth, colorType: colorType, isInterlaced: data[12] == 1)
    }

    // MARK: Unfiltering and deinterlacing

    /// Adam7 pass origins and steps: (x start, y start, x step, y step).
    private static let adam7: [(x: Int, y: Int, dx: Int, dy: Int)] = [
        (0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2),
    ]

    /// The packed, filter-free scanlines of the whole image, `rowByteCount` bytes
    /// per row, deinterlaced when the file is interlaced.
    private static func unfilteredPixels(_ inflated: [UInt8], header: Header) throws -> [UInt8] {
        if !header.isInterlaced {
            var offset = 0
            return try unfilter(inflated, offset: &offset, width: header.width, height: header.height, header: header)
        }

        let rowBytes = header.rowByteCount(width: header.width)
        var image = [UInt8](repeating: 0, count: rowBytes * header.height)
        var offset = 0
        for pass in adam7 {
            let passWidth = (header.width - pass.x + pass.dx - 1) / pass.dx
            let passHeight = (header.height - pass.y + pass.dy - 1) / pass.dy
            guard passWidth > 0, passHeight > 0 else {
                continue
            }
            let rows = try unfilter(inflated, offset: &offset, width: passWidth, height: passHeight, header: header)
            let passRowBytes = header.rowByteCount(width: passWidth)
            for row in 0 ..< passHeight {
                let destinationRow = (pass.y + row * pass.dy) * rowBytes
                for column in 0 ..< passWidth {
                    copyPixel(
                        from: rows,
                        rowStart: row * passRowBytes,
                        column: column,
                        to: &image,
                        rowStart: destinationRow,
                        column: pass.x + column * pass.dx,
                        bitsPerPixel: header.bitsPerPixel,
                    )
                }
            }
        }
        return image
    }

    private static func copyPixel(
        from source: [UInt8],
        rowStart sourceRow: Int,
        column sourceColumn: Int,
        to destination: inout [UInt8],
        rowStart destinationRow: Int,
        column destinationColumn: Int,
        bitsPerPixel: Int,
    ) {
        if bitsPerPixel >= 8 {
            let bytes = bitsPerPixel / 8
            for byte in 0 ..< bytes {
                destination[destinationRow + destinationColumn * bytes + byte] = source[sourceRow + sourceColumn * bytes + byte]
            }
            return
        }
        let sourceBit = sourceColumn * bitsPerPixel
        let destinationBit = destinationColumn * bitsPerPixel
        let value = (source[sourceRow + sourceBit / 8] >> UInt8(8 - bitsPerPixel - sourceBit % 8)) & UInt8((1 << bitsPerPixel) - 1)
        destination[destinationRow + destinationBit / 8] |= value << UInt8(8 - bitsPerPixel - destinationBit % 8)
    }

    /// Reverses the per-scanline filters of one (sub)image, reading
    /// `height * (1 + rowBytes)` bytes from `offset` and advancing it.
    private static func unfilter(
        _ data: [UInt8],
        offset: inout Int,
        width: Int,
        height: Int,
        header: Header,
    ) throws -> [UInt8] {
        let rowBytes = header.rowByteCount(width: width)
        let bytesPerPixel = max(1, header.bitsPerPixel / 8)
        guard offset + height * (rowBytes + 1) <= data.count else {
            throw DecodeError.invalidImageData
        }

        var output = [UInt8](repeating: 0, count: rowBytes * height)
        var failed = false
        data.withUnsafeBufferPointer { input in
            output.withUnsafeMutableBufferPointer { out in
                for row in 0 ..< height {
                    let filterType = input[offset + row * (rowBytes + 1)]
                    let source = offset + row * (rowBytes + 1) + 1
                    let current = row * rowBytes
                    let previous = current - rowBytes
                    switch filterType {
                    case 0:
                        for index in 0 ..< rowBytes {
                            out[current + index] = input[source + index]
                        }
                    case 1:
                        for index in 0 ..< rowBytes {
                            let left = index >= bytesPerPixel ? out[current + index - bytesPerPixel] : 0
                            out[current + index] = input[source + index] &+ left
                        }
                    case 2:
                        for index in 0 ..< rowBytes {
                            let up = row > 0 ? out[previous + index] : 0
                            out[current + index] = input[source + index] &+ up
                        }
                    case 3:
                        for index in 0 ..< rowBytes {
                            let left = index >= bytesPerPixel ? Int(out[current + index - bytesPerPixel]) : 0
                            let up = row > 0 ? Int(out[previous + index]) : 0
                            out[current + index] = input[source + index] &+ UInt8((left + up) / 2)
                        }
                    case 4:
                        for index in 0 ..< rowBytes {
                            let left = index >= bytesPerPixel ? Int(out[current + index - bytesPerPixel]) : 0
                            let up = row > 0 ? Int(out[previous + index]) : 0
                            let upLeft = (row > 0 && index >= bytesPerPixel) ? Int(out[previous + index - bytesPerPixel]) : 0
                            out[current + index] = input[source + index] &+ UInt8(paeth(left, up, upLeft))
                        }
                    default:
                        failed = true
                        return
                    }
                }
            }
        }
        if failed {
            throw DecodeError.invalidImageData
        }
        offset += height * (rowBytes + 1)
        return output
    }

    private static func paeth(_ left: Int, _ up: Int, _ upLeft: Int) -> Int {
        let estimate = left + up - upLeft
        let distanceLeft = abs(estimate - left)
        let distanceUp = abs(estimate - up)
        let distanceUpLeft = abs(estimate - upLeft)
        if distanceLeft <= distanceUp, distanceLeft <= distanceUpLeft {
            return left
        }
        return distanceUp <= distanceUpLeft ? up : upLeft
    }

    // MARK: Sample conversion

    private static func raster(packed: [UInt8], header: Header, parsed: ParsedChunks) throws -> Raster {
        let width = header.width
        let height = header.height
        let pixelCount = width * height
        let rowBytes = header.rowByteCount(width: width)
        let depth = header.bitDepth
        let outputDepth = depth == 16 ? 16 : 8
        let bytesPerSample = outputDepth / 8

        switch header.colorType {
        case 0:
            let components = 1
            var color = [UInt8](repeating: 0, count: pixelCount * bytesPerSample)
            let key = parsed.transparency.flatMap { $0.count >= 2 ? Int($0[0]) << 8 | Int($0[1]) : nil }
            var alphaPlane = [UInt8](repeating: 0, count: key == nil ? 0 : pixelCount * bytesPerSample)
            let scale = depth < 8 ? 255 / ((1 << depth) - 1) : 1
            for row in 0 ..< height {
                for column in 0 ..< width {
                    let raw = sample(packed, rowStart: row * rowBytes, index: column, depth: depth)
                    let position = (row * width + column) * bytesPerSample
                    if depth == 16 {
                        color[position] = UInt8(raw >> 8)
                        color[position + 1] = UInt8(raw & 0xFF)
                    } else {
                        color[position] = UInt8(raw * scale)
                    }
                    if let key {
                        setOpacity(&alphaPlane, at: position, bytes: bytesPerSample, opaque: raw != key)
                    }
                }
            }
            return Raster(width: width, height: height, sampleDepth: outputDepth, colorComponents: components, color: color, alpha: key == nil ? nil : alphaPlane)

        case 2:
            // Whole-byte pixels leave no row padding, so the packed rows are the samples.
            let color = packed
            var alpha: [UInt8]?
            if let trns = parsed.transparency, trns.count >= 6 {
                let keys = (0 ..< 3).map { Int(trns[$0 * 2]) << 8 | Int(trns[$0 * 2 + 1]) }
                var plane = [UInt8](repeating: 0, count: pixelCount * bytesPerSample)
                for pixel in 0 ..< pixelCount {
                    var matches = true
                    for channel in 0 ..< 3 {
                        let position = (pixel * 3 + channel) * bytesPerSample
                        let value = bytesPerSample == 2 ? Int(color[position]) << 8 | Int(color[position + 1]) : Int(color[position])
                        if value != keys[channel] {
                            matches = false
                            break
                        }
                    }
                    setOpacity(&plane, at: pixel * bytesPerSample, bytes: bytesPerSample, opaque: !matches)
                }
                alpha = plane
            }
            return Raster(width: width, height: height, sampleDepth: outputDepth, colorComponents: 3, color: color, alpha: alpha)

        case 3:
            guard let palette = parsed.palette else {
                throw DecodeError.missingPalette
            }
            var color = [UInt8](repeating: 0, count: pixelCount * 3)
            var alpha: [UInt8]? = parsed.transparency == nil ? nil : [UInt8](repeating: 255, count: pixelCount)
            let entries = palette.count / 3
            for row in 0 ..< height {
                for column in 0 ..< width {
                    let paletteIndex = sample(packed, rowStart: row * rowBytes, index: column, depth: depth)
                    guard paletteIndex < entries else {
                        throw DecodeError.invalidImageData
                    }
                    let pixel = row * width + column
                    color[pixel * 3] = palette[paletteIndex * 3]
                    color[pixel * 3 + 1] = palette[paletteIndex * 3 + 1]
                    color[pixel * 3 + 2] = palette[paletteIndex * 3 + 2]
                    if let trns = parsed.transparency, paletteIndex < trns.count {
                        alpha?[pixel] = trns[paletteIndex]
                    }
                }
            }
            return Raster(width: width, height: height, sampleDepth: 8, colorComponents: 3, color: color, alpha: alpha)

        case 4, 6:
            let colorComponents = header.colorType == 4 ? 1 : 3
            let stride = (colorComponents + 1) * bytesPerSample
            let colorStride = colorComponents * bytesPerSample
            let flat = packed
            var color = [UInt8](repeating: 0, count: pixelCount * colorStride)
            var alpha = [UInt8](repeating: 0, count: pixelCount * bytesPerSample)
            flat.withUnsafeBufferPointer { input in
                color.withUnsafeMutableBufferPointer { colorOut in
                    alpha.withUnsafeMutableBufferPointer { alphaOut in
                        for pixel in 0 ..< pixelCount {
                            let base = pixel * stride
                            for byte in 0 ..< colorStride {
                                colorOut[pixel * colorStride + byte] = input[base + byte]
                            }
                            for byte in 0 ..< bytesPerSample {
                                alphaOut[pixel * bytesPerSample + byte] = input[base + colorStride + byte]
                            }
                        }
                    }
                }
            }
            return Raster(width: width, height: height, sampleDepth: outputDepth, colorComponents: colorComponents, color: color, alpha: alpha)

        default:
            throw DecodeError.unsupportedFormat
        }
    }

    /// A raw sample of `depth` bits (1 to 16) at pixel `index` of a packed row.
    private static func sample(_ bytes: [UInt8], rowStart: Int, index: Int, depth: Int) -> Int {
        switch depth {
        case 16:
            return Int(bytes[rowStart + index * 2]) << 8 | Int(bytes[rowStart + index * 2 + 1])
        case 8:
            return Int(bytes[rowStart + index])
        default:
            let bit = index * depth
            return Int((bytes[rowStart + bit / 8] >> UInt8(8 - depth - bit % 8)) & UInt8((1 << depth) - 1))
        }
    }

    private static func setOpacity(_ plane: inout [UInt8], at position: Int, bytes: Int, opaque: Bool) {
        let value: UInt8 = opaque ? 0xFF : 0
        for byte in 0 ..< bytes {
            plane[position + byte] = value
        }
    }

    // MARK: Primitives

    private static func readUInt32(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        UInt32(bytes[index]) << 24 | UInt32(bytes[index + 1]) << 16 | UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 3])
    }

    private static let crcTable: [UInt32] = (0 ..< 256).map { value in
        var crc = UInt32(value)
        for _ in 0 ..< 8 {
            crc = crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1
        }
        return crc
    }

    /// The CRC-32 of ISO 3309 as PNG defines it.
    static func crc32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
