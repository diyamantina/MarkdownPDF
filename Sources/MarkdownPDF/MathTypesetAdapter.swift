import Foundation
import MathTypeset

// Bridges the backend-neutral types from the shared MathTypeset engine to the
// PDF types this renderer draws with. The layout algorithm lives in the package;
// MarkdownPDF supplies font measurement and emits the resulting boxes as PDF
// text and rules.

extension MathFontStyle {
    init(_ font: StandardFont) {
        let variant: Variant = switch font {
        case .helvetica: .regular
        case .helveticaBold: .bold
        case .helveticaOblique: .italic
        case .courier: .monospace
        }
        self.init(variant: variant)
    }

    var standardFont: StandardFont {
        switch variant {
        case .regular: .helvetica
        case .bold, .boldItalic: .helveticaBold
        case .italic: .helveticaOblique
        case .monospace: .courier
        }
    }
}

extension MathColor {
    init(_ color: PDFColor) {
        self.init(red: color.red, green: color.green, blue: color.blue)
    }

    var pdfColor: PDFColor {
        PDFColor(red: red, green: green, blue: blue)
    }
}

extension PDFTextRun {
    init(_ run: MathRun) {
        self.init(
            text: run.text,
            font: run.font.standardFont,
            size: run.size,
            color: run.color.pdfColor,
            baselineOffset: run.baselineOffset,
        )
    }
}
