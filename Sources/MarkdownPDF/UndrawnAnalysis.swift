import Foundation

/// Reads the text of a document and says which characters no embedded face draws (``MarkdownPDF/Render/Report``). It asks the questions the drawing asks, of
/// the same catalog of faces: a character beyond WinAnsi is drawn when an embedded text face is there and has its glyph, or when it is an emoji the colour
/// face draws; with no embedded text face it is written by the base-14 font, which folds it to a stand-in letter, so it is reported.
enum UndrawnAnalysis {
    /// The report of `document` drawn with the faces of `options` (already resolved: the bundled faces are in it when the document needed them).
    /// `bundledFacesAvailable` says whether the bundled faces exist in this deployment, to name the reason when no text face is embedded.
    static func report(of document: MarkdownDocument, options: PDFOptions, bundledFacesAvailable: Bool) throws -> MarkdownPDF.Render.Report {
        let catalog = try PDFEmbeddedFontCatalog(
            fonts: options.embeddedFonts,
            renderingMissingGlyphPolicy: options.conformance.isEnabled ? .reject : .useNotdef,
            omitUndrawableEmoji: options.omitUndrawableEmoji,
        )
        let hasTextFace = [StandardFont.helvetica, .helveticaBold, .helveticaOblique, .courier].contains { catalog.hasEntry(for: $0) }
        var order: [String] = []
        var found: [String: MarkdownPDF.Render.Report.Character] = [:]
        for text in document.blocks.flatMap(\.drawnTexts) where text.unicodeScalars.contains(where: { $0.value > 0x7F }) {
            for character in text {
                let scalars = Array(character.unicodeScalars)
                if scalars.allSatisfy({ PDFTextEncoding.isRepresentable($0) || PDFTextEncoding.isInvisibleFormatControl($0) }) {
                    continue
                }
                if hasTextFace, isDrawn(character, scalars: scalars, catalog: catalog) {
                    continue
                }
                let key = String(character)
                if var entry = found[key] {
                    entry.count += 1
                    found[key] = entry
                } else {
                    let reason: MarkdownPDF.Render.Report.Reason = hasTextFace ? .noFaceHasIt : (bundledFacesAvailable ? .noEmbeddedFace : .bundledFacesUnavailable)
                    found[key] = MarkdownPDF.Render.Report.Character(text: key, codePoints: scalars.map(\.value), reason: reason, count: 1)
                    order.append(key)
                }
            }
        }
        return MarkdownPDF.Render.Report(undrawn: order.compactMap { found[$0] }, diagramNotes: diagramNotes(of: document))
    }

    /// The notes of every Mermaid diagram of the document, in order: each diagram is parsed as the renderer parses it, and the notes it carries are
    /// numbered by the diagram's position among the Mermaid diagrams.
    private static func diagramNotes(of document: MarkdownDocument) -> [MarkdownPDF.Render.Report.DiagramNote] {
        var notes: [MarkdownPDF.Render.Report.DiagramNote] = []
        for (index, source) in document.blocks.flatMap(\.mermaidSources).enumerated() {
            guard case let .diagram(diagram) = MermaidDiagram.parse(source) else { continue }
            notes += diagram.notes.map { note in
                var numbered = note
                numbered.diagram = index + 1
                return numbered
            }
        }
        return notes
    }

    /// Whether an embedded face draws the character: the colour face for an emoji it has, a text face for every scalar of it.
    private static func isDrawn(_ character: Character, scalars: [Unicode.Scalar], catalog: PDFEmbeddedFontCatalog) -> Bool {
        if let cluster = EmojiSegmenter.cluster(of: character), catalog.colorEmoji?.drawing(of: cluster, fontSize: 10) != nil {
            return true
        }
        // a bare text-default emoji that no text face has is drawn from the colour face
        if scalars.count == 1, let sans = catalog.entry(for: .helvetica), catalog.bareEmojiNeedsColourFace(scalars[0], own: sans),
           catalog.bareEmojiPiece(scalars[0], size: 10) != nil
        {
            return true
        }
        return scalars.allSatisfy { scalar in
            if PDFTextEncoding.isInvisibleFormatControl(scalar) {
                return true
            }
            let one = String(scalar)
            return catalog.covers(one, font: .helvetica) || catalog.covers(one, font: .courier)
        }
    }
}

private extension MarkdownBlock {
    /// The sources of the Mermaid fences of the block, in reading order (a fence inside a quote, a list or a footnote counts).
    var mermaidSources: [String] {
        switch self {
        case let .blockQuote(blocks), let .footnoteDefinition(_, blocks):
            blocks.flatMap(\.mermaidSources)
        case let .unorderedList(items), let .orderedList(_, items):
            items.flatMap { $0.blocks.flatMap(\.mermaidSources) }
        case let .codeBlock(info, code):
            info?.split(separator: " ").first?.lowercased() == "mermaid" ? [code] : []
        case .heading, .paragraph, .displayMath, .table, .thematicBreak, .pageBreak, .html:
            []
        }
    }

    /// The texts of the block that the text path draws, in reading order. Diagrams and charts (a Mermaid or chart fence) and the source of formulas have
    /// their own paths and are not read.
    var drawnTexts: [String] {
        switch self {
        case let .heading(_, content), let .paragraph(content):
            content.flatMap(\.drawnTexts)
        case let .blockQuote(blocks), let .footnoteDefinition(_, blocks):
            blocks.flatMap(\.drawnTexts)
        case let .unorderedList(items), let .orderedList(_, items):
            items.flatMap { $0.blocks.flatMap(\.drawnTexts) }
        case let .codeBlock(info, code):
            Self.isDiagram(info) ? [] : [code]
        case let .html(code):
            [code]
        case let .table(table):
            (table.headers + table.rows.flatMap(\.self)).flatMap { $0.flatMap(\.drawnTexts) }
        case .displayMath, .thematicBreak, .pageBreak:
            []
        }
    }

    private static func isDiagram(_ info: String?) -> Bool {
        guard let word = info?.split(separator: " ").first?.lowercased() else { return false }
        return word == "mermaid" || word == "chart"
    }
}

private extension MarkdownInline {
    var drawnTexts: [String] {
        switch self {
        case let .text(text), let .code(text):
            [text]
        case let .emphasis(children), let .strong(children), let .strikethrough(children):
            children.flatMap(\.drawnTexts)
        case let .link(children, _, _):
            children.flatMap(\.drawnTexts)
        case .image, .inlineMath, .softBreak, .lineBreak, .footnoteReference, .indexMarker:
            []
        }
    }
}
