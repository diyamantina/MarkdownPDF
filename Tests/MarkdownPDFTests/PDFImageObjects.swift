import Foundation
@testable import MarkdownPDF

/// Image XObjects read back from the bytes of a generated PDF, with their
/// Flate-decoded samples, for pixel-exact witnesses.
struct PDFImageObjects {
    struct Image {
        var objectNumber: Int
        var dictionary: String
        var stream: Data

        var width: Int {
            integer("Width")
        }

        var height: Int {
            integer("Height")
        }

        var bitsPerComponent: Int {
            integer("BitsPerComponent")
        }

        var colorSpace: String? {
            dictionary.firstMatch(of: /\/ColorSpace \/(\w+)/)?.output.1.description
        }

        /// The object number named by `/SMask n 0 R`, if any.
        var softMaskObjectNumber: Int? {
            dictionary.firstMatch(of: /\/SMask (\d+) 0 R/).flatMap { Int($0.output.1) }
        }

        func decodedSamples() throws -> [UInt8] {
            try [UInt8](PDFDeflate.inflateZlib(stream))
        }

        private func integer(_ key: String) -> Int {
            guard let match = try? Regex("/\(key) (\\d+)").firstMatch(in: dictionary),
                  let text = match[1].substring
            else {
                return 0
            }
            return Int(text) ?? 0
        }
    }

    var images: [Image]

    init(pdf: Data) {
        let bytes = [UInt8](pdf)
        var found: [Image] = []
        let marker = Array("/Subtype /Image".utf8)
        var search = 0
        while let hit = Self.find(marker, in: bytes, from: search) {
            search = hit + marker.count
            guard let objStart = Self.findBackward(Array(" 0 obj".utf8), in: bytes, before: hit),
                  let streamStart = Self.find(Array("stream\n".utf8), in: bytes, from: hit)
            else {
                continue
            }
            var numberStart = objStart
            while numberStart > 0, bytes[numberStart - 1] >= 0x30, bytes[numberStart - 1] <= 0x39 {
                numberStart -= 1
            }
            let number = Int(String(decoding: bytes[numberStart ..< objStart], as: UTF8.self)) ?? -1
            let dictionary = String(decoding: bytes[objStart ..< streamStart], as: UTF8.self)
            guard let length = dictionary.firstMatch(of: /\/Length (\d+)/).flatMap({ Int($0.output.1) }) else {
                continue
            }
            let dataStart = streamStart + "stream\n".utf8.count
            found.append(Image(
                objectNumber: number,
                dictionary: dictionary,
                stream: Data(bytes[dataStart ..< dataStart + length]),
            ))
        }
        images = found
    }

    func image(number: Int) -> Image? {
        images.first { $0.objectNumber == number }
    }

    private static func find(_ needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard !needle.isEmpty, bytes.count >= needle.count, start <= bytes.count - needle.count else {
            return nil
        }
        for index in start ... bytes.count - needle.count where bytes[index] == needle[0] {
            if Array(bytes[index ..< index + needle.count]) == needle {
                return index
            }
        }
        return nil
    }

    private static func findBackward(_ needle: [UInt8], in bytes: [UInt8], before end: Int) -> Int? {
        var index = end - needle.count
        while index >= 0 {
            if Array(bytes[index ..< index + needle.count]) == needle {
                return index
            }
            index -= 1
        }
        return nil
    }
}
