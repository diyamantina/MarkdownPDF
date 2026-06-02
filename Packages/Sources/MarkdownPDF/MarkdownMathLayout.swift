import Foundation

struct MarkdownMathLayout {
    var font: StandardFont
    var color: PDFColor
    var measureText: (PDFTextRun) throws -> Double

    func layout(
        _ node: MarkdownMathNode,
        size: Double,
        displayStyle: Bool,
    ) throws -> MarkdownMathLayoutBox {
        switch node {
        case let .sequence(children):
            try layoutSequence(children, size: size, displayStyle: displayStyle)
        case let .text(text):
            try layoutText(text, size: size)
        case let .symbol(display, _, _):
            try layoutText(display, size: size)
        case let .fraction(numerator, denominator):
            try layoutFraction(numerator: numerator, denominator: denominator, size: size)
        case let .radical(radicand):
            try layoutRadical(radicand, size: size, displayStyle: displayStyle)
        case let .scripts(base, subscriptNode, superscriptNode):
            try layoutScripts(
                base: base,
                subscriptNode: subscriptNode,
                superscriptNode: superscriptNode,
                size: size,
                displayStyle: displayStyle,
            )
        }
    }

    private func layoutSequence(
        _ children: [MarkdownMathNode],
        size: Double,
        displayStyle: Bool,
    ) throws -> MarkdownMathLayoutBox {
        var cursor = 0.0
        var elements: [MarkdownMathLayoutElement] = []
        var height = 0.0
        var depth = 0.0

        for child in children {
            let box = try layout(child, size: size, displayStyle: displayStyle)
            elements += box.elements.map { $0.offsetBy(x: cursor, y: 0) }
            cursor += box.width
            height = max(height, box.height)
            depth = max(depth, box.depth)
        }

        return MarkdownMathLayoutBox(width: cursor, height: height, depth: depth, elements: elements)
    }

    private func layoutText(_ text: String, size: Double) throws -> MarkdownMathLayoutBox {
        guard !text.isEmpty else {
            return MarkdownMathLayoutBox(width: 0, height: 0, depth: 0, elements: [])
        }

        let run = PDFTextRun(text: text, font: font, size: size, color: color)
        return try MarkdownMathLayoutBox(
            width: measureText(run),
            height: size * 0.72,
            depth: size * 0.22,
            elements: [.text(run: run, x: 0, y: 0)],
        )
    }

    private func layoutFraction(
        numerator: MarkdownMathNode,
        denominator: MarkdownMathNode,
        size: Double,
    ) throws -> MarkdownMathLayoutBox {
        let childSize = size * 0.82
        let numeratorBox = try layout(numerator, size: childSize, displayStyle: false)
        let denominatorBox = try layout(denominator, size: childSize, displayStyle: false)
        let padding = size * 0.22
        let gap = size * 0.24
        let ruleThickness = max(0.45, size * 0.045)
        let width = max(numeratorBox.width, denominatorBox.width) + padding * 2
        let numeratorBaseline = ruleThickness / 2 + gap + numeratorBox.depth
        let denominatorBaseline = -ruleThickness / 2 - gap - denominatorBox.height
        let numeratorX = (width - numeratorBox.width) / 2
        let denominatorX = (width - denominatorBox.width) / 2

        var elements: [MarkdownMathLayoutElement] = [
            .rule(x: 0, y: -ruleThickness / 2, width: width, height: ruleThickness, color: color),
        ]
        elements += numeratorBox.elements.map { $0.offsetBy(x: numeratorX, y: numeratorBaseline) }
        elements += denominatorBox.elements.map { $0.offsetBy(x: denominatorX, y: denominatorBaseline) }

        return MarkdownMathLayoutBox(
            width: width,
            height: numeratorBaseline + numeratorBox.height,
            depth: abs(denominatorBaseline) + denominatorBox.depth,
            elements: elements,
        )
    }

