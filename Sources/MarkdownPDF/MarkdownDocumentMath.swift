import Foundation

/// Whether the formulas of a document need symbols the base fonts do not have (an integral, an infinity, a Greek letter, a relation, a sum).
///
/// With the base fonts such a symbol is spelled out as a word ("int", "infinity", "pi"), so a document with such a formula uses the bundled faces, as it
/// already does for text outside WinAnsi. A formula made only of letters, digits, fractions, roots and function names keeps the base fonts.
extension MarkdownDocument {
    var containsMathNeedingSymbols: Bool {
        blocks.contains(where: \.containsMathNeedingSymbols)
    }
}

extension MarkdownMath {
    /// True when the source has a character outside WinAnsi, or a command that is a symbol and not a layout word or a function name.
    var needsSymbolGlyphs: Bool {
        if source.unicodeScalars.contains(where: { !PDFTextEncoding.isRepresentable($0) }) {
            return true
        }
        var commands: [String] = []
        var current: String?
        for character in source {
            if let name = current {
                if character.isLetter {
                    current = name + String(character)
                    continue
                }
                commands.append(name)
                current = nil
            }
            if character == "\\" {
                current = ""
            }
        }
        if let name = current {
            commands.append(name)
        }
        return commands.contains { !$0.isEmpty && !Self.layoutAndFunctionCommands.contains($0) }
    }

    /// Commands that draw with ASCII letters and rules only: layout words and the names of functions.
    private static let layoutAndFunctionCommands: Set<String> = [
        "frac", "dfrac", "tfrac", "sqrt", "left", "right", "text", "mathrm", "mathbf", "mathit", "mathsf", "mathtt",
        "operatorname", "quad", "qquad", "over", "binom", "begin", "end", "limits", "nolimits", "displaystyle",
        "textstyle", "sin", "cos", "tan", "log", "ln", "exp", "lim", "max", "min", "det", "gcd", "sup", "inf",
    ]
}

private extension MarkdownBlock {
    var containsMathNeedingSymbols: Bool {
        switch self {
        case let .heading(_, content), let .paragraph(content):
            content.contains(where: \.containsMathNeedingSymbols)
        case let .blockQuote(blocks), let .footnoteDefinition(_, blocks):
            blocks.contains(where: \.containsMathNeedingSymbols)
        case let .unorderedList(items), let .orderedList(_, items):
            items.contains { $0.blocks.contains(where: \.containsMathNeedingSymbols) }
        case let .displayMath(math):
            math.needsSymbolGlyphs
        case let .table(table):
            (table.headers + table.rows.flatMap(\.self)).contains { $0.contains(where: \.containsMathNeedingSymbols) }
        case .codeBlock, .html, .thematicBreak, .pageBreak:
            false
        }
    }
}

private extension MarkdownInline {
    var containsMathNeedingSymbols: Bool {
        switch self {
        case let .inlineMath(math):
            math.needsSymbolGlyphs
        case let .emphasis(children), let .strong(children), let .strikethrough(children):
            children.contains(where: \.containsMathNeedingSymbols)
        case let .link(children, _, _):
            children.contains(where: \.containsMathNeedingSymbols)
        case .text, .code, .image, .softBreak, .lineBreak, .footnoteReference, .indexMarker:
            false
        }
    }
}
