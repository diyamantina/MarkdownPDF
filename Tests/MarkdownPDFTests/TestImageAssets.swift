import Foundation

enum TestImageAssets {
    static func directoryWithChartPNG(
        named name: String = "local-chart.png",
        width: Int = 96,
        height: Int = 48,
    ) throws -> URL {
        let directory = try PDFValidation.temporaryDirectory()
        try chartPNG(width: width, height: height).write(to: directory.appendingPathComponent(name))
        return directory
    }

    private static func chartPNG(width: Int, height: Int) -> Data {
        var scanlines: [UInt8] = []
        scanlines.reserveCapacity((width * 3 + 1) * height)
        for y in 0 ..< height {
            scanlines.append(0)
            for x in 0 ..< width {
                let bar = x * 4 / width
                let grid = x % 12 == 0 || y % 12 == 0
                scanlines += chartPixel(bar: bar, grid: grid)
            }
        }

        var header: [UInt8] = []
        appendUInt32(UInt32(width), to: &header)
        appendUInt32(UInt32(height), to: &header)
        header += [8, 2, 0, 0, 0]

        var png = Data(PDFValidation.pngSignature)
        png.append(pngChunk(type: "IHDR", data: header))
        png.append(pngChunk(type: "IDAT", data: zlibStored(scanlines)))
        png.append(pngChunk(type: "IEND", data: []))
        return png
    }

    private static func chartPixel(bar: Int, grid: Bool) -> [UInt8] {
        if grid {
            return [40, 44, 52]
        }

        switch bar {
        case 0:
            return [58, 134, 255]
        case 1:
            return [42, 157, 143]
        case 2:
            return [238, 155, 0]
        default:
            return [220, 75, 95]
        }
    }

    private static func pngChunk(type: String, data: [UInt8]) -> Data {
        let typeBytes = Array(type.utf8)
        var chunk = Data()
        appendUInt32(UInt32(data.count), to: &chunk)
        chunk.append(contentsOf: typeBytes)
        chunk.append(contentsOf: data)

        var crcInput = typeBytes
        crcInput.append(contentsOf: data)
        appendUInt32(crc32(crcInput), to: &chunk)
        return chunk
    }

    private static func zlibStored(_ bytes: [UInt8]) -> [UInt8] {
        var stream: [UInt8] = [0x78, 0x01]
        var index = 0
        while index < bytes.count {
            let remaining = bytes.count - index
            let count = min(remaining, 65535)
            let finalBlock = index + count == bytes.count
            stream.append(finalBlock ? 0x01 : 0x00)
            stream.append(UInt8(count & 0xFF))
            stream.append(UInt8((count >> 8) & 0xFF))
            let inverted = count ^ 0xFFFF
            stream.append(UInt8(inverted & 0xFF))
            stream.append(UInt8((inverted >> 8) & 0xFF))
            stream.append(contentsOf: bytes[index ..< (index + count)])
            index += count
        }

        appendUInt32(adler32(bytes), to: &stream)
        return stream
    }

    private static func appendUInt32(_ value: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8((value >> 24) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8(value & 0xFF))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var bytes: [UInt8] = []
        appendUInt32(value, to: &bytes)
        data.append(contentsOf: bytes)
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        let modulus: UInt32 = 65521
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % modulus
            b = (b + a) % modulus
        }
        return (b << 16) | a
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
