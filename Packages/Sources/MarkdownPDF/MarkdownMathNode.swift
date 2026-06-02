import Foundation

indirect enum MarkdownMathNode: Equatable {
    case sequence([MarkdownMathNode])
    case text(String)
    case symbol(display: String, linearized: String, isBigOperator: Bool)
    case fraction(numerator: MarkdownMathNode, denominator: MarkdownMathNode)
    case radical(radicand: MarkdownMathNode)
    case scripts(base: MarkdownMathNode, subscript: MarkdownMathNode?, superscript: MarkdownMathNode?)
}
