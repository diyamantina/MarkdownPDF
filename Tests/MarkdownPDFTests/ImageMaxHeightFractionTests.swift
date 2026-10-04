import Foundation
@testable import MarkdownPDF
import Testing

@Suite("Image max height fraction")
struct ImageMaxHeightFractionTests {
    private static let pageHeight = 540.0
    private static let margin = 24.0

    /// The drawn height of the one image on the page, read from its `cm` operator.
    private func drawnImageHeight(fraction: Double?) throws -> Double {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownPDFTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try tallJPEG().write(to: directory.appendingPathComponent("tall.jpg"))

        var options = PDFOptions(
            pageSize: PDFOptions.PageSize(width: 960, height: Self.pageHeight),
            margins: PDFOptions.Margins(
                top: Self.margin,
                right: Self.margin,
                bottom: Self.margin,
                left: Self.margin,
            ),
        )
        if let fraction {
            options.imageMaxHeightFraction = fraction
        }

        let data = try MarkdownPDFRenderer(options: options).render(
            markdown: "![tall](tall.jpg)",
            assetsBaseURL: directory,
        )
        let text = String(decoding: data, as: UTF8.self)
        let matrix = try #require(
            text.firstMatch(of: /([0-9.]+) 0 0 ([0-9.]+) ([0-9.]+) ([0-9.]+) cm\s+\/Im1 Do/),
            "no image draw operator found",
        )
        return try #require(Double(matrix.output.2))
    }

    @Test("The default keeps the historical 45 percent cap")
    func defaultCapIsFortyFivePercent() throws {
        let height = try drawnImageHeight(fraction: nil)
        #expect(abs(height - Self.pageHeight * 0.45) < 0.01)
    }

    @Test("A larger fraction lets the image grow to that share of the page")
    func largerFractionRaisesTheCap() throws {
        let height = try drawnImageHeight(fraction: 0.8)
        #expect(abs(height - Self.pageHeight * 0.8) < 0.01)
    }

    @Test("The cap never exceeds the content area")
    func capNeverExceedsContentArea() throws {
        let height = try drawnImageHeight(fraction: 1)
        #expect(abs(height - (Self.pageHeight - 2 * Self.margin)) < 0.01)
    }

    @Test("Out of range and non-finite fractions are clamped or defaulted")
    func unusableFractionsAreContained() throws {
        let tiny = try drawnImageHeight(fraction: -3)
        #expect(abs(tiny - Self.pageHeight * 0.05) < 0.01)
        let beyondOne = try drawnImageHeight(fraction: 7)
        #expect(abs(beyondOne - (Self.pageHeight - 2 * Self.margin)) < 0.01)
        let notANumber = try drawnImageHeight(fraction: .nan)
        #expect(abs(notANumber - Self.pageHeight * 0.45) < 0.01)
        let infinite = try drawnImageHeight(fraction: .infinity)
        #expect(abs(infinite - Self.pageHeight * 0.45) < 0.01)
    }

    /// A baseline JPEG header declaring a 2000 by 2000 image. The renderer reads
    /// only the dimensions, so the scan data stays minimal.
    private func tallJPEG() -> Data {
        Data([
            0xFF, 0xD8,
            0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
            0xFF, 0xC0, 0x00, 0x11, 0x08, 0x07, 0xD0, 0x07, 0xD0, 0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00,
            0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00,
            0x00,
            0xFF, 0xD9,
        ])
    }
}
