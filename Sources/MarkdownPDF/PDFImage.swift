import Foundation

struct PDFImage {
    var name: String
    var width: Int
    var height: Int
    var colorSpace: PDFSyntax.Name
    var bitsPerComponent: Int
    var filter: PDFSyntax.Name
    var decodeParms: PDFSyntax.Dictionary?
    var data: Data

    static func load(
        source: String,
        baseURL: URL?,
        name: String,
    ) throws -> PDFImage {
        let url = imageURL(source: source, baseURL: baseURL)
        let data: Data

        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MarkdownPDFError.unreadableImage(source)
        }

        if let image = parseJPEG(data: data, name: name) {
            return image
        }
        if let image = parsePNG(data: data, name: name) {
            return image
        }

        throw MarkdownPDFError.unsupportedImage(source)
    }

    private static func imageURL(source: String, baseURL: URL?) -> URL {
        if let url = URL(string: source), let scheme = url.scheme, scheme == "file" {
            return url
        }
        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source)
        }
        return (baseURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .appendingPathComponent(source)
    }

    private static func parseJPEG(data: Data, name: String) -> PDFImage? {
        let bytes = [UInt8](data)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else {
            return nil
        }

        var index = 2
        while index + 9 < bytes.count {
            guard bytes[index] == 0xFF else {
                index += 1
                continue
            }

            let marker = bytes[index + 1]
            index += 2

            if marker == 0xD9 || marker == 0xDA {
                break
            }

            guard index + 1 < bytes.count else {
                return nil
            }

            let length = Int(bytes[index]) << 8 | Int(bytes[index + 1])
            guard length >= 2, index + length <= bytes.count else {
                return nil
            }

            if (0xC0 ... 0xC3).contains(marker) ||
                (0xC5 ... 0xC7).contains(marker) ||
                (0xC9 ... 0xCB).contains(marker) ||
                (0xCD ... 0xCF).contains(marker)
            {
                guard index + 7 < bytes.count else {
                    return nil
                }
                let height = Int(bytes[index + 3]) << 8 | Int(bytes[index + 4])
                let width = Int(bytes[index + 5]) << 8 | Int(bytes[index + 6])
                let components = Int(bytes[index + 7])
                let colorSpace = components == 1 ? PDFSyntax.Name("DeviceGray") : PDFSyntax.Name("DeviceRGB")

                return PDFImage(
                    name: name,
                    width: width,
                    height: height,
                    colorSpace: colorSpace,
                    bitsPerComponent: 8,
                    filter: PDFSyntax.Name("DCTDecode"),
                    decodeParms: nil,
                    data: data,
                )
            }

            index += length
        }

        return nil
    }

    private static func parsePNG(data: Data, name: String) -> PDFImage? {
        let bytes = [UInt8](data)
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard bytes.count > 33, Array(bytes.prefix(8)) == signature else {
            return nil
        }

        var index = 8
        var width: Int?
        var height: Int?
        var bits = 8
        var colorSpace = PDFSyntax.Name("DeviceRGB")
        var colors = 3
        var idat = Data()

        while index + 8 <= bytes.count {
            let length = readUInt32(bytes, index)
            let chunkStart = index + 8
            let chunkEnd = chunkStart + Int(length)
            guard chunkEnd + 4 <= bytes.count else {
                return nil
            }

            let type = String(bytes: bytes[(index + 4) ..< (index + 8)], encoding: .ascii) ?? ""
            if type == "IHDR" {
                width = Int(readUInt32(bytes, chunkStart))
                height = Int(readUInt32(bytes, chunkStart + 4))
                bits = Int(bytes[chunkStart + 8])
                let colorType = bytes[chunkStart + 9]
                let interlace = bytes[chunkStart + 12]

                guard bits == 8, interlace == 0 else {
                    return nil
                }

                switch colorType {
                case 0:
                    colorSpace = PDFSyntax.Name("DeviceGray")
                    colors = 1
                case 2:
                    colorSpace = PDFSyntax.Name("DeviceRGB")
                    colors = 3
                default:
                    return nil
                }
            } else if type == "IDAT" {
                idat.append(contentsOf: bytes[chunkStart ..< chunkEnd])
            } else if type == "IEND" {
                break
            }

            index = chunkEnd + 4
        }

        guard let width, let height, !idat.isEmpty else {
            return nil
        }

        return PDFImage(
            name: name,
            width: width,
            height: height,
            colorSpace: colorSpace,
            bitsPerComponent: bits,
            filter: PDFSyntax.Name("FlateDecode"),
            decodeParms: PDFSyntax.Dictionary([
                .init("Predictor", .int(15)),
                .init("Colors", .int(colors)),
                .init("BitsPerComponent", .int(bits)),
                .init("Columns", .int(width)),
            ]),
            data: idat,
        )
    }

    private static func readUInt32(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        UInt32(bytes[index]) << 24 |
            UInt32(bytes[index + 1]) << 16 |
            UInt32(bytes[index + 2]) << 8 |
            UInt32(bytes[index + 3])
    }
}
