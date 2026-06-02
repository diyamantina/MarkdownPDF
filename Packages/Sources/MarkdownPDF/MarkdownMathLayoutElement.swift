import Foundation

enum MarkdownMathLayoutElement {
    case text(run: PDFTextRun, x: Double, y: Double)
    case rule(x: Double, y: Double, width: Double, height: Double, color: PDFColor)

    func offsetBy(x deltaX: Double, y deltaY: Double) -> MarkdownMathLayoutElement {
        switch self {
        case let .text(run, x, y):
            .text(run: run, x: x + deltaX, y: y + deltaY)
        case let .rule(x, y, width, height, color):
            .rule(x: x + deltaX, y: y + deltaY, width: width, height: height, color: color)
        }
    }
}
