import Foundation

extension PDFEmbeddedFontCatalog {
    /// The pieces of a run whose OWN font is not embedded (the monospaced role of a document that embeds the text faces only, so the code is written with
    /// the base-14 font), or nil when the run is drawn as one. The base-14 font holds WinAnsi, and it used to fold every other character to an ASCII
    /// stand-in letter (the check mark and the down arrow to `v`, the package emoji to `?`) although the proportional face and the colour emoji face of the
    /// document were there to draw them. Now:
    ///
    /// - an emoji the colour face can draw is drawn from it;
    /// - a character WinAnsi cannot hold and the embedded proportional face has is drawn from that face;
    /// - everything else stays in the base-14 font as before, a character no face has too (its stand-in, a fault to see).
    ///
    /// Width and drawing both go through this, so they cannot disagree. With no embedded proportional face the run is not split (a document that embeds
    /// nothing is drawn exactly as before, and the colour emoji face is not used for it).
    func standardPieces(of run: PDFTextRun, fontSet: PDFOptions.FontSet) throws -> [Piece]? {
        guard entry(for: run.font) == nil, run.inlineMathBox == nil, let sans = entry(for: .helvetica) else { return nil }
        let hasEmoji = colorEmoji != nil && EmojiSegmenter.containsColorEmoji(run.text)
        let needsFace = run.text.unicodeScalars.contains { Self.drawsFromFace($0, sans: sans) }
        guard hasEmoji || needsFace else { return nil }
        var pieces: [Piece] = []
        var pending = ""
        var changedAny = false
        func flushText() throws {
            guard !pending.isEmpty else { return }
            var stretches: [(text: String, fromFace: Bool)] = []
            for scalar in pending.unicodeScalars {
                let fromFace = Self.drawsFromFace(scalar, sans: sans)
                if let last = stretches.last, last.fromFace == fromFace {
                    stretches[stretches.count - 1].text.unicodeScalars.append(scalar)
                } else {
                    stretches.append((String(scalar), fromFace))
                }
            }
            for stretch in stretches {
                var piece = run
                piece.text = stretch.text
                if stretch.fromFace {
                    piece.font = .helvetica
                    try pieces.append(.text(run: piece, mapping: shapedMapping(for: piece, entry: sans)))
                    changedAny = true
                } else {
                    pieces.append(.standard(run: piece, advance: piece.width(fontSet: fontSet)))
                }
            }
            pending = ""
        }
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
                    changedAny = true
                } else {
                    pending += cluster.text
                }
            }
        }
        try flushText()
        return changedAny ? pieces : nil
    }

    /// True for a character the base-14 font cannot hold (WinAnsi) and the embedded proportional face can draw. The invisible format controls (a
    /// variation selector, a joiner) are not: the base-14 path removes them, as before.
    private static func drawsFromFace(_ scalar: UnicodeScalar, sans: Entry) -> Bool {
        guard scalar.value > 0x7F, !PDFTextEncoding.isRepresentable(scalar), !PDFTextEncoding.isInvisibleFormatControl(scalar) else { return false }
        return (try? sans.mapper.map(text: String(scalar), fontSize: 1)) != nil
    }
}
