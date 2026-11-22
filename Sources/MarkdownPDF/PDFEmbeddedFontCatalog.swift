import Foundation
import MathTypeset

struct PDFEmbeddedFontCatalog {
    struct Entry {
        var resource: PDFEmbeddedFontResource
        var mapper: TrueTypeGlyphMapper
        var shaper: OpenTypeShaper
        var arabicShaper: ArabicShaper
        var hebrewShaper: HebrewShaper
        var mathMetrics: MathLayoutMetrics?
    }

    private var entriesByFont: [StandardFont: Entry]

    /// Policy for a scalar the font's cmap cannot draw on the *rendering* path.
    /// `.useNotdef` keeps one missing glyph from aborting the whole document; the
    /// caller passes `.reject` when a conformance profile is active, because
    /// PDF/UA-1 and PDF/A-2a forbid referencing the `.notdef` glyph in content and
    /// require a Unicode mapping for every code, so drawing notdef would ship
    /// spec-violating output under a conformance claim. The strict `.reject` probe
    /// in ``covers(_:font:)`` is unaffected by this and stays strict always.
    private let renderingMissingGlyphPolicy: TrueTypeGlyphMapper.MissingGlyphPolicy

    /// Whether an emoji no face can draw is left out instead of drawn as the missing-glyph box (``PDFOptions/omitUndrawableEmoji``).
    private let omitUndrawableEmoji: Bool

    /// The colour emoji face, when the options carry one: a run that holds emoji it can draw is laid out and drawn piece by piece
    /// (``pieces(of:entry:)``), plain text through the run's own face and each emoji as coloured layers.
    let colorEmoji: ColorEmojiFont?

    init(
        fonts: PDFOptions.EmbeddedFonts,
        parseMathTables: Bool = false,
        renderingMissingGlyphPolicy: TrueTypeGlyphMapper.MissingGlyphPolicy = .useNotdef,
        omitUndrawableEmoji: Bool = false,
    ) throws {
        self.renderingMissingGlyphPolicy = renderingMissingGlyphPolicy
        self.omitUndrawableEmoji = omitUndrawableEmoji
        // With no emoji face given, the bundled colour face draws emoji.
        // Under a conformance profile (`.reject`) no colour face is used: a missing glyph is refused as before, so a conformance claim is unchanged.
        colorEmoji = renderingMissingGlyphPolicy == .reject ? nil : try fonts.emoji.map { try ColorEmojiFont(source: $0) } ?? BundledFonts.colorEmoji
        var entries: [StandardFont: Entry] = [:]
        try Self.add(fonts.regular, for: .helvetica, resourceName: "EF1", parseMathTables: parseMathTables, to: &entries)
        try Self.add(fonts.bold, for: .helveticaBold, resourceName: "EF2", parseMathTables: parseMathTables, to: &entries)
        try Self.add(
            fonts.italic,
            for: .helveticaOblique,
            resourceName: "EF3",
            parseMathTables: parseMathTables,
            to: &entries,
        )
        try Self.add(fonts.monospaced, for: .courier, resourceName: "EF4", parseMathTables: parseMathTables, to: &entries)
        try Self.add(fonts.math, for: .math, resourceName: "EF5", parseMathTables: true, to: &entries)
        entriesByFont = entries
    }

    func entry(for font: StandardFont) -> Entry? {
        entriesByFont[font]
    }

    /// Whether a face is embedded for `font`, without copying its entry.
    func hasEntry(for font: StandardFont) -> Bool {
        entriesByFont[font] != nil
    }

    /// Whether the embedded font bound to `font` can draw every scalar in `text`.
    /// Used to decide, per math symbol, between the Unicode glyph and an ASCII
    /// transliteration. A font with no embedded entry (the base-14 portable
    /// profile) covers no math glyphs, so this returns `false`.
    func covers(_ text: String, font: StandardFont) -> Bool {
        guard let entry = entry(for: font) else {
            return false
        }
        return (try? entry.mapper.map(text: text, fontSize: 1)) != nil
    }

    /// One piece of a laid-out run: plain text shaped by the run's own face, an emoji drawn from the colour face, or text the base-14 font draws (the
    /// stretches of a run whose own font is not embedded that WinAnsi can hold, next to stretches drawn from an embedded face: ``standardPieces(of:fontSet:)``).
    enum Piece {
        case text(run: PDFTextRun, mapping: ShapedTextMapping)
        case emoji(cluster: EmojiSegmenter.Cluster, drawing: ColorEmojiFont.Drawing, advance: Double)
        case standard(run: PDFTextRun, advance: Double)

        var advance: Double {
            switch self {
            case let .text(_, mapping): mapping.totalAdvance
            case let .emoji(_, _, advance): advance
            case let .standard(_, advance): advance
            }
        }
    }

