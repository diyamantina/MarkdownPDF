import Foundation

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
    var inlineMathBox: MarkdownMathLayoutBox?

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
        inlineMathBox: MarkdownMathLayoutBox? = nil,
    ) {
        self.text = text
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
