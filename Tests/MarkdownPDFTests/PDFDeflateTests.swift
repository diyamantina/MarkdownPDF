import Foundation
@testable import MarkdownPDF
import Testing

@Suite("PDF DEFLATE compression")
struct PDFDeflateTests {
    @Test("Zlib wrapper round trips stored and fixed Huffman blocks")
    func zlibWrapperRoundTripsStoredAndFixedHuffmanBlocks() throws {
        let inputs = [
            Data(),
            Data((0 ... 255).map(UInt8.init)),
            Data(String(repeating: "BT /F1 12 Tf 72 720 Td (Hello) Tj ET\n", count: 24).utf8),
        ]

        for strategy in [PDFDeflate.Strategy.stored, .fixedHuffman] {
            for input in inputs {
                let compressed = PDFDeflate.zlibCompressed(input, strategy: strategy)
                let inflated = try PDFDeflate.inflateZlib(compressed)

                #expect(inflated == input)
                #expect(PDFDeflate.zlibCompressed(input, strategy: strategy) == compressed)
            }
        }
    }

    @Test("Fixed Huffman encoder shrinks repeated content deterministically")
    func fixedHuffmanEncoderShrinksRepeatedContentDeterministically() throws {
        let input = Data(String(repeating: "0 0 0 rg 100 100 m 120 100 l 120 120 l S\n", count: 160).utf8)
        let compressed = PDFDeflate.zlibCompressed(input)

        #expect(compressed.count < input.count)
        #expect(try PDFDeflate.inflateZlib(compressed) == input)
        #expect(PDFDeflate.zlibCompressed(input) == compressed)
    }

    @Test("Long flat runs and a repeating pattern round trip and shrink")
    func longFlatRunsRoundTripAndShrink() throws {
        // Flat colour keeps every hash bucket full, the case that used to cost O(bucket)
        // per input byte. The output must still inflate to the input and be small.
        var input: [UInt8] = []
        for row in 0 ..< 400 {
            input += [UInt8](repeating: 0xF5, count: 3000)
            input += (0 ..< 24).map { UInt8(($0 &+ row) & 0xFF) }
        }
        let compressed = PDFDeflate.zlibCompressed(Data(input))

        #expect(try [UInt8](PDFDeflate.inflateZlib(compressed)) == input)
        #expect(compressed.count < input.count / 50)
    }

    @Test("Compression option writes valid FlateDecode content streams")
    func compressionOptionWritesValidFlateDecodeContentStreams() throws {
        let paragraph = "Repeated PDF content makes stream compression measurable and keeps text extractable."
        let markdown = "# Compression\n\n" + Array(repeating: paragraph, count: 120).joined(separator: "\n\n")
        let plain = try MarkdownPDFRenderer().render(markdown: markdown)
        let compressed = try MarkdownPDFRenderer(
            options: PDFOptions(streamCompression: .enabled),
        ).render(markdown: markdown)

        let plainInspector = PDFInspector(plain)
        let compressedInspector = PDFInspector(compressed)
        #expect(!plainInspector.text.contains("/Filter /FlateDecode"))
        #expect(compressedInspector.text.contains("/Filter /FlateDecode"))
        #expect(compressed.count < plain.count)
        #expect(
            compressedInspector.canonicalStructureIssues().isEmpty,
            "Compressed PDF structure failed:\n\(compressedInspector.canonicalStructureReport())",
        )

        let qpdf = try PDFValidation.qpdfCheck(data: compressed, name: "compressed-content-stream")
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        let plainText = try PDFValidation.pdftotext(data: plain, name: "plain-content-stream")
        let compressedText = try PDFValidation.pdftotext(data: compressed, name: "compressed-content-stream")

