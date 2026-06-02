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
    }

    func width(fontSet: PDFOptions.FontSet) -> Double {
        font.width(of: portableText, size: size, fontSet: fontSet)
    }

    var portableText: String {
        PDFTextEncoding.portableText(for: text)
    }
}
