import Foundation

indirect enum MarkdownMathNode: Equatable {
    case sequence([MarkdownMathNode])
    case text(String)
    case symbol(display: String, linearized: String, isBigOperator: Bool)
    case fraction(numerator: MarkdownMathNode, denominator: MarkdownMathNode)
    case radical(radicand: MarkdownMathNode)
    case scripts(base: MarkdownMathNode, subscript: MarkdownMathNode?, superscript: MarkdownMathNode?)
    case accent(symbol: String, linearized: String, isOverline: Bool, base: MarkdownMathNode)
    case matrix(rows: [[MarkdownMathNode]], open: String, close: String, leftAlign: Bool)
    case scaledDelimiter(symbol: String, scale: Double)
}
