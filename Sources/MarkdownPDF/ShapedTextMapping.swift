import Foundation

struct ShapedTextMapping: Equatable {
    enum ValidationError: Swift.Error, Equatable, LocalizedError {
        case sourceGlyphCountMismatch(sourceScalarCount: Int, glyphCount: Int)
        case invalidSourceRange(lowerBound: Int, upperBound: Int, sourceScalarCount: Int)
        case discontiguousSourceRange(expectedLowerBound: Int, actualLowerBound: Int)
        case incompleteSourceCoverage(lastUpperBound: Int, sourceScalarCount: Int)
        case emptyNormalizedText(sourceRange: Range<Int>)
        case emptyToUnicodeSequence(sourceRange: Range<Int>)
        case toUnicodeSequenceMismatch(sourceRange: Range<Int>, expected: String, actual: String)
        case emptyGlyphs(sourceRange: Range<Int>)
        case invalidGlyphAdvance(sourceRange: Range<Int>, glyphID: UInt16, advance: Double)
        case invalidGlyphOffset(sourceRange: Range<Int>, glyphID: UInt16, x: Double, y: Double)

        var errorDescription: String? {
            switch self {
            case let .sourceGlyphCountMismatch(sourceScalarCount, glyphCount):
                "Cannot create one-to-one shaped text from \(sourceScalarCount) source scalars and \(glyphCount) glyphs."
            case let .invalidSourceRange(lowerBound, upperBound, sourceScalarCount):
                "Shaped cluster source range \(lowerBound)..<\(upperBound) is outside the \(sourceScalarCount) source scalars."
            case let .discontiguousSourceRange(expectedLowerBound, actualLowerBound):
                "Shaped cluster source range starts at \(actualLowerBound) instead of \(expectedLowerBound)."
            case let .incompleteSourceCoverage(lastUpperBound, sourceScalarCount):
                "Shaped clusters cover \(lastUpperBound) of \(sourceScalarCount) source scalars."
            case let .emptyNormalizedText(sourceRange):
                "Shaped cluster \(sourceRange) has empty normalized text."
            case let .emptyToUnicodeSequence(sourceRange):
                "Shaped cluster \(sourceRange) has no ToUnicode scalar sequence."
            case let .toUnicodeSequenceMismatch(sourceRange, expected, actual):
                "Shaped cluster \(sourceRange) maps ToUnicode text \(actual) instead of source text \(expected)."
            case let .emptyGlyphs(sourceRange):
                "Shaped cluster \(sourceRange) emits no glyphs."
            case let .invalidGlyphAdvance(sourceRange, glyphID, advance):
                "Shaped cluster \(sourceRange) glyph \(glyphID) has invalid advance \(advance)."
            case let .invalidGlyphOffset(sourceRange, glyphID, x, y):
                "Shaped cluster \(sourceRange) glyph \(glyphID) has invalid offset (\(x), \(y))."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .sourceGlyphCountMismatch:
                "Create explicit clusters when shaping does not preserve a one glyph per scalar relationship."
            case .invalidSourceRange, .discontiguousSourceRange, .incompleteSourceCoverage:
                "Use contiguous source scalar ranges that cover the original source text exactly once."
            case .emptyNormalizedText:
                "Store the normalized cluster text that was used for shaping."
            case .emptyToUnicodeSequence:
                "Keep the source-faithful Unicode scalar sequence needed for extraction."
            case .toUnicodeSequenceMismatch:
                "Use the exact source scalars covered by the cluster as the ToUnicode sequence."
            case .emptyGlyphs:
                "Keep unsupported inputs out of PDF emission until a visible fallback or typed error policy is chosen."
            case .invalidGlyphAdvance:
                "Only store finite, non-negative glyph advances in the shaped text model."
            case .invalidGlyphOffset:
                "Only store finite glyph positioning offsets in the shaped text model."
            }
        }
    }

    struct Cluster: Equatable {
        var sourceScalarRange: Range<Int>
        var normalizedText: String
        var glyphs: [Glyph]
        var toUnicodeScalars: [UnicodeScalar]

        var pdfCharacterCodes: [UInt16] {
            glyphs.map(\.pdfCharacterCode)
        }

        var advance: Double {
            glyphs.reduce(0) { $0 + $1.advance }
        }

        var toUnicodeText: String {
            String(String.UnicodeScalarView(toUnicodeScalars))
        }
    }

    struct Glyph: Equatable {
        var glyphID: UInt16
        var cid: UInt16
        var pdfCharacterCode: UInt16
        var advanceWidth: UInt16
        var advance: Double
        var offset: Offset
        var cmapScalar: UnicodeScalar?

        init(
            glyphID: UInt16,
            cid: UInt16,
            pdfCharacterCode: UInt16,
            advanceWidth: UInt16,
            advance: Double,
            offset: Offset = .zero,
            cmapScalar: UnicodeScalar? = nil,
        ) {
            self.glyphID = glyphID
            self.cid = cid
            self.pdfCharacterCode = pdfCharacterCode
            self.advanceWidth = advanceWidth
            self.advance = advance
            self.offset = offset
            self.cmapScalar = cmapScalar
        }