    /// The pieces of a run that holds colour emoji the colour face can draw, nil when it holds none (the run is then laid out as one). Width and
    /// drawing both go through this, so they cannot disagree. An emoji the face cannot draw stays in the text around it, as before.
    func pieces(of run: PDFTextRun, entry: Entry) throws -> [Piece]? {
        let hasEmoji = colorEmoji != nil && EmojiSegmenter.containsColorEmoji(run.text)
        let fallback = fallbackFace(for: run, entry: entry)
        guard hasEmoji || fallback != nil else { return nil }
        var pieces: [Piece] = []
        var pending = ""
        var usedFallback = false
        // Plain text is laid out in stretches: each stretch in the run's own face, or in the fallback face where the run's own face lacks a character
        // and the fallback has it.
        func flushText() throws {
            guard !pending.isEmpty else { return }
            var stretches: [(text: String, usesFallback: Bool)] = []
            for scalar in pending.unicodeScalars {
                let usesFallback = fallback.map { Self.needsFallback(scalar, own: entry, fallback: $0.entry) } ?? false
                if let last = stretches.last, last.usesFallback == usesFallback {
                    stretches[stretches.count - 1].text.unicodeScalars.append(scalar)
                } else {
                    stretches.append((String(scalar), usesFallback))
                }
            }
            for stretch in stretches {
                var piece = run
                piece.text = stretch.text
                if stretch.usesFallback, let fallback {
                    piece.font = fallback.font
                    try pieces.append(.text(run: piece, mapping: shapedMapping(for: piece, entry: fallback.entry)))
                    usedFallback = true
                } else {
                    try pieces.append(.text(run: piece, mapping: shapedMapping(for: piece, entry: entry)))
                }
            }
            pending = ""
        }
        var drewAny = false
        let segments = hasEmoji ? EmojiSegmenter.segments(of: run.text) : [.text(run.text)]
        for segment in segments {
            switch segment {
            case let .text(text):
                pending += text
            case let .emoji(cluster):
                if let colorEmoji, let drawing = colorEmoji.drawing(of: cluster, fontSize: run.size),
                   let advance = colorEmoji.advance(of: cluster, fontSize: run.size)
                {
                    try flushText()
                    pieces.append(.emoji(cluster: cluster, drawing: drawing, advance: advance))
                    drewAny = true
                } else {
                    pending += cluster.text
                }
            }
        }
        try flushText()
        guard drewAny || usedFallback else { return nil }
        return pieces
    }

    /// The face a run falls back to for a character its own face lacks: the proportional text face, for the monospaced face (which has no Braille
    /// patterns, for one) and for the bold and oblique faces. Nil for the proportional face itself and for the math face, or when no text face is
    /// embedded. Only a run that holds a character the own face lacks and the fallback has gets one.
    private func fallbackFace(for run: PDFTextRun, entry: Entry) -> (font: StandardFont, entry: Entry)? {
        guard run.font != .helvetica, run.font != .math, let fallbackEntry = self.entry(for: .helvetica) else { return nil }
        let needed = run.text.unicodeScalars.contains { Self.needsFallback($0, own: entry, fallback: fallbackEntry) }
        return needed ? (.helvetica, fallbackEntry) : nil
    }

    /// A scalar the run's own face cannot draw and the fallback face can.
    private static func needsFallback(_ scalar: UnicodeScalar, own: Entry, fallback: Entry) -> Bool {
        guard scalar.value > 0x7F else { return false }
        func covered(_ entry: Entry) -> Bool {
            (try? entry.mapper.map(text: String(scalar), fontSize: 1)) != nil
        }
        return !covered(own) && covered(fallback)
    }

    func width(of run: PDFTextRun, fallbackFontSet: PDFOptions.FontSet) throws -> Double {
        guard let entry = entry(for: run.font) else {
            return try widthWithoutEmbeddedFace(of: run, fontSet: fallbackFontSet)
        }

        if let pieces = try pieces(of: run, entry: entry) {
            return pieces.reduce(0) { $0 + $1.advance }
        }
        return try shapedMapping(for: run, entry: entry).totalAdvance
    }

    /// Maps a run to glyphs for drawing under ``renderingMissingGlyphPolicy``. With
    /// `.useNotdef` a single scalar the font's cmap lacks (an emoji, a stray
    /// combining mark, a CJK glyph the subset omits) renders as that font's
    /// `.notdef` glyph for that one scalar instead of aborting the whole document
    /// with `missingGlyph`; the subset always retains glyph 0. Under a conformance
    /// profile the policy is `.reject`, so a missing glyph refuses rather than
    /// shipping non-conformant notdef content. The strict `.reject` probe stays in
    /// ``covers(_:font:)`` regardless, deciding math-symbol transliteration.
    func mapping(for run: PDFTextRun, entry: Entry) throws -> TrueTypeGlyphMapper.TextMapping {
        var mapper = entry.mapper
        mapper.missingGlyphPolicy = renderingMissingGlyphPolicy
        return try mapper.map(text: run.text, fontSize: run.size)
    }

