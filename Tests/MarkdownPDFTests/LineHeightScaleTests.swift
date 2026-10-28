import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: the baseline distance between two consecutive lines of one block is the
/// element's font size times its line height multiplier. Scaling the option by `k`
/// scales that distance by exactly `k`. Measured from the generated content stream
/// geometry, not from the renderer's own state.
@Suite("Line height scale")
struct LineHeightScaleTests {
    private static let tolerance = 0.002

    private static let paragraph = String(repeating: "lorem ipsum dolor sit amet ", count: 60)

    private func render(_ markdown: String, scale: Double? = nil) throws -> Data {
        var options = PDFOptions()
        if let scale {
            options.lineHeightScale = scale
        }
        return try MarkdownPDFRenderer(options: options).render(markdown: markdown)
    }

    /// Baseline gaps between consecutive text lines, top to bottom. A line is the set
    /// of fragments that share one baseline, so words and markers on a line count once.
    private func pitches(_ markdown: String, scale: Double? = nil) throws -> [Double] {
        let geometry = try ContentStreamGeometry(pdf: render(markdown, scale: scale))
        let page = try #require(geometry.pages.first)
        let baselines = Set(page.texts.map { ($0.y * 1000).rounded() / 1000 }).sorted(by: >)
        return zip(baselines, baselines.dropFirst()).map { $0 - $1 }
    }

    @Test("The default is the theme's own spacing: 11 pt body at 1.24")
    func defaultPitchIsTheThemeValue() throws {
        let gaps = try pitches(Self.paragraph)
        let first = try #require(gaps.last)
        #expect(abs(first - 11.0 * 1.24) < Self.tolerance, "pitch was \(first)")
        #expect(PDFOptions().lineHeightScale == 1)
    }

    @Test("A scale of 1 renders byte for byte the same as no scale")
    func unitScaleIsByteIdentical() throws {
        let markdown = "# Title\n\n\(Self.paragraph)\n\n- one\n- two\n\n```\ncode\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n"
        #expect(try render(markdown) == render(markdown, scale: 1))
    }

    @Test(
        "Line pitch scales by the factor for every text element",
        arguments: [
            ("paragraph", paragraph),
            ("list item", "- \(paragraph)"),
            ("block quote", "> \(paragraph)"),
            ("code block", "```\nalpha\nbeta\ngamma\ndelta\n```\n"),
        ],
    )
    func pitchScalesWithTheFactor(name: String, markdown: String) throws {
        let base = try #require(pitches(markdown).last, "\(name): no line pair found")
        for factor in [1.25, 1.5, 2.0] {
            let scaled = try #require(pitches(markdown, scale: factor).last)
            #expect(abs(scaled - base * factor) < Self.tolerance, "\(name) at \(factor): \(scaled) vs \(base * factor)")
        }
    }

    @Test("A table cell that wraps scales its line pitch")
    func tableCellPitchScales() throws {
        let markdown = "| a | b |\n|---|---|\n| \(String(repeating: "wrap ", count: 80)) | x |\n"
        let base = try #require(pitches(markdown).last)
        let scaled = try #require(pitches(markdown, scale: 1.5).last)
        #expect(abs(scaled - base * 1.5) < Self.tolerance, "\(scaled) vs \(base * 1.5)")
    }

    @Test("A looser scale makes a long document longer, a tighter one shorter")
    func scaleChangesPagination() throws {
        let markdown = String(repeating: "\(Self.paragraph)\n\n", count: 12)
        let loose = try pageCount(markdown, scale: 2)
        let normal = try pageCount(markdown, scale: 1)
        let tight = try pageCount(markdown, scale: 0.75)
        #expect(loose > normal)
        #expect(tight < normal)
    }

    @Test("Out of range scales clamp to 0.5...3 and a non-finite scale uses the default")
    func unusableScalesAreContained() throws {
        let markdown = Self.paragraph
        #expect(try render(markdown, scale: 100) == render(markdown, scale: 3))
        #expect(try render(markdown, scale: 0) == render(markdown, scale: 0.5))
        #expect(try render(markdown, scale: -4) == render(markdown, scale: 0.5))
        #expect(try render(markdown, scale: .nan) == render(markdown, scale: 1))
        #expect(try render(markdown, scale: .infinity) == render(markdown, scale: 1))
    }

    private func pageCount(_ markdown: String, scale: Double) throws -> Int {
        try ContentStreamGeometry(pdf: render(markdown, scale: scale)).pages.count
    }
}
