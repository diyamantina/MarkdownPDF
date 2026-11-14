import Foundation
@testable import MarkdownPDF
import Testing

/// Witnesses that PNGs the renderer used to replace with `[Image: alt]` now embed
/// as images: the PDF's image XObject and soft mask are decoded and compared with
/// the source grid, and the box the image is drawn into is read from the page.
@Suite("PNG image rendering")
struct PNGImageRenderTests {
    /// Quadrant colours of the 2 x 2 test image, with alpha.
    private static let quadrants: [[Int]] = [
        [200, 30, 40, 255], [20, 160, 60, 128],
        [30, 60, 220, 64], [250, 240, 20, 0],
    ]

    private func render(_ png: Data, alt: String = "figure", options: PDFOptions = PDFOptions()) throws -> Data {
        let directory = try PDFValidation.temporaryDirectory()
        try png.write(to: directory.appendingPathComponent("figure.png"))
        return try MarkdownPDFRenderer(options: options).render(
            markdown: "![\(alt)](figure.png)",
            assetsBaseURL: directory,
        )
    }

    private func softMask(of image: PDFImageObjects.Image, in objects: PDFImageObjects) throws -> PDFImageObjects.Image {
        let number = try #require(image.softMaskObjectNumber)
        return try #require(objects.image(number: number))
    }

    private func quadrantPNG(size: Int, colorType: UInt8 = 6, bitDepth: Int = 8) -> Data {
        TestPNGEncoder(
            width: size,
            height: size,
            colorType: colorType,
            bitDepth: bitDepth,
            sample: { x, y, channel in
                let quadrant = Self.quadrants[(y * 2 / size) * 2 + x * 2 / size]
                return quadrant[channel]
            },
        ).encode()
    }

