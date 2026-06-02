import Foundation

struct MarkdownMathLinearizer {
    func linearize(_ node: MarkdownMathNode) -> String {
        collapseSpaces(rawLinearization(for: node))
    }

    private func rawLinearization(for node: MarkdownMathNode) -> String {
        switch node {
        case let .sequence(children):
            return children.map(rawLinearization).joined()
        case let .text(text):
            return text
        case let .symbol(_, linearized, _):
            return linearized
        case let .fraction(numerator, denominator):
            return "frac(\(linearize(numerator)), \(linearize(denominator)))"
        case let .radical(radicand):
            return "sqrt(\(linearize(radicand)))"
        case let .scripts(base, subscriptNode, superscriptNode):
            var result = parenthesizedIfNeeded(base)
            if let subscriptNode {
                result += "_{\(linearize(subscriptNode))}"
            }
            if let superscriptNode {
                result += "^{\(linearize(superscriptNode))}"
            }
            return result
        }
    }

    private func parenthesizedIfNeeded(_ node: MarkdownMathNode) -> String {
        switch node {
        case .sequence:
            let text = linearize(node)
            return text.contains(" ") ? "(\(text))" : text
        default:
            return linearize(node)
        }
    }

    private func collapseSpaces(_ text: String) -> String {
        var result = ""
        var previousWasSpace = false

        for character in text {
            if character.isWhitespace {
                if !previousWasSpace {
                    result.append(" ")
                }
                previousWasSpace = true
            } else {
                result.append(character)
                previousWasSpace = false
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
