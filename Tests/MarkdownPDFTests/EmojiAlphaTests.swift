import Foundation
@testable import MarkdownPDF
import Testing

/// A layer of a colour emoji whose palette entry has an alpha below 255 (a shadow, a highlight, a glass) is filled with that alpha, not opaque:
/// the page selects a graphics state whose fill alpha (`ca`) is the entry's alpha over 255, and a page of opaque emoji has none. MEASURED: 15 entries
/// of the 1063 of the bundled palette are translucent (the alpha 38 to 230 of black, white and brown shades).
@Suite("Colour emoji layers keep their alpha")
struct EmojiAlphaTests {
    /// The first emoji whose drawing has a layer with an alpha below 255, with that alpha, and the first whose layers are all opaque.
    private func samples() throws -> (translucent: (scalar: Unicode.Scalar, alpha: Int), opaque: Unicode.Scalar) {
        let face = try #require(BundledFonts.colorEmoji)
        var translucent: (Unicode.Scalar, Int)?
        var opaque: Unicode.Scalar?
        for value in UInt32(0x2600) ... UInt32(0x1FAFF) {
            guard let scalar = Unicode.Scalar(value), scalar.properties.isEmoji, scalar.value > 0x7F,
                  let drawing = face.drawing(of: EmojiSegmenter.Cluster(scalars: [scalar], base: scalar), fontSize: 10)
            else { continue }
            let lowest = drawing.layers.map(\.alpha).min() ?? 255
            if lowest < 255, translucent == nil {
                translucent = (scalar, lowest)
            } else if lowest == 255, opaque == nil {
                opaque = scalar
            }
            if translucent != nil, opaque != nil {
                break
            }
        }
        return try (#require(translucent), #require(opaque))
    }

    @Test("a translucent layer is drawn under a graphics state with its alpha, and the page names that state")
    func translucentLayer() throws {
        let sample = try samples().translucent
        let data = try MarkdownPDFRenderer().render(markdown: "a \(Character(sample.scalar)) b\n")
        let text = PDFInspector(data).text
        let tokens = text.split(whereSeparator: \.isWhitespace)
        let name = "/GS\(sample.alpha)"
        #expect(tokens.contains { $0 == Substring(name) }, "the content selects no graphics state \(name)")
        #expect(text.contains("/ExtGState"), "the page has no ExtGState resource")
        let expected = PDFSyntax.Value.number(Double(sample.alpha) / 255).serialized
        #expect(text.contains("/ca \(expected)") && text.contains("/CA \(expected)"), Comment(rawValue: "no ExtGState with /ca \(expected)"))
    }

    @Test("a page of opaque emoji selects no graphics state and has no ExtGState resource")
    func opaqueEmoji() throws {
        let sample = try samples().opaque
        let data = try MarkdownPDFRenderer().render(markdown: "a \(Character(sample)) b\n")
        let text = PDFInspector(data).text
        #expect(!text.contains("/ExtGState"))
        #expect(!text.split(whereSeparator: \.isWhitespace).contains("gs"))
    }
}
