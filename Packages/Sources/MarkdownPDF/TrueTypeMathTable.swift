import Foundation

struct TrueTypeMathTable: Equatable {
    struct MathValueRecord: Equatable {
        var value: Int16
        var deviceOffset: UInt16
    }

    struct Constants: Equatable {
        enum ValueName: String, CaseIterable {
            case mathLeading
            case axisHeight
            case accentBaseHeight
            case flattenedAccentBaseHeight
            case subscriptShiftDown
            case subscriptTopMax
            case subscriptBaselineDropMin
            case superscriptShiftUp
            case superscriptShiftUpCramped
            case superscriptBottomMin
            case superscriptBaselineDropMax
            case subSuperscriptGapMin
            case superscriptBottomMaxWithSubscript
            case spaceAfterScript
            case upperLimitGapMin
            case upperLimitBaselineRiseMin
            case lowerLimitGapMin
            case lowerLimitBaselineDropMin
            case stackTopShiftUp
            case stackTopDisplayStyleShiftUp
            case stackBottomShiftDown
            case stackBottomDisplayStyleShiftDown
            case stackGapMin
            case stackDisplayStyleGapMin
            case stretchStackTopShiftUp
            case stretchStackBottomShiftDown
            case stretchStackGapAboveMin
            case stretchStackGapBelowMin
            case fractionNumeratorShiftUp
            case fractionNumeratorDisplayStyleShiftUp
            case fractionDenominatorShiftDown
            case fractionDenominatorDisplayStyleShiftDown
            case fractionNumeratorGapMin
            case fractionNumDisplayStyleGapMin
            case fractionRuleThickness
            case fractionDenominatorGapMin
            case fractionDenomDisplayStyleGapMin
            case skewedFractionHorizontalGap
            case skewedFractionVerticalGap
            case overbarVerticalGap
            case overbarRuleThickness
            case overbarExtraAscender
            case underbarVerticalGap
            case underbarRuleThickness
            case underbarExtraDescender
            case radicalVerticalGap
            case radicalDisplayStyleVerticalGap
            case radicalRuleThickness
            case radicalExtraAscender
            case radicalKernBeforeDegree
            case radicalKernAfterDegree
        }

        var scriptPercentScaleDown: Int16
        var scriptScriptPercentScaleDown: Int16
        var delimitedSubFormulaMinHeight: UInt16
        var displayOperatorMinHeight: UInt16
        var values: [ValueName: MathValueRecord]
        var radicalDegreeBottomRaisePercent: Int16

        func value(_ name: ValueName) -> MathValueRecord? {
            values[name]
        }
    }

    struct GlyphValueRecord: Equatable {
        var glyphID: UInt16
        var value: MathValueRecord
    }

    struct GlyphInfo: Equatable {
        var italicsCorrections: [GlyphValueRecord]
        var topAccentAttachments: [GlyphValueRecord]
        var extendedShapeGlyphIDs: [UInt16]
        var mathKerns: [MathKernRecord]
    }

    struct MathKernRecord: Equatable {
        var glyphID: UInt16
        var topRight: MathKern?
        var topLeft: MathKern?
        var bottomRight: MathKern?
        var bottomLeft: MathKern?
    }

    struct MathKern: Equatable {
        var correctionHeights: [MathValueRecord]
        var kernValues: [MathValueRecord]
    }

    struct Variants: Equatable {
        var minConnectorOverlap: UInt16
        var verticalConstructions: [GlyphConstruction]
        var horizontalConstructions: [GlyphConstruction]
    }

    struct GlyphConstruction: Equatable {
        var glyphID: UInt16
        var assembly: GlyphAssembly?
        var variants: [GlyphVariant]
    }

    struct GlyphVariant: Equatable {
        var glyphID: UInt16
        var advanceMeasurement: UInt16
    }

    struct GlyphAssembly: Equatable {
        var italicsCorrection: MathValueRecord
        var parts: [GlyphPart]
    }

    struct GlyphPart: Equatable {
        var glyphID: UInt16
        var startConnectorLength: UInt16
        var endConnectorLength: UInt16
        var fullAdvance: UInt16
        var partFlags: UInt16

        var isExtender: Bool {
            partFlags & 0x0001 != 0
        }
    }

    var majorVersion: UInt16
    var minorVersion: UInt16
    var constants: Constants
    var glyphInfo: GlyphInfo
    var variants: Variants
}