    private func layoutRadical(
        _ radicand: MarkdownMathNode,
        size: Double,
        displayStyle: Bool,
    ) throws -> MarkdownMathLayoutBox {
        let radical = try layoutText("sqrt", size: size * 0.82)
        let radicandBox = try layout(radicand, size: size * 0.95, displayStyle: displayStyle)
        let gap = size * 0.2
        let ruleThickness = max(0.45, size * 0.045)
        let radicandX = radical.width + gap
        let overbarY = radicandBox.height + size * 0.08

        var elements = radical.elements
        elements += radicandBox.elements.map { $0.offsetBy(x: radicandX, y: 0) }
        elements.append(.rule(
            x: radicandX,
            y: overbarY,
            width: radicandBox.width,
            height: ruleThickness,
            color: color,
        ))

        return MarkdownMathLayoutBox(
            width: radical.width + gap + radicandBox.width,
            height: max(radical.height, overbarY + ruleThickness),
            depth: max(radical.depth, radicandBox.depth),
            elements: elements,
        )
    }

    private func layoutScripts(
        base: MarkdownMathNode,
        subscriptNode: MarkdownMathNode?,
        superscriptNode: MarkdownMathNode?,
        size: Double,
        displayStyle: Bool,
    ) throws -> MarkdownMathLayoutBox {
        if displayStyle, base.isBigOperator {
            return try layoutLimits(
                base: base,
                lower: subscriptNode,
                upper: superscriptNode,
                size: size,
            )
        }

        let baseBox = try layout(base, size: size, displayStyle: displayStyle)
        let scriptSize = size * 0.68
        let subscriptBox = try subscriptNode.map { try layout($0, size: scriptSize, displayStyle: false) }
        let superscriptBox = try superscriptNode.map { try layout($0, size: scriptSize, displayStyle: false) }
        let scriptGap = size * 0.08
        let scriptX = baseBox.width + scriptGap
        let superscriptY = baseBox.height * 0.58
        let subscriptY = -baseBox.depth - scriptSize * 0.28

        var elements = baseBox.elements
        var scriptWidth = 0.0
        var height = baseBox.height
        var depth = baseBox.depth

        if let superscriptBox {
            elements += superscriptBox.elements.map { $0.offsetBy(x: scriptX, y: superscriptY) }
            scriptWidth = max(scriptWidth, superscriptBox.width)
            height = max(height, superscriptY + superscriptBox.height)
        }

        if let subscriptBox {
            elements += subscriptBox.elements.map { $0.offsetBy(x: scriptX, y: subscriptY) }
            scriptWidth = max(scriptWidth, subscriptBox.width)
            depth = max(depth, abs(subscriptY) + subscriptBox.depth)
        }

        return MarkdownMathLayoutBox(
            width: baseBox.width + scriptGap + scriptWidth,
            height: height,
            depth: depth,
            elements: elements,
        )
    }

    private func layoutLimits(
        base: MarkdownMathNode,
        lower: MarkdownMathNode?,
        upper: MarkdownMathNode?,
        size: Double,
    ) throws -> MarkdownMathLayoutBox {
        let baseBox = try layout(base, size: size * 1.15, displayStyle: false)
        let scriptSize = size * 0.68
        let lowerBox = try lower.map { try layout($0, size: scriptSize, displayStyle: false) }
        let upperBox = try upper.map { try layout($0, size: scriptSize, displayStyle: false) }
        let gap = size * 0.16
        let width = max(baseBox.width, lowerBox?.width ?? 0, upperBox?.width ?? 0)
        let baseX = (width - baseBox.width) / 2

        var elements = baseBox.elements.map { $0.offsetBy(x: baseX, y: 0) }
        var height = baseBox.height
        var depth = baseBox.depth

        if let upperBox {
            let upperY = baseBox.height + gap + upperBox.depth
            elements += upperBox.elements.map { $0.offsetBy(x: (width - upperBox.width) / 2, y: upperY) }
            height = upperY + upperBox.height
        }

        if let lowerBox {
            let lowerY = -baseBox.depth - gap - lowerBox.height
            elements += lowerBox.elements.map { $0.offsetBy(x: (width - lowerBox.width) / 2, y: lowerY) }
            depth = abs(lowerY) + lowerBox.depth
        }

        return MarkdownMathLayoutBox(width: width, height: height, depth: depth, elements: elements)
    }
}

private extension MarkdownMathNode {
    var isBigOperator: Bool {
        if case let .symbol(_, _, isBigOperator) = self {
            return isBigOperator
        }
        return false
    }
}
