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
    @inline(never)
    func standardPieces(of run: PDFTextRun, fontSet: PDFOptions.FontSet) throws -> [Piece]? {
        guard entry(for: run.font) == nil, run.inlineMathBox == nil, let sans = entry(for: .helvetica) else { return nil }
        let hasEmoji = colorEmoji != nil && EmojiSegmenter.containsColorEmoji(run.text)
        let needsFace = run.text.unicodeScalars.contains { Self.drawsFromFace($0, sans: sans) }
        // a bare text-default emoji that no text face has is drawn from the colour face too
        let hasBare = colorEmoji != nil && run.text.unicodeScalars.contains { bareEmojiNeedsColourFace($0, own: sans) }
        guard hasEmoji || needsFace || hasBare else { return nil }
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
                guard hasBare else {
                    pending += text
                    continue
                }
                for scalar in text.unicodeScalars {
                    if bareEmojiNeedsColourFace(scalar, own: sans), let piece = bareEmojiPiece(scalar, size: run.size) {
                        try flushText()
                        pieces.append(piece)
                        changedAny = true
                    } else {
                        pending.unicodeScalars.append(scalar)
                    }
                }
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

    /// The width of a run whose own font is not embedded: the sum of the pieces ``standardPieces(of:fontSet:)`` makes of it, or the base-14 width when it
    /// makes none. Out of line, with nothing but the call in the caller: ``width(of:fallbackFontSet:)`` is called at the bottom of every deep block
    /// nesting, and a local of the size of a run in its frame is enough to overflow the stack of a test thread at a hundred levels of list (MEASURED:
    /// `deepListIndentIsClamped` crashed with signal 10 when the call was written `try x(run) ?? run.width(...)`).
    @inline(never)
    func widthWithoutEmbeddedFace(of run: PDFTextRun, fontSet: PDFOptions.FontSet) throws -> Double {
        guard mayBeSplitWithoutEmbeddedFace(run) else { return run.width(fontSet: fontSet) }
        return try splitWidth(of: run, fontSet: fontSet)
    }

    /// The cheap test that comes first, with no local of any size: a text face is embedded and the run holds a character beyond ASCII. Anything else is
    /// drawn and measured by the base-14 font as before. Its frame, and the frame of the caller, must stay small: the frame of the function that does
    /// the work holds the pieces, and that is too much to put on the stack below a deep nesting that is already close to the limit.
    @inline(never)
    func mayBeSplitWithoutEmbeddedFace(_ run: PDFTextRun) -> Bool {
        hasEntry(for: .helvetica) && run.text.utf8.contains { $0 >= 0x80 }
    }

    @inline(never)
    private func splitWidth(of run: PDFTextRun, fontSet: PDFOptions.FontSet) throws -> Double {
        if let pieces = try standardPieces(of: run, fontSet: fontSet) {
            return pieces.reduce(0) { $0 + $1.advance }
        }
        return run.width(fontSet: fontSet)
    }

    /// True for a character the base-14 font cannot hold (WinAnsi) and the embedded proportional face can draw. The invisible format controls (a
    /// variation selector, a joiner) are not: the base-14 path removes them, as before.
    private static func drawsFromFace(_ scalar: UnicodeScalar, sans: Entry) -> Bool {
        guard scalar.value > 0x7F, !PDFTextEncoding.isRepresentable(scalar), !PDFTextEncoding.isInvisibleFormatControl(scalar) else { return false }
        return (try? sans.mapper.map(text: String(scalar), fontSize: 1)) != nil
    }
}
