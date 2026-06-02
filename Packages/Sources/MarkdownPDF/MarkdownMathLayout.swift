import Foundation

struct MarkdownMathLayout {
    var font: StandardFont
    var color: PDFColor
    var measureText: (PDFTextRun) throws -> Double
    var metrics: MarkdownMathLayoutMetrics = .default

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
            try layoutFraction(
                numerator: numerator,
                denominator: denominator,
                size: size,
                displayStyle: displayStyle,
            )
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
        case let .accent(symbol, _, isOverline, base):
            try layoutAccent(
                symbol: symbol,
                isOverline: isOverline,
                base: base,
                size: size,
                displayStyle: displayStyle,
            )
        }
    }

    private func layoutAccent(
        symbol: String,
        isOverline: Bool,
        base: MarkdownMathNode,
        size: Double,
        displayStyle: Bool,
    ) throws -> MarkdownMathLayoutBox {
        let baseBox = try layout(base, size: size, displayStyle: displayStyle)
        let gap = size * 0.12
        let ruleThickness = metrics.radicalRuleThickness(size: size)
        var elements = baseBox.elements

        if isOverline {
            let ruleY = baseBox.height + gap
            elements.append(.rule(
                x: 0,
                y: ruleY,
                width: baseBox.width,
                height: ruleThickness,
                color: color,
            ))
            return MarkdownMathLayoutBox(
                width: baseBox.width,
                height: ruleY + ruleThickness,
                depth: baseBox.depth,
                elements: elements,
            )
        }

        let accentSize = size * 0.9
        let accent = try layoutText(symbol, size: accentSize)
        let accentX = max(0, (baseBox.width - accent.width) / 2)
        let accentY = baseBox.height + gap
        elements += accent.elements.map { $0.offsetBy(x: accentX, y: accentY) }
        return MarkdownMathLayoutBox(
            width: max(baseBox.width, accentX + accent.width),
            height: accentY + accent.height,
            depth: baseBox.depth,
            elements: elements,
        )
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
            height: metrics.textHeight(size: size),
            depth: metrics.textDepth(size: size),
            elements: [.text(run: run, x: 0, y: 0)],
        )
    }

    private func layoutFraction(
        numerator: MarkdownMathNode,
        denominator: MarkdownMathNode,
        size: Double,
        displayStyle: Bool,
    ) throws -> MarkdownMathLayoutBox {
        let childSize = metrics.fractionChildSize(size: size)
        let numeratorBox = try layout(numerator, size: childSize, displayStyle: false)
        let denominatorBox = try layout(denominator, size: childSize, displayStyle: false)
        let padding = metrics.fractionPadding(size: size)
        let numeratorGap = metrics.fractionNumeratorGap(size: size, displayStyle: displayStyle)
        let denominatorGap = metrics.fractionDenominatorGap(size: size, displayStyle: displayStyle)
        let ruleThickness = metrics.fractionRuleThickness(size: size)
        let axisY = metrics.axisHeight(size: size)
        let ruleY = axisY - ruleThickness / 2
        let width = max(numeratorBox.width, denominatorBox.width) + padding * 2
        let numeratorBaseline = axisY + ruleThickness / 2 + numeratorGap + numeratorBox.depth
        let denominatorBaseline = axisY - ruleThickness / 2 - denominatorGap - denominatorBox.height
        let numeratorX = (width - numeratorBox.width) / 2
        let denominatorX = (width - denominatorBox.width) / 2

        var elements: [MarkdownMathLayoutElement] = [
            .rule(x: 0, y: ruleY, width: width, height: ruleThickness, color: color),
        ]
        elements += numeratorBox.elements.map { $0.offsetBy(x: numeratorX, y: numeratorBaseline) }
        elements += denominatorBox.elements.map { $0.offsetBy(x: denominatorX, y: denominatorBaseline) }
        let ruleHeight = max(axisY + ruleThickness / 2, 0)
        let ruleDepth = max(-(axisY - ruleThickness / 2), 0)

        return MarkdownMathLayoutBox(
            width: width,
            height: max(ruleHeight, numeratorBaseline + numeratorBox.height),
            depth: max(ruleDepth, abs(denominatorBaseline) + denominatorBox.depth),
            elements: elements,
        )
    }

    private func layoutRadical(
        _ radicand: MarkdownMathNode,
        size: Double,
        displayStyle: Bool,
    ) throws -> MarkdownMathLayoutBox {
        let radical = try layoutText("sqrt", size: metrics.radicalSignSize(size: size))
        let radicandBox = try layout(radicand, size: metrics.radicalRadicandSize(size: size), displayStyle: displayStyle)
        let gap = metrics.radicalHorizontalGap(size: size)
        let verticalGap = metrics.radicalVerticalGap(size: size, displayStyle: displayStyle)
        let ruleThickness = metrics.radicalRuleThickness(size: size)
        let extraAscender = metrics.radicalExtraAscender(size: size)
        let radicandX = radical.width + gap
        let overbarY = radicandBox.height + verticalGap

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
            height: max(radical.height, overbarY + ruleThickness + extraAscender),
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
        let scriptSize = metrics.scriptSize(size: size)
        let subscriptBox = try subscriptNode.map { try layout($0, size: scriptSize, displayStyle: false) }
        let superscriptBox = try superscriptNode.map { try layout($0, size: scriptSize, displayStyle: false) }
        let scriptGap = metrics.spaceAfterScript(size: size)
        let scriptX = baseBox.width + scriptGap
        let superscriptY = metrics.superscriptShiftUp(size: size, baseBox: baseBox)
        let subscriptY = -metrics.subscriptShiftDown(size: size, baseBox: baseBox, scriptSize: scriptSize)

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
        let baseBox = try layout(base, size: metrics.displayOperatorSize(size: size), displayStyle: false)
        let scriptSize = metrics.scriptSize(size: size)
        let lowerBox = try lower.map { try layout($0, size: scriptSize, displayStyle: false) }
        let upperBox = try upper.map { try layout($0, size: scriptSize, displayStyle: false) }
        let upperGap = metrics.upperLimitGap(size: size)
        let lowerGap = metrics.lowerLimitGap(size: size)
        let width = max(baseBox.width, lowerBox?.width ?? 0, upperBox?.width ?? 0)
        let baseX = (width - baseBox.width) / 2

        var elements = baseBox.elements.map { $0.offsetBy(x: baseX, y: 0) }
        var height = baseBox.height
        var depth = baseBox.depth

        if let upperBox {
            let upperY = baseBox.height + upperGap + upperBox.depth
            elements += upperBox.elements.map { $0.offsetBy(x: (width - upperBox.width) / 2, y: upperY) }
            height = upperY + upperBox.height
        }

        if let lowerBox {
            let lowerY = -baseBox.depth - lowerGap - lowerBox.height
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
