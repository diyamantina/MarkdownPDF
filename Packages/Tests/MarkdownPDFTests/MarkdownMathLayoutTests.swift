@testable import MarkdownPDF
import Testing

@Suite("Markdown math layout")
struct MarkdownMathLayoutTests {
    @Test("Default metrics preserve fraction geometry")
    func defaultMetricsPreserveFractionGeometry() throws {
        let box = try makeLayout().layout(
            .fraction(numerator: .text("a"), denominator: .text("b")),
            size: 10,
            displayStyle: false,
        )

        let rule = try #require(box.ruleElements.first)
        let numerator = try #require(box.textElement(containing: "a"))
        let denominator = try #require(box.textElement(containing: "b"))

        #expect(abs(rule.y + 0.225) < 0.0001)
        #expect(abs(rule.height - 0.45) < 0.0001)
        #expect(abs(rule.width - 9.32) < 0.0001)
        #expect(abs(numerator.y - 4.429) < 0.0001)
        #expect(abs(denominator.y + 8.529) < 0.0001)
        #expect(abs(box.height - 10.333) < 0.0001)
        #expect(abs(box.depth - 10.333) < 0.0001)
    }

    @Test("Default metrics preserve script radical and limit geometry")
    func defaultMetricsPreserveScriptRadicalAndLimitGeometry() throws {
        let layout = makeLayout()
        let scripts = try layout.layout(
            .scripts(base: .text("x"), subscript: .text("i"), superscript: .text("2")),
            size: 10,
            displayStyle: false,
        )
        let superscript = try #require(scripts.textElement(containing: "2"))
        let subscriptText = try #require(scripts.textElement(containing: "i"))

        #expect(abs(superscript.x - 6.8) < 0.0001)
        #expect(abs(superscript.y - 4.176) < 0.0001)
        #expect(abs(subscriptText.x - 6.8) < 0.0001)
        #expect(abs(subscriptText.y + 4.104) < 0.0001)
        #expect(abs(scripts.height - 9.072) < 0.0001)
        #expect(abs(scripts.depth - 5.6) < 0.0001)

        let radical = try layout.layout(
            .radical(radicand: .text("x")),
            size: 10,
            displayStyle: true,
        )
        let radicalRule = try #require(radical.ruleElements.first)

        #expect(abs(radicalRule.y - 7.64) < 0.0001)
        #expect(abs(radicalRule.height - 0.45) < 0.0001)
        #expect(abs(radical.height - 8.09) < 0.0001)

        let limits = try layout.layout(
            .scripts(
                base: .symbol(display: "sum", linearized: "sum", isBigOperator: true),
                subscript: .text("i"),
                superscript: .text("n"),
            ),
            size: 10,
            displayStyle: true,
        )
        let upper = try #require(limits.textElement(containing: "n"))
        let lower = try #require(limits.textElement(containing: "i"))

        #expect(abs(upper.y - 11.376) < 0.0001)
        #expect(abs(lower.y + 9.026) < 0.0001)
        #expect(abs(limits.height - 16.272) < 0.0001)
        #expect(abs(limits.depth - 10.522) < 0.0001)
    }

    @Test("OpenType metrics influence fraction axis and gaps")
    func openTypeMetricsInfluenceFractionAxisAndGaps() throws {
        let box = try makeLayout(metrics: .openType(constants: mathConstants(), unitsPerEm: 1000)).layout(
            .fraction(numerator: .text("a"), denominator: .text("b")),
            size: 10,
            displayStyle: true,
        )

        let rule = try #require(box.ruleElements.first)
        let numerator = try #require(box.textElement(containing: "a"))
        let denominator = try #require(box.textElement(containing: "b"))

        #expect(abs(rule.y - 1) < 0.0001)
        #expect(abs(rule.height - 1) < 0.0001)
        #expect(abs(numerator.y - 6.604) < 0.0001)
        #expect(abs(denominator.y + 7.504) < 0.0001)
        #expect(abs(box.height - 12.508) < 0.0001)
        #expect(abs(box.depth - 9.308) < 0.0001)
    }

