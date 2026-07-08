import Foundation
import MathTypeset

struct PDFTextRun {
    var text: String
    var font: StandardFont
    var size: Double
    var color: PDFColor
    var underline: Bool
    var strikethrough: Bool
    var linkDestination: String?
    var baselineOffset: Double
    var namedDestination: String?

    /// When set, this run is drawn as a laid-out inline math box (a fraction,
    /// radical, or similar 2D construct) rather than as text. The run's `text`
    /// holds the readable linearization used as the box's ActualText for
    /// extraction, and its advance width is the box width.
    var inlineMathBox: MathBox?

    init(
        text: String,
        font: StandardFont,
        size: Double,
        color: PDFColor = .black,
        underline: Bool = false,
        strikethrough: Bool = false,
        linkDestination: String? = nil,
        baselineOffset: Double = 0,
        namedDestination: String? = nil,
        inlineMathBox: MathBox? = nil,
    ) {
        // Strip the invisible default-ignorable format controls up front (the BOM,
        // the zero-width joiners, the word joiner, the soft hyphen, the bidi
        // controls, the variation selectors, ...). They carry no glyph, and they
        // reach text runs pasted from web pages mid-document. On the embedded path
        // a cmap that omits them aborts the whole render with `missingGlyph`; the
        // base-14 path drew them as `?`. Removing them here keeps width, glyphs,
        // and the ActualText span consistent. The filter works at the scalar level,
        // so a control fused into a composed grapheme (`\u{FEFF}\u{0301}`) is
        // removed too, where a grapheme-aware replace would leave it to abort
        // downstream.
        self.text = PDFTextEncoding.strippingInvisibleFormatControls(text)
        self.font = font
        self.size = size
        self.color = color
        self.underline = underline
        self.strikethrough = strikethrough
        self.linkDestination = linkDestination
        self.baselineOffset = baselineOffset
        self.namedDestination = namedDestination
        self.inlineMathBox = inlineMathBox
    }

    func width(fontSet: PDFOptions.FontSet) -> Double {
        if let inlineMathBox {
            return inlineMathBox.width
        }
        return font.width(of: portableText, size: size, fontSet: fontSet)
    }

    var portableText: String {
        PDFTextEncoding.portableText(for: text)
    }
}