        try #require(plainText.exitCode == 0, "pdftotext failed:\n\(plainText.output)")
        try #require(compressedText.exitCode == 0, "pdftotext failed:\n\(compressedText.output)")
        #expect(compressedText.output == plainText.output)
    }

    @Test("FontFile2 compression preserves Length1 and encoded length")
    func fontFile2CompressionPreservesLength1AndEncodedLength() throws {
        let fontProgram = Data(String(repeating: "font-program-fragment-", count: 120).utf8)
        let stream = PDFFontFile2Stream(
            fontProgram: fontProgram,
            streamCompression: .enabled,
        ).pdfStream.serialized
        let text = String(decoding: stream, as: UTF8.self)
        let encoded = try firstStreamBody(in: stream)

        #expect(text.contains("/Length1 \(fontProgram.count)"))
        #expect(text.contains("/Filter /FlateDecode"))
        #expect(text.contains("/Length \(encoded.count)"))
        #expect(encoded.count < fontProgram.count)
        #expect(try PDFDeflate.inflateZlib(encoded) == fontProgram)
    }

    @Test("Embedded FontFile2 compression renders valid PDF")
    func embeddedFontFile2CompressionRendersValidPDF() throws {
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "TestFont")
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                embeddedFonts: .allRoles(source),
                streamCompression: .enabled,
            ),
        ).render(markdown: "# WAVE\n\nWAVE WAVE WAVE WAVE")
        let inspector = PDFInspector(data)
        let fontFileObject = try #require(inspector.indirectObjects.first { object in
            object.content.contains("/Length1 ")
        })

        #expect(fontFileObject.content.contains("/Filter /FlateDecode"))
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "Compressed embedded-font PDF structure failed:\n\(inspector.canonicalStructureReport())",
        )

        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "compressed-fontfile2")
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        let extractedText = try PDFValidation.pdftotext(data: data, name: "compressed-fontfile2")
        try #require(extractedText.exitCode == 0, "pdftotext failed:\n\(extractedText.output)")
        #expect(extractedText.output.contains("WAVE"))
    }

    @Test("Stream encoder skips compression without savings")
    func streamEncoderSkipsCompressionWithoutSavings() {
        let input = Data((0 ..< 64).map(UInt8.init))
        let stream = PDFStreamEncoder.stream(
            dictionary: PDFSyntax.Dictionary(),
            data: input,
            compression: .enabled,
        )
        let text = String(decoding: stream.serialized, as: UTF8.self)

        #expect(!text.contains("/Filter /FlateDecode"))
        #expect(text.contains("/Length 64"))
    }

    private func firstStreamBody(in data: Data) throws -> Data {
        let bytes = Array(data)
        let streamMarker = Array("stream\n".utf8)
        let endMarker = Array("\nendstream".utf8)
        let start = try #require(range(of: streamMarker, in: bytes)?.upperBound)
        let end = try #require(range(of: endMarker, in: bytes, from: start)?.lowerBound)
        return Data(bytes[start ..< end])
    }

    private func range(of needle: [UInt8], in haystack: [UInt8], from start: Int = 0) -> Range<Int>? {
        guard !needle.isEmpty, needle.count <= haystack.count, start <= haystack.count - needle.count else {
            return nil
        }

        for index in start ... haystack.count - needle.count
            where Array(haystack[index ..< index + needle.count]) == needle
        {
            return index ..< index + needle.count
        }

        return nil
    }
}

@Suite("PDF DEFLATE dynamic Huffman inflate")
struct PDFDeflateDynamicTests {
    private func pattern(count: Int) -> [UInt8] {
        var state: UInt32 = 12345
        var bytes: [UInt8] = []
        while bytes.count < count {
            state = state &* 1_664_525 &+ 1_013_904_223
            let value = UInt8(truncatingIfNeeded: state >> 24)
            switch (state >> 8) % 5 {
            case 0:
                bytes += [UInt8](repeating: value, count: Int(state >> 20) % 300 + 1)
            case 1:
                bytes += [value, value &+ 1, value, value &+ 1, value]
            default:
                bytes.append(value)
            }
        }
        return Array(bytes.prefix(count))
    }

    @Test("Inflates an independently encoded dynamic block", arguments: [0, 1, 2, 3, 255, 1000, 70000])
    func inflatesIndependentlyEncodedDynamicBlock(count: Int) throws {
        let input = pattern(count: count)
        let compressed = TestDynamicDeflate.zlib(input)

        #expect(try [UInt8](PDFDeflate.inflateZlib(Data(compressed))) == input)
    }

    @Test("Rejects truncated and corrupted dynamic streams")
    func rejectsTruncatedAndCorruptedDynamicStreams() {
        let compressed = TestDynamicDeflate.zlib(pattern(count: 5000))

        #expect(throws: PDFDeflate.InflateError.self) {
            try PDFDeflate.inflateZlib(Data(compressed.prefix(compressed.count / 2)))
        }
        var flipped = compressed
        flipped[flipped.count / 2] ^= 0x55
        #expect(throws: PDFDeflate.InflateError.self) {
            try PDFDeflate.inflateZlib(Data(flipped))
        }
    }

    @Test("Rejects a dynamic header with an over-subscribed code")
    func rejectsOverSubscribedCode() {
        // BFINAL=1, BTYPE=2, HLIT=0, HDIST=0, HCLEN=0 then four 3-bit code-length
        // lengths of 1, which over-subscribes the one-bit code space.
        var bits: [Int] = [1, 0, 1]
        bits += [0, 0, 0, 0, 0] + [0, 0, 0, 0, 0] + [0, 0, 0, 0]
        for _ in 0 ..< 4 {
            bits += [1, 0, 0]
        }
        var bytes = [UInt8](repeating: 0, count: (bits.count + 7) / 8 + 6)
        for (index, bit) in bits.enumerated() {
            bytes[index / 8] |= UInt8(bit << (index % 8))
        }
        let stream = Data([0x78, 0x01] + bytes)

        #expect(throws: PDFDeflate.InflateError.self) {
            try PDFDeflate.inflateZlib(stream)
        }
    }
}
