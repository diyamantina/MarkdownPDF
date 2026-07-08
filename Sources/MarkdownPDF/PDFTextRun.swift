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
        // Strip U+FEFF (byte-order mark / zero-width no-break space) up front. It is
        // an invisible formatting character with no glyph, and it reaches text runs
        // from BOMs pasted mid-document. The embedded-font path classified it as an
        // Arabic presentation form and threw `unsupportedComplexScriptScalar`,
        // aborting the whole render; the base-14 path drew it as `?`. Removing it
        // here keeps width, glyphs, and the ActualText span consistent.
        // Filter at the scalar level. `replacingOccurrences(of: "\u{FEFF}")` uses a
        // grapheme-aware search that will not match a BOM fused into a composed
        // sequence (`\u{FEFF}\u{0301}`), leaving it to abort downstream.
        self.text = text.unicodeScalars.contains("\u{FEFF}")
            ? String(String.UnicodeScalarView(text.unicodeScalars.filter { $0 != "\u{FEFF}" }))
            : text
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