    @Test("An RGBA PNG embeds as an RGB image with an alpha soft mask, sample for sample")
    func rgbaEmbedsWithSoftMask() throws {
        let size = 40
        let pdf = try render(quadrantPNG(size: size))
        let objects = PDFImageObjects(pdf: pdf)

        let image = try #require(objects.images.first { $0.softMaskObjectNumber != nil })
        let mask = try softMask(of: image, in: objects)
        #expect(image.colorSpace == "DeviceRGB")
        #expect(mask.colorSpace == "DeviceGray")
        let dimensions: [Int] = [image.width, image.height, mask.width, mask.height]
        #expect(dimensions == [Int](repeating: size, count: 4))
        #expect(image.bitsPerComponent == 8)
        #expect(mask.bitsPerComponent == 8)

        let color = try image.decodedSamples()
        let alpha = try mask.decodedSamples()
        #expect(color.count == size * size * 3)
        #expect(alpha.count == size * size)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let quadrant = Self.quadrants[(y * 2 / size) * 2 + x * 2 / size]
                for channel in 0 ..< 3 {
                    #expect(Int(color[(y * size + x) * 3 + channel]) == quadrant[channel])
                }
                #expect(Int(alpha[y * size + x]) == quadrant[3])
            }
        }

        let text = try PDFValidation.text(pdf)
        #expect(!text.contains("[Image:"))
        let inspector = PDFInspector(pdf)
        #expect(inspector.canonicalStructureIssues().isEmpty, "\(inspector.canonicalStructureReport())")
        try PDFValidation.requireSoundStructure(pdf, name: "rgba-png")
    }

    @Test("A fully opaque RGBA PNG drops the soft mask")
    func opaqueRGBADropsSoftMask() throws {
        let png = TestPNGEncoder(
            width: 8,
            height: 8,
            colorType: 6,
            bitDepth: 8,
            sample: { x, y, channel in channel == 3 ? 255 : (x * 31 + y * 17 + channel * 50) % 256 },
        ).encode()
        let objects = try PDFImageObjects(pdf: render(png))

        #expect(objects.images.count == 1)
        #expect(objects.images.first?.softMaskObjectNumber == nil)
    }

    @Test("A gray plus alpha PNG embeds as DeviceGray with a soft mask")
    func grayAlphaEmbeds() throws {
        let objects = try PDFImageObjects(pdf: render(quadrantPNG(size: 8, colorType: 4)))
        let image = try #require(objects.images.first { $0.softMaskObjectNumber != nil })
        let mask = try softMask(of: image, in: objects)

        #expect(image.colorSpace == "DeviceGray")
        #expect(try image.decodedSamples().count == 64)
        // For gray plus alpha, channel 1 of the grid is alpha.
        let expected = (0 ..< 8).flatMap { y in (0 ..< 8).map { x in UInt8(Self.quadrants[(y * 2 / 8) * 2 + x * 2 / 8][1]) } }
        #expect(try mask.decodedSamples() == expected)
    }

    @Test("A 16 bit RGBA PNG embeds at 16 bits per component")
    func sixteenBitEmbeds() throws {
        let objects = try PDFImageObjects(pdf: render(
            TestPNGEncoder(
                width: 6,
                height: 5,
                colorType: 6,
                bitDepth: 16,
                sample: { x, y, channel in (x * 4001 + y * 9973 + channel * 15013) % 65536 },
            ).encode(),
        ))
        let image = try #require(objects.images.first { $0.softMaskObjectNumber != nil })
        let mask = try softMask(of: image, in: objects)

        #expect(image.bitsPerComponent == 16)
        #expect(mask.bitsPerComponent == 16)
        let color = try image.decodedSamples()
        #expect(color.count == 6 * 5 * 3 * 2)
        let sample = (2 * 4001 + 3 * 9973 + 1 * 15013) % 65536
        let position = (3 * 6 + 2) * 6 + 2
        #expect(Int(color[position]) << 8 | Int(color[position + 1]) == sample)
    }

    @Test("A palette PNG with tRNS embeds with its alpha table as a soft mask")
    func paletteEmbeds() throws {
        var palette = TestPNGEncoder(
            width: 5,
            height: 5,
            colorType: 3,
            bitDepth: 2,
            sample: { x, y, _ in (x + y) % 4 },
        )
        palette.palette = [255, 0, 0, 0, 255, 0, 0, 0, 255, 9, 9, 9]
        palette.transparency = [255, 128, 0]
        let paletteObjects = try PDFImageObjects(pdf: render(palette.encode()))
        let paletteImage = try #require(paletteObjects.images.first { $0.softMaskObjectNumber != nil })
        #expect(paletteImage.colorSpace == "DeviceRGB")
        let paletteMask = try softMask(of: paletteImage, in: paletteObjects)
        let alpha = try paletteMask.decodedSamples()
        #expect(alpha[0] == 255)
        #expect(alpha[1] == 128)
        #expect(alpha[2] == 0)
        #expect(alpha[3] == 255)
    }

    @Test("An interlaced RGBA PNG embeds")
    func interlacedEmbeds() throws {
        var interlaced = TestPNGEncoder(
            width: 11,
            height: 9,
            colorType: 6,
            bitDepth: 8,
            sample: { x, y, channel in (x * 23 + y * 41 + channel * 7) % 256 },
        )
        interlaced.isInterlaced = true
        let interlacedObjects = try PDFImageObjects(pdf: render(interlaced.encode()))
        let interlacedImage = try #require(interlacedObjects.images.first { $0.softMaskObjectNumber != nil })
        let color = try interlacedImage.decodedSamples()
        #expect(Int(color[(4 * 11 + 6) * 3 + 1]) == (6 * 23 + 4 * 41 + 7) % 256)
    }

    @Test("An unreadable PNG still degrades to the image placeholder")
    func corruptPNGKeepsPlaceholder() throws {
        var png = [UInt8](quadrantPNG(size: 8))
        png.removeLast(30)
        let pdf = try render(Data(png), alt: "broken figure")
        let text = try PDFValidation.text(pdf)
        #expect(text.contains("[Image: broken figure]"))
        #expect(PDFImageObjects(pdf: pdf).images.isEmpty)
    }

    @Test("Existing 8 bit RGB PNGs keep their pass-through encoding byte for byte")
    func rgbPassThroughIsUnchanged() throws {
        let directory = try TestImageAssets.directoryWithChartPNG()
        let pdf = try MarkdownPDFRenderer().render(
            markdown: "![chart](local-chart.png)",
            assetsBaseURL: directory,
        )
        let image = try #require(PDFImageObjects(pdf: pdf).images.first)

        #expect(image.dictionary.contains("/DecodeParms << /Predictor 15 /Colors 3 /BitsPerComponent 8 /Columns 96 >>"))
        #expect(image.softMaskObjectNumber == nil)
    }

    @Test("An RGBA image is drawn as a square at the top left corner, capped at the image height fraction, over a bare page")
    func rgbaImageIsPlacedAtTheTopLeft() throws {
        let size = 200
        var options = PDFOptions()
        options.margins = PDFOptions.Margins(top: 0, right: 0, bottom: 0, left: 0)
        options.pageSize = PDFOptions.PageSize(width: 200, height: 200)
        let pdf = try render(quadrantPNG(size: size), options: options)

        // The renderer caps a standalone image at 45% of the page height: a square
        // of that side, with its top left corner at the top left corner of the page.
        let drawn = Double(size) * PDFOptions.defaultImageMaxHeightFraction
        let number = #"(-?[0-9]+(?:\.[0-9]+)?)"#
        let pattern = try Regex("\(number) 0 0 \(number) \(number) \(number) cm\\s+/Im[0-9]+ Do")
        let streams = PDFInspector(pdf).streams.map(\.body)
        let matches = streams.flatMap { $0.matches(of: pattern) }
        try #require(matches.count == 1, "the image is not drawn exactly once")
        let box = (1 ... 4).compactMap { matches[0][$0].substring.flatMap { Double($0) } }
        try #require(box.count == 4)
        #expect(abs(box[0] - drawn) < 0.001 && abs(box[1] - drawn) < 0.001, "the image box is \(box[0]) x \(box[1]), not \(drawn) square")
        #expect(abs(box[2]) < 0.001 && abs(box[3] + box[1] - Double(size)) < 0.001, "the image box does not start at the top left corner: \(box)")
        // Nothing is painted under the image, so what shows through its alpha is the bare page.
        let stream = try #require(streams.first { $0.contains(" Do") })
        let paints = stream.split(whereSeparator: \.isWhitespace).filter { ["f", "f*", "B", "S", "sh", "Tj"].contains(String($0)) }
        #expect(paints.isEmpty, "other marks on the page: \(paints)")
    }

    /// What the placement and the decoded samples cannot say: that a rasterizer
    /// blends each quadrant with white by its alpha.
    @Test(
        "A rasterizer composites the soft mask over white",
        .disabled("not verified: needs a rasterizer inside MarkdownPDF, see Docs/NOT-VERIFIED.md"),
    )
    func rastersCompositeOverWhite() {
        PDFValidation.notVerified("the composited pixels of an RGBA image")
    }
}
