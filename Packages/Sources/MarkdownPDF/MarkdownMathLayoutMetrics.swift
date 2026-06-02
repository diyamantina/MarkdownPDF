import Foundation

struct MarkdownMathLayoutMetrics: Equatable {
    static let `default` = MarkdownMathLayoutMetrics()

    private var unitsPerEm: Double?
    private var constants: TrueTypeMathTable.Constants?

    static func openType(
        constants: TrueTypeMathTable.Constants,
        unitsPerEm: UInt16,
    ) -> MarkdownMathLayoutMetrics {
        guard unitsPerEm > 0 else {
            return .default
        }

        return MarkdownMathLayoutMetrics(
            unitsPerEm: Double(unitsPerEm),
            constants: constants,
        )
    }

    func textHeight(size: Double) -> Double {
        size * 0.72
    }

    func textDepth(size: Double) -> Double {
        size * 0.22
    }

    func fractionChildSize(size: Double) -> Double {
        size * 0.82
    }

    func fractionPadding(size: Double) -> Double {
        size * 0.22
    }

    func fractionNumeratorGap(size: Double, displayStyle: Bool) -> Double {
        let name: TrueTypeMathTable.Constants.ValueName = displayStyle
            ? .fractionNumDisplayStyleGapMin
            : .fractionNumeratorGapMin
        return scaledConstant(name, size: size) ?? size * 0.24
    }

    func fractionDenominatorGap(size: Double, displayStyle: Bool) -> Double {
        let name: TrueTypeMathTable.Constants.ValueName = displayStyle
            ? .fractionDenomDisplayStyleGapMin
            : .fractionDenominatorGapMin
        return scaledConstant(name, size: size) ?? size * 0.24
    }

    func fractionRuleThickness(size: Double) -> Double {
        scaledConstant(.fractionRuleThickness, size: size) ?? defaultRuleThickness(size: size)
    }

    func radicalSignSize(size: Double) -> Double {
        size * 0.82
    }

    func radicalRadicandSize(size: Double) -> Double {
        size * 0.95
    }

    func radicalHorizontalGap(size: Double) -> Double {
        size * 0.2
    }

    func radicalVerticalGap(size: Double, displayStyle: Bool) -> Double {
        let name: TrueTypeMathTable.Constants.ValueName = displayStyle
            ? .radicalDisplayStyleVerticalGap
            : .radicalVerticalGap
        return scaledConstant(name, size: size) ?? size * 0.08
    }

    func radicalRuleThickness(size: Double) -> Double {
        scaledConstant(.radicalRuleThickness, size: size) ?? defaultRuleThickness(size: size)
    }

    func radicalExtraAscender(size: Double) -> Double {
        scaledConstant(.radicalExtraAscender, size: size) ?? 0
    }

    func scriptSize(size: Double) -> Double {
        guard let constants, constants.scriptPercentScaleDown > 0 else {
            return size * 0.68
        }

        return size * Double(constants.scriptPercentScaleDown) / 100
    }

    func spaceAfterScript(size: Double) -> Double {
        scaledConstant(.spaceAfterScript, size: size) ?? size * 0.08
    }

    func superscriptShiftUp(size: Double, baseBox: MarkdownMathLayoutBox) -> Double {
        scaledConstant(.superscriptShiftUp, size: size) ?? baseBox.height * 0.58
    }

    func subscriptShiftDown(size: Double, baseBox: MarkdownMathLayoutBox, scriptSize: Double) -> Double {
        scaledConstant(.subscriptShiftDown, size: size) ?? baseBox.depth + scriptSize * 0.28
    }

    func displayOperatorSize(size: Double) -> Double {
        guard let constants, constants.displayOperatorMinHeight > 0, let unitsPerEm else {
            return size * 1.15
        }

        let minimumHeight = Double(constants.displayOperatorMinHeight) * size / unitsPerEm
        return max(size * 1.15, minimumHeight / 0.72)
    }

    func upperLimitGap(size: Double) -> Double {
        scaledConstant(.upperLimitGapMin, size: size) ?? size * 0.16
    }

    func lowerLimitGap(size: Double) -> Double {
        scaledConstant(.lowerLimitGapMin, size: size) ?? size * 0.16
    }

    func axisHeight(size: Double) -> Double {
        scaledConstant(.axisHeight, size: size) ?? 0
    }

    private func scaledConstant(_ name: TrueTypeMathTable.Constants.ValueName, size: Double) -> Double? {
        guard let constants,
              let unitsPerEm,
              let value = constants.value(name)?.value,
              value > 0
        else {
            return nil
        }

        return Double(value) * size / unitsPerEm
    }

    private func defaultRuleThickness(size: Double) -> Double {
        max(0.45, size * 0.045)
    }
}