    @Test("OpenType metrics influence script size and placement")
    func openTypeMetricsInfluenceScriptSizeAndPlacement() throws {
        let box = try makeLayout(metrics: .openType(constants: mathConstants(), unitsPerEm: 1000)).layout(
            .scripts(base: .text("x"), subscript: .text("i"), superscript: .text("2")),
            size: 10,
            displayStyle: false,
        )

        let base = try #require(box.textElement(containing: "x"))
        let subscriptText = try #require(box.textElement(containing: "i"))
        let superscript = try #require(box.textElement(containing: "2"))

        #expect(abs(base.y) < 0.0001)
        #expect(abs(superscript.x - 7) < 0.0001)
        #expect(abs(superscript.y - 5) < 0.0001)
        #expect(abs(superscript.run.size - 8) < 0.0001)
        #expect(abs(subscriptText.x - 7) < 0.0001)
        #expect(abs(subscriptText.y + 4) < 0.0001)
        #expect(abs(subscriptText.run.size - 8) < 0.0001)
        #expect(abs(box.height - 10.76) < 0.0001)
        #expect(abs(box.depth - 5.76) < 0.0001)
    }

    @Test("OpenType metrics influence radical and display limit spacing")
    func openTypeMetricsInfluenceRadicalAndDisplayLimitSpacing() throws {
        let metrics = MarkdownMathLayoutMetrics.openType(constants: mathConstants(), unitsPerEm: 1000)
        let radical = try makeLayout(metrics: metrics).layout(
            .radical(radicand: .text("x")),
            size: 10,
            displayStyle: true,
        )
        let radicalRule = try #require(radical.ruleElements.first)

        #expect(abs(radicalRule.y - 8.84) < 0.0001)
        #expect(abs(radicalRule.height - 0.8) < 0.0001)
        #expect(abs(radical.height - 10.34) < 0.0001)

        let limits = try makeLayout(metrics: metrics).layout(
            .scripts(
                base: .symbol(display: "sum", linearized: "sum", isBigOperator: true),
                subscript: .text("i"),
                superscript: .text("n"),
            ),
            size: 10,
            displayStyle: true,
        )
        let upper = try #require(limits.textElement(containing: "n"))
        let lower = try #require(limits.textElement(containing: "i"))

        #expect(abs(upper.y - 13.36) < 0.0001)
        #expect(abs(lower.y + 11.51) < 0.0001)
        #expect(abs(limits.height - 19.12) < 0.0001)
        #expect(abs(limits.depth - 13.27) < 0.0001)
    }

    private func makeLayout(metrics: MarkdownMathLayoutMetrics = .default) -> MarkdownMathLayout {
        MarkdownMathLayout(
            font: .helvetica,
            color: .black,
            measureText: { run in Double(run.text.count) * run.size * 0.6 },
            metrics: metrics,
        )
    }

    private func mathConstants() -> TrueTypeMathTable.Constants {
        var values: [TrueTypeMathTable.Constants.ValueName: TrueTypeMathTable.MathValueRecord] = [:]
        values[.axisHeight] = value(150)
        values[.fractionRuleThickness] = value(100)
        values[.fractionNumeratorGapMin] = value(210)
        values[.fractionNumDisplayStyleGapMin] = value(280)
        values[.fractionDenominatorGapMin] = value(220)
        values[.fractionDenomDisplayStyleGapMin] = value(260)
        values[.radicalVerticalGap] = value(120)
        values[.radicalDisplayStyleVerticalGap] = value(200)
        values[.radicalRuleThickness] = value(80)
        values[.radicalExtraAscender] = value(70)
        values[.spaceAfterScript] = value(100)
        values[.superscriptShiftUp] = value(500)
        values[.subscriptShiftDown] = value(400)
        values[.upperLimitGapMin] = value(260)
        values[.lowerLimitGapMin] = value(300)

        return TrueTypeMathTable.Constants(
            scriptPercentScaleDown: 80,
            scriptScriptPercentScaleDown: 60,
            delimitedSubFormulaMinHeight: 0,
            displayOperatorMinHeight: 900,
            values: values,
            radicalDegreeBottomRaisePercent: 0,
        )
    }

    private func value(_ value: Int16) -> TrueTypeMathTable.MathValueRecord {
        TrueTypeMathTable.MathValueRecord(value: value, deviceOffset: 0)
    }
}

private extension MarkdownMathLayoutBox {
    typealias RuleElement = (x: Double, y: Double, width: Double, height: Double)
    typealias TextElement = (run: PDFTextRun, x: Double, y: Double)

    var ruleElements: [RuleElement] {
        var rules: [RuleElement] = []
        for element in elements {
            if case let .rule(x, y, width, height, _) = element {
                rules.append((x: x, y: y, width: width, height: height))
            }
        }
        return rules
    }

    func textElement(containing text: String) -> TextElement? {
        for element in elements {
            if case let .text(run, x, y) = element,
               run.text.contains(text)
            {
                return (run: run, x: x, y: y)
            }
        }
        return nil
    }
}