        init(
            _ glyph: TrueTypeGlyphMapper.Glyph,
            offset: Offset = .zero,
            cmapScalar: UnicodeScalar? = nil,
        ) {
            self.init(
                glyphID: glyph.glyphID,
                cid: glyph.cid,
                pdfCharacterCode: glyph.pdfCharacterCode,
                advanceWidth: glyph.advanceWidth,
                advance: glyph.width,
                offset: offset,
                cmapScalar: cmapScalar,
            )
        }
    }

    struct Offset: Equatable {
        var x: Double
        var y: Double

        static let zero = Offset(x: 0, y: 0)
    }

    var sourceText: String
    var clusters: [Cluster]

    init(sourceText: String, clusters: [Cluster]) throws {
        try Self.validate(sourceText: sourceText, clusters: clusters)
        self.sourceText = sourceText
        self.clusters = clusters
    }

    var sourceScalarCount: Int {
        sourceText.unicodeScalars.count
    }

    var glyphs: [Glyph] {
        clusters.flatMap(\.glyphs)
    }

    var totalAdvance: Double {
        clusters.reduce(0) { $0 + $1.advance }
    }

    var toUnicodeText: String {
        clusters.map(\.toUnicodeText).joined()
    }

    static func oneGlyphPerScalar(
        sourceText: String,
        glyphs: [TrueTypeGlyphMapper.Glyph],
    ) throws -> ShapedTextMapping {
        let scalars = Array(sourceText.unicodeScalars)
        guard scalars.count == glyphs.count else {
            throw ValidationError.sourceGlyphCountMismatch(
                sourceScalarCount: scalars.count,
                glyphCount: glyphs.count,
            )
        }

        let clusters = scalars.indices.map { index in
            Cluster(
                sourceScalarRange: index ..< index + 1,
                normalizedText: String(scalars[index]),
                glyphs: [Glyph(glyphs[index])],
                toUnicodeScalars: [scalars[index]],
            )
        }
        return try ShapedTextMapping(sourceText: sourceText, clusters: clusters)
    }

    private static func validate(sourceText: String, clusters: [Cluster]) throws {
        let sourceScalars = Array(sourceText.unicodeScalars)
        let sourceScalarCount = sourceScalars.count
        var previousUpperBound = 0
        for cluster in clusters {
            try validateSourceRange(cluster.sourceScalarRange, sourceScalarCount: sourceScalarCount)
            guard cluster.sourceScalarRange.lowerBound == previousUpperBound else {
                throw ValidationError.discontiguousSourceRange(
                    expectedLowerBound: previousUpperBound,
                    actualLowerBound: cluster.sourceScalarRange.lowerBound,
                )
            }
            previousUpperBound = cluster.sourceScalarRange.upperBound
            try validatePayload(cluster, sourceScalars: sourceScalars)
        }
        guard previousUpperBound == sourceScalarCount else {
            throw ValidationError.incompleteSourceCoverage(
                lastUpperBound: previousUpperBound,
                sourceScalarCount: sourceScalarCount,
            )
        }
    }

    private static func validateSourceRange(_ range: Range<Int>, sourceScalarCount: Int) throws {
        guard range.lowerBound >= 0,
              range.lowerBound < range.upperBound,
              range.upperBound <= sourceScalarCount
        else {
            throw ValidationError.invalidSourceRange(
                lowerBound: range.lowerBound,
                upperBound: range.upperBound,
                sourceScalarCount: sourceScalarCount,
            )
        }
    }

    private static func validatePayload(_ cluster: Cluster, sourceScalars: [UnicodeScalar]) throws {
        guard !cluster.normalizedText.isEmpty else {
            throw ValidationError.emptyNormalizedText(sourceRange: cluster.sourceScalarRange)
        }
        guard !cluster.toUnicodeScalars.isEmpty else {
            throw ValidationError.emptyToUnicodeSequence(sourceRange: cluster.sourceScalarRange)
        }
        guard !cluster.glyphs.isEmpty else {
            throw ValidationError.emptyGlyphs(sourceRange: cluster.sourceScalarRange)
        }
        let expectedToUnicodeScalars = Array(sourceScalars[cluster.sourceScalarRange])
        guard cluster.toUnicodeScalars == expectedToUnicodeScalars else {
            throw ValidationError.toUnicodeSequenceMismatch(
                sourceRange: cluster.sourceScalarRange,
                expected: unicodeText(expectedToUnicodeScalars),
                actual: unicodeText(cluster.toUnicodeScalars),
            )
        }
        for glyph in cluster.glyphs {
            guard glyph.advance.isFinite, glyph.advance >= 0 else {
                throw ValidationError.invalidGlyphAdvance(
                    sourceRange: cluster.sourceScalarRange,
                    glyphID: glyph.glyphID,
                    advance: glyph.advance,
                )
            }
            guard glyph.offset.x.isFinite, glyph.offset.y.isFinite else {
                throw ValidationError.invalidGlyphOffset(
                    sourceRange: cluster.sourceScalarRange,
                    glyphID: glyph.glyphID,
                    x: glyph.offset.x,
                    y: glyph.offset.y,
                )
            }
        }
    }

    private static func unicodeText(_ scalars: [UnicodeScalar]) -> String {
        String(String.UnicodeScalarView(scalars))
    }
}

extension TrueTypeGlyphMapper.TextMapping {
    func shapedText() throws -> ShapedTextMapping {
        try ShapedTextMapping.oneGlyphPerScalar(sourceText: sourceText, glyphs: glyphs)
    }
}