    /// The text without the emoji the face cannot draw, and without the space that set each one apart. A bundled face has
    /// no color glyphs, so an emoji would print as an empty box (or a question mark); the words around it read as written.
    /// A missing glyph that is not an emoji (a script the face lacks) is left alone: that one is a fault to see.
    /// Under a conformance profile (`.reject`) nothing is dropped, so the missing glyph is refused as before.
    func withoutUndrawableEmoji(_ text: String, entry: Entry) -> String {
        guard omitUndrawableEmoji, renderingMissingGlyphPolicy == .useNotdef,
              text.unicodeScalars.contains(where: { $0.value > 0x7F })
        else {
            return text
        }
        func isEmojiPart(_ scalar: UnicodeScalar) -> Bool {
            (scalar.properties.isEmoji && scalar.value > 0x7F) || scalar.value == 0xFE0F || scalar.value == 0xFE0E
                || scalar.value == 0x200D || (0x1F3FB ... 0x1F3FF).contains(scalar.value)
        }
        func drawable(_ scalar: UnicodeScalar) -> Bool {
            (try? entry.mapper.map(text: String(scalar), fontSize: 1)) != nil
        }
        var output = String.UnicodeScalarView()
        var skipSpace = false
        for scalar in text.unicodeScalars {
            if isEmojiPart(scalar), !drawable(scalar) {
                skipSpace = true
                continue
            }
            if skipSpace, scalar == " ", output.isEmpty || output.last == " " || output.last == "\n" {
                skipSpace = false
                continue
            }
            skipSpace = false
            output.append(scalar)
        }
        return String(output)
    }

    func shapedMapping(for originalRun: PDFTextRun, entry: Entry) throws -> ShapedTextMapping {
        var run = originalRun
        run.text = PDFTextEncoding.strippingVariationSelectors(withoutUndrawableEmoji(originalRun.text, entry: entry))
        if OpenTypeShaper.canShapeLatinIncrement(run.text) {
            var shaper = entry.shaper
            shaper.missingGlyphPolicy = renderingMissingGlyphPolicy
            return try shaper.shape(text: run.text, fontSize: run.size)
        }
        // Cursive scripts (Arabic and the other joining scripts) resolve each
        // letter's positional form and apply the font's GSUB before mapping to
        // glyphs. This produces joined shapes and the correct (ligated) advance;
        // RTL visual ordering is the renderer's job. A font without the script's
        // GSUB features shapes to base (isolated) glyphs, i.e. no worse than the
        // unshaped path.
        if ArabicShaper.containsJoiningScript(run.text), entry.arabicShaper.canShapeArabic {
            return try entry.arabicShaper.shapedMapping(
                text: run.text,
                fontSize: run.size,
                missingGlyphPolicy: renderingMissingGlyphPolicy,
            )
        }
        if let scalar = run.text.unicodeScalars.first(where: Self.requiresExplicitShapingSupport) {
            throw PDFEmbeddedFontError.unsupportedComplexScriptScalar(scalar: scalar)
        }
        return try mapping(for: run, entry: entry).shapedText()
    }

    private static func add(
        _ source: PDFOptions.EmbeddedFontSource?,
        for font: StandardFont,
        resourceName: String,
        parseMathTables: Bool,
        to entries: inout [StandardFont: Entry],
    ) throws {
        guard let source else {
            return
        }

        let metadata = try TrueTypeFontParser().parse(
            source.data,
            parseMathTable: parseMathTables,
            faceIndex: source.faceIndex,
        )
        let resource = PDFEmbeddedFontResource(
            resourceName: resourceName,
            fontProgram: source.data,
            metadata: metadata,
            baseName: source.baseName,
        )
        entries[font] = Entry(
            resource: resource,
            mapper: TrueTypeGlyphMapper(data: source.data, metadata: metadata),
            shaper: OpenTypeShaper(data: source.data, metadata: metadata),
            arabicShaper: ArabicShaper(fontData: source.data, metadata: metadata),
            hebrewShaper: HebrewShaper(fontData: source.data, metadata: metadata),
            mathMetrics: metadata.math.map {
                MathLayoutMetrics.openType(constants: $0.constants, unitsPerEm: metadata.head.unitsPerEm)
            },
        )
    }

    private static func requiresExplicitShapingSupport(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0700 ... 0x074F, // Syriac
             0x0750 ... 0x077F, // Arabic Supplement
             0x0780 ... 0x07BF, // Thaana
             0x07C0 ... 0x07FF, // NKo
             0x08A0 ... 0x08FF, // Arabic Extended-A
             0x0900 ... 0x0D7F, // Indic script blocks used by the first roadmap fixture set.
             0x0E00 ... 0x0E7F, // Thai
             0x1780 ... 0x17FF, // Khmer
             0xFB1D ... 0xFDFF, // Hebrew and Arabic presentation forms
             0xFE70 ... 0xFEFE: // Arabic Presentation Forms-B (U+FEFF is the BOM, not a letter)
            true
        default:
            false
        }
    }
}
