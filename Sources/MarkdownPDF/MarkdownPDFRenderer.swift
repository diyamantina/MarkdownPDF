import Foundation
import MathTypeset

public struct MarkdownPDFRenderer: Sendable {
    public var options: PDFOptions

    public init(options: PDFOptions = PDFOptions()) {
        self.options = options
    }

    public func render(
        markdown: String,
        assetsBaseURL: URL? = nil,
    ) throws -> Data {
        try render(
            sources: [MarkdownSource(markdown: markdown, assetsBaseURL: assetsBaseURL)],
            startsEachSourceOnNewPage: false,
        )
    }

    /// Renders several Markdown sources as one PDF.
    ///
    /// Each source resolves its own relative image paths against its own
    /// ``MarkdownSource/assetsBaseURL``. Sources are laid out in order as one
    /// document: heading destinations that repeat across sources get distinct
    /// names the same way repeated headings inside one file do, footnote labels are
    /// scoped to their own source (so `[^1]` in two files are two footnotes, numbered
    /// consecutively and listed once after the last source), and the PDF title is
    /// ``PDFOptions/title``. The table of contents, page numbers, and index cover the
    /// whole document. Passing no sources renders an empty document.
    ///
    /// - Parameters:
    ///   - sources: The Markdown documents in reading order.
    ///   - startsEachSourceOnNewPage: Begins every source after the first on a fresh
    ///     page when true, the default. A source that begins on an untouched page
    ///     does not leave a blank page.
    public func render(
        sources: [MarkdownSource],
        startsEachSourceOnNewPage: Bool = true,
    ) throws -> Data {
        let parser = MarkdownParser(
            options: MarkdownParser.Options(
                mathTypesetting: options.mathTypesetting.isEnabled,
                indexMarkers: options.index.isEnabled,
                ignoreHTMLComments: options.ignoreHTMLComments.isEnabled,
            ),
        )
        var units = sources.map { source in
            RenderUnit(document: parser.parse(source.markdown), assetsBaseURL: source.assetsBaseURL)
        }
        if units.isEmpty {
            units = [RenderUnit(document: MarkdownDocument(blocks: []), assetsBaseURL: nil)]
        }
        let colophon = try colophonContent()
        let combined = MarkdownDocument(blocks: units.flatMap(\.document.blocks) + (colophon?.blocks ?? []))
        return try renderUnits(
            units,
            colophon: colophon,
            options: resolvedOptions(for: combined),
            startsEachUnitOnNewPage: startsEachSourceOnNewPage,
        )
    }

    /// The blocks of the colophon, or nil when it is disabled. Custom text is parsed
    /// like a source, without index markers: the index does not search the colophon.
    private func colophonContent() throws -> ColophonContent? {
        guard options.colophon.isEnabled else {
            return nil
        }
        guard let custom = options.colophon.markdown else {
            return ColophonContent(
                blocks: ColophonDefaultText.blocks(title: options.title, author: options.author),
                assetsBaseURL: nil,
            )
        }
        guard !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MarkdownPDFError.colophonTextEmpty
        }
        let parser = MarkdownParser(
            options: MarkdownParser.Options(
                mathTypesetting: options.mathTypesetting.isEnabled,
                ignoreHTMLComments: options.ignoreHTMLComments.isEnabled,
            ),
        )
        return ColophonContent(blocks: parser.parse(custom).blocks, assetsBaseURL: options.colophon.assetsBaseURL)
    }

    private func resolvedOptions(for document: MarkdownDocument) -> PDFOptions {
        // Text outside WinAnsi needs the bundled faces; so does a typeset formula with a symbol the base fonts lack,
        // which would otherwise be spelled out ("int", "infinity", "pi").
        var resolvedOptions = options
        if options.embeddedFonts.hasNoTextFaces, document.containsNonWinAnsiText {
            let math = options.embeddedFonts.math
            resolvedOptions.embeddedFonts = .dejaVu
            resolvedOptions.embeddedFonts.math = math
        }
        // A formula with a symbol the base fonts lack is drawn with the math face, not spelled out ("int", "infinity", "pi").
        if options.mathTypesetting.isEnabled, resolvedOptions.embeddedFonts.math == nil, document.containsMathNeedingSymbols {
            resolvedOptions.embeddedFonts.math = BundledFonts.latinModernMath
        }
        return resolvedOptions
    }

    /// Lays the units out until everything that feeds back into pagination settles.
    ///
    /// Two things depend on the final layout: the table of contents (its entries
    /// carry page numbers, and the contents occupy pages themselves) and the index
    /// (which records the pages terms landed on, and is itself appended after the
    /// body). Each pass renders with the previous pass's table of contents and index,
    /// then derives both again; the pass whose output equals its input is final.
    /// Page number footers do not take part: they are drawn in the bottom margin
    /// after layout, so they cannot move content and the page count they print is
    /// exact.
    private func renderUnits(
        _ units: [RenderUnit],
        colophon: ColophonContent?,
        options: PDFOptions,
        startsEachUnitOnNewPage: Bool,
    ) throws -> Data {
        let imageCache = PDFImageCache()
        // Decoded once, before the first pass: the cover does not depend on layout, and
        // a missing or undecodable image must fail before any pass runs.
        let cover = try Self.coverImage(for: options.cover)
        func layout(
            tableOfContents: [TableOfContentsEntry]?,
            index: [IndexRecord],
        ) throws -> Layout {
            var layout = try Layout(options: options, imageCache: imageCache, cover: cover)
            try layout.render(
                units,
                startsEachUnitOnNewPage: startsEachUnitOnNewPage,
                tableOfContentsEntries: tableOfContents,
                indexRecords: index,
                colophon: colophon,
            )
            return layout
        }

        let tocEnabled = options.tableOfContents.isEnabled
        let indexEnabled = options.index.isEnabled
        guard tocEnabled || indexEnabled else {
            return try layout(tableOfContents: nil, index: []).pdfData()
        }

        let maximumDepth = options.tableOfContents.maximumDepth
        let first = try layout(tableOfContents: nil, index: [])
        var entries = tocEnabled ? first.tableOfContentsEntries(maximumDepth: maximumDepth) : []
        var records = indexEnabled ? first.indexRecords() : []
        guard !entries.isEmpty || !records.isEmpty else {
            return try first.pdfData()
        }

        let maximumPasses = 6
        for _ in 0 ..< maximumPasses {
            let next = try layout(tableOfContents: entries.isEmpty ? nil : entries, index: records)
            let nextEntries = tocEnabled ? next.tableOfContentsEntries(maximumDepth: maximumDepth) : []
            let nextRecords = indexEnabled ? next.indexRecords() : []
            if nextEntries == entries, nextRecords == records {
                return try next.pdfData()
            }
            entries = nextEntries
            records = nextRecords
        }

        throw MarkdownPDFError.tableOfContentsDidNotConverge(maxPasses: maximumPasses)
    }
}

private extension MarkdownPDFRenderer {
    /// The decoded cover image, named `Im1`, or nil when there is no cover. Throws a
    /// typed error for a file that cannot be read and for bytes that are not a PNG or
    /// JPEG: a cover is never dropped silently.
    static func coverImage(for cover: PDFOptions.Cover) throws -> PDFImage? {
        guard let source = cover.image else {
            return nil
        }

        switch source {
        case let .data(data):
            guard let image = PDFImage.decode(data: data, name: "Im1") else {
                throw MarkdownPDFError.coverImageUnsupported("cover image data")
            }
            return image
        case let .file(path, baseURL):
            let data: Data
            do {
                data = try Data(contentsOf: PDFImage.resolvedURL(source: path, baseURL: baseURL))
            } catch {
                throw MarkdownPDFError.coverImageUnreadable(path)
            }
            guard let image = PDFImage.decode(data: data, name: "Im1") else {
                throw MarkdownPDFError.coverImageUnsupported(path)
            }
            return image
        }
    }
}

private struct RenderUnit {
    var document: MarkdownDocument
    var assetsBaseURL: URL?
}

/// The parsed colophon and the folder its relative images resolve against.
private struct ColophonContent {
    var blocks: [MarkdownBlock]
    var assetsBaseURL: URL?
}

private extension MarkdownInline {
    var isIndexMarker: Bool {
        if case .indexMarker = self {
            return true
        }
        return false
    }
}

private extension MarkdownDocument {
    var containsNonWinAnsiText: Bool {
        blocks.contains(where: \.containsNonWinAnsiText)
    }
}

private extension MarkdownBlock {
    var isHeading: Bool {
        if case .heading = self {
            return true
        }
        return false
    }

    /// The list cut down to its first item, or nil when the block is not a list or
    /// the list is empty.
    var firstListItemAlone: MarkdownBlock? {
        switch self {
        case let .unorderedList(items):
            items.first.map { .unorderedList([$0]) }
        case let .orderedList(start, items):
            items.first.map { .orderedList(start: start, items: [$0]) }
        default:
            nil
        }
    }

    var containsNonWinAnsiText: Bool {
        switch self {
        case let .heading(_, content), let .paragraph(content):
            content.contains(where: \.containsNonWinAnsiText)
        case let .blockQuote(blocks):
            blocks.contains(where: \.containsNonWinAnsiText)
        case let .unorderedList(items), let .orderedList(_, items):
            items.contains { $0.blocks.contains(where: \.containsNonWinAnsiText) }
        case let .codeBlock(_, code), let .html(code):
            code.containsNonWinAnsiScalar
        case let .displayMath(math):
            math.source.containsNonWinAnsiScalar
        case let .table(table):
            (table.headers + table.rows.flatMap(\.self))
                .contains { $0.contains(where: \.containsNonWinAnsiText) }
        case let .footnoteDefinition(_, blocks):
            blocks.contains(where: \.containsNonWinAnsiText)
        case .thematicBreak, .pageBreak:
            false
        }
    }
}

private extension MarkdownInline {
    var containsNonWinAnsiText: Bool {
        switch self {
        case let .text(text), let .code(text):
            text.containsNonWinAnsiScalar
        case let .inlineMath(math):
            math.source.containsNonWinAnsiScalar
        case let .emphasis(children), let .strong(children), let .strikethrough(children):
            children.contains(where: \.containsNonWinAnsiText)
        case let .link(children, _, _):
            children.contains(where: \.containsNonWinAnsiText)
        case let .image(alt, _, _):
            alt.containsNonWinAnsiScalar
        case .softBreak, .lineBreak, .footnoteReference, .indexMarker:
            false
        }
    }
}

private extension String {
    var containsNonWinAnsiScalar: Bool {
        PDFTextEncoding.strippingInvisibleFormatControls(self)
            .unicodeScalars
            .contains { !PDFTextEncoding.isRepresentable($0) }
    }
}

private struct TableOfContentsEntry: Equatable {
    var destinationName: String
    var title: String
    var level: Int
    var pageNumber: Int
}

private struct ResolvedFootnote {
    var labelKey: String
    var number: Int
    var definitionDestinationName: String
    var referenceDestinationName: String
    var blocks: [MarkdownBlock]
}

private struct ResolvedFootnoteDocuments {
    /// The body blocks of each input document with footnote definitions removed.
    var bodyBlocks: [[MarkdownBlock]]
    var footnotes: [ResolvedFootnote]
    var footnotesByLabelKey: [String: ResolvedFootnote]
}

/// Resolves footnotes across one or more documents.
///
/// Labels are scoped to their own document: the lookup key is the document's
/// namespace (`"0:"`, `"1:"`, ...) followed by the normalized label, so `[^1]` in
/// two merged sources are two footnotes. Numbers run consecutively over the whole
/// merged document in order of first reference.
private struct FootnoteResolver {
    /// The key prefix for one document. A single document uses the same scheme, so
    /// the renderer never needs a separate path.
    static func namespace(forDocument index: Int) -> String {
        "\(index):"
    }

    var namespace = ""

    func resolve(_ documents: [MarkdownDocument]) -> ResolvedFootnoteDocuments {
        var definitions: [String: [MarkdownBlock]] = [:]
        var bodyBlocks: [[MarkdownBlock]] = []
        var orderedKeys: [String] = []
        var seen = Set<String>()

        for (index, document) in documents.enumerated() {
            let scoped = FootnoteResolver(namespace: Self.namespace(forDocument: index))
            for (key, blocks) in scoped.collectDefinitions(in: document.blocks) {
                definitions[key] = blocks
            }
            bodyBlocks.append(scoped.stripFootnoteDefinitions(from: document.blocks))
        }
        for (index, blocks) in bodyBlocks.enumerated() {
            let scoped = FootnoteResolver(namespace: Self.namespace(forDocument: index))
            for block in blocks {
                scoped.collectReferences(in: block, definitions: definitions, seen: &seen, orderedKeys: &orderedKeys)
            }
        }

        let footnotes = orderedKeys.enumerated().compactMap { index, key -> ResolvedFootnote? in
            guard let blocks = definitions[key] else {
                return nil
            }
            let number = index + 1
            return ResolvedFootnote(
                labelKey: key,
                number: number,
                definitionDestinationName: "fn-\(number)",
                referenceDestinationName: "fnref-\(number)",
                blocks: blocks,
            )
        }
        let footnotesByLabelKey = Dictionary(uniqueKeysWithValues: footnotes.map { ($0.labelKey, $0) })
        return ResolvedFootnoteDocuments(
            bodyBlocks: bodyBlocks,
            footnotes: footnotes,
            footnotesByLabelKey: footnotesByLabelKey,
        )
    }

    private func scopedKey(_ label: String) -> String {
        namespace + footnoteLabelKey(label)
    }

    private func collectDefinitions(in blocks: [MarkdownBlock]) -> [String: [MarkdownBlock]] {
        var definitions: [String: [MarkdownBlock]] = [:]
        for block in blocks {
            collectDefinitions(in: block, into: &definitions)
        }
        return definitions
    }

    private func collectDefinitions(
        in block: MarkdownBlock,
        into definitions: inout [String: [MarkdownBlock]],
    ) {
        switch block {
        case let .footnoteDefinition(label, blocks):
            definitions[scopedKey(label)] = definitions[scopedKey(label)] ?? blocks
        case let .blockQuote(blocks):
            for block in blocks {
                collectDefinitions(in: block, into: &definitions)
            }
        case let .unorderedList(items), let .orderedList(_, items):
            for item in items.flatMap(\.blocks) {
                collectDefinitions(in: item, into: &definitions)
            }
        case .heading, .paragraph, .codeBlock, .displayMath, .table, .thematicBreak, .pageBreak, .html:
            break
        }
    }

    private func stripFootnoteDefinitions(from blocks: [MarkdownBlock]) -> [MarkdownBlock] {
        blocks.compactMap(stripFootnoteDefinitions)
    }

    private func stripFootnoteDefinitions(from block: MarkdownBlock) -> MarkdownBlock? {
        switch block {
        case .footnoteDefinition:
            return nil
        case let .blockQuote(blocks):
            let stripped = stripFootnoteDefinitions(from: blocks)
            return stripped.isEmpty ? nil : .blockQuote(stripped)
        case let .unorderedList(items):
            return .unorderedList(items.map { item in
                MarkdownBlock.ListItem(
                    blocks: stripFootnoteDefinitions(from: item.blocks),
                    checkbox: item.checkbox,
                )
            })
        case let .orderedList(start, items):
            return .orderedList(
                start: start,
                items: items.map { item in
                    MarkdownBlock.ListItem(
                        blocks: stripFootnoteDefinitions(from: item.blocks),
                        checkbox: item.checkbox,
                    )
                },
            )
        case .heading, .paragraph, .codeBlock, .displayMath, .table, .thematicBreak, .pageBreak, .html:
            return block
        }
    }

    private func collectReferences(
        in block: MarkdownBlock,
        definitions: [String: [MarkdownBlock]],
        seen: inout Set<String>,
        orderedKeys: inout [String],
    ) {
        switch block {
        case let .heading(_, content), let .paragraph(content):
            collectReferences(in: content, definitions: definitions, seen: &seen, orderedKeys: &orderedKeys)
        case let .blockQuote(blocks):
            for block in blocks {
                collectReferences(in: block, definitions: definitions, seen: &seen, orderedKeys: &orderedKeys)
            }
        case let .unorderedList(items), let .orderedList(_, items):
            for item in items.flatMap(\.blocks) {
                collectReferences(in: item, definitions: definitions, seen: &seen, orderedKeys: &orderedKeys)
            }
        case let .table(table):
            for item in table.headers + table.rows.flatMap(\.self) {
                collectReferences(in: item, definitions: definitions, seen: &seen, orderedKeys: &orderedKeys)
            }
        case .codeBlock, .displayMath, .thematicBreak, .pageBreak, .html, .footnoteDefinition:
            break
        }
    }

    private func collectReferences(
        in inlines: [MarkdownInline],
        definitions: [String: [MarkdownBlock]],
        seen: inout Set<String>,
        orderedKeys: inout [String],
    ) {
        for inline in inlines {
            switch inline {
            case let .footnoteReference(label):
                let key = scopedKey(label)
                if definitions[key] != nil, seen.insert(key).inserted {
                    orderedKeys.append(key)
                }
            case let .emphasis(children), let .strong(children), let .strikethrough(children):
                collectReferences(in: children, definitions: definitions, seen: &seen, orderedKeys: &orderedKeys)
            case let .link(children, _, _):
                collectReferences(in: children, definitions: definitions, seen: &seen, orderedKeys: &orderedKeys)
            case .text, .softBreak, .lineBreak, .code, .inlineMath, .image, .indexMarker:
                break
            }
        }
    }
}

private func footnoteLabelKey(_ label: String) -> String {
    label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private struct TableColumnMetrics {
    var minimumWidth: Double
    var preferredWidth: Double
}

private struct TablePreparedRow {
    var cellLines: [[[PDFTextRun]]]
}

private struct BidiLine {
    var visualRuns: [BidiPositionedRun]
}

private struct BidiPositionedRun {
    var sourceTextRun: PDFTextRun
    var displayText: String
    var x: Double
    var sourceScalarOffset: Int
    /// A whole-run shaping already computed in LOGICAL order (cursive scripts).
    /// When set, the run is drawn from this mapping rather than the per-character
    /// path, and `isRightToLeft` decides the visual glyph order.
    var preShapedMapping: ShapedTextMapping?
    var isRightToLeft: Bool = false
}

private struct Layout {
    var options: PDFOptions
    /// The base for relative image paths of the unit being rendered.
    var assetsBaseURL: URL?
    var pages: [PDFPageCanvas] = [PDFPageCanvas()]
    var images: [PDFImage] = []
    var imageCache: [String: PDFImage] = [:]
    let sharedImages: PDFImageCache
    /// 1 when physical page 1 is the cover, otherwise 0. The cover is never numbered:
    /// printed page `n` is physical page `n + coverPageCount`.
    let coverPageCount: Int

    /// The scope of footnote labels for the unit being rendered. See
    /// ``FootnoteResolver``.
    var footnoteNamespace = FootnoteResolver.namespace(forDocument: 0)
    var indexRegistry = IndexRegistry()
    var indexMatcher: IndexTermMatcher?
    /// Terms from markers-only paragraphs, attached to the next line drawn so they
    /// land on the page that line lands on.
    var pendingIndexTerms: [String] = []
    var headingNames = PDFHeadingDestinationName()
    var embeddedFonts: PDFEmbeddedFontCatalog
    var taggedContentBuilder: PDFTaggedContentBuilder?
    var markedContentDepth = 0
    var y: Double
    var listDepth = 0

    /// True while a block is being laid out only to learn whether it fits. See
    /// ``fits(onFreshPage:_:)``.
    var isMeasuring = false

    /// Where the last heading ended. A block that starts exactly there is not moved
    /// to the next page on its own, which would leave the heading behind.
    var headingEnd: (page: Int, y: Double)?

    /// One entry per open block quote, innermost last.
    ///
    /// `hasDrawn` distinguishes "the quote started on this page" from "the quote's
    /// first block broke the page before drawing anything". Only in the second case
    /// may the origin move, which is what keeps a rule off a page that carries no
    /// quote content.
    struct BlockQuoteFrame {
        var page: Int
        var top: Double
        var hasDrawn = false
    }

    var blockQuoteFrames: [BlockQuoteFrame] = []

    var blockQuoteDepth: Int {
        blockQuoteFrames.count
    }

    var footnotesByLabelKey: [String: ResolvedFootnote] = [:]
    var registeredNamedDestinations = Set<String>()

    init(options: PDFOptions, imageCache: PDFImageCache, cover: PDFImage? = nil) throws {
        self.options = options
        sharedImages = imageCache
        coverPageCount = cover == nil ? 0 : 1
        if options.index.isEnabled {
            var terms: [(entry: IndexEntryID, text: String)] = []
            for text in options.index.terms {
                // A blank term has always been ignored; only a pipe makes an empty form an error.
                guard !text.allSatisfy(\.isWhitespace) else {
                    continue
                }
                let term = try PDFOptions.Index.Term(parsing: text)
                guard let entry = IndexRegistry.entry(for: term.heading) else {
                    continue
                }
                indexRegistry.register(entry)
                terms.append((entry.id, entry.sub ?? entry.main))
                for variant in term.variants {
                    terms.append((entry.id, variant))
                }
            }
            indexMatcher = IndexTermMatcher(terms: terms)
        }
        try Self.validateConformance(options)
        embeddedFonts = try PDFEmbeddedFontCatalog(
            fonts: options.embeddedFonts,
            parseMathTables: options.mathTypesetting.isEnabled,
            // A conformance profile forbids referencing the .notdef glyph in
            // content, so keep the correct-or-refuse posture there rather than
            // drawing notdef for a scalar the font lacks.
            renderingMissingGlyphPolicy: options.conformance.isEnabled ? .reject : .useNotdef,
            omitUndrawableEmoji: options.omitUndrawableEmoji,
        )
        taggedContentBuilder = options.taggedPDF.isEnabled || options.conformance.requiresTaggedPDF
            ? PDFTaggedContentBuilder()
            : nil
        y = options.pageSize.height - options.margins.top
        drawPageBackgroundIfNeeded()
        if let cover {
            drawCover(cover)
            startNewPage()
        }
    }

    /// Draws the cover on the current (first) page: the image alone, fitted by
    /// ``PDFCoverFit``, over the page background or white. Its outline entry is
    /// "Cover"; it is not a table of contents entry.
    private mutating func drawCover(_ image: PDFImage) {
        if options.theme.pageBackground == nil {
            // Transparent pixels composite over white, whatever the viewer paints.
            let artifact = beginArtifactIfTagged()
            currentPage.drawRectangle(
                x: 0,
                y: 0,
                width: options.pageSize.width,
                height: options.pageSize.height,
                stroke: nil,
                fill: .white,
            )
            endMarkedContentIfNeeded(artifact)
        }

        images.append(image)
        let rectangle = PDFCoverFit.rectangle(
            imageWidth: image.width,
            imageHeight: image.height,
            page: options.pageSize,
        )
        let figure = beginStructureElement(
            .figure,
            attributes: PDFTaggedContent.Attributes(alternateDescription: coverAlternateDescription),
        )
        let marked = beginMarkedContentForCurrentElement()
        currentPage.drawImage(
            name: image.name,
            x: rectangle.x,
            y: rectangle.y,
            width: rectangle.width,
            height: rectangle.height,
        )
        endMarkedContentIfNeeded(marked)
        endStructureElement(figure)
        currentPage.addHeadingDestination(
            PDFHeadingDestination(
                name: Self.coverDestinationName,
                title: "Cover",
                level: 1,
                x: 0,
                y: options.pageSize.height,
                isOutlineLeaf: true,
            ),
        )
    }

    private static let coverDestinationName = "mdpdf-cover"

    /// "Cover of Title by Author", with the missing parts left out.
    private var coverAlternateDescription: String {
        let title = options.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let author = options.author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var text = "Cover"
        if !title.isEmpty {
            text += " of \(title)"
        }
        if !author.isEmpty {
            text += " by \(author)"
        }
        return text
    }

    private static func validateConformance(_ options: PDFOptions) throws {
        guard options.conformance.requiresDocumentTitle else {
            return
        }

        let title = options.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            throw MarkdownPDFError.missingConformanceTitle(profile: options.conformance.displayName)
        }
    }

    mutating func render(
        _ units: [RenderUnit],
        startsEachUnitOnNewPage: Bool,
        tableOfContentsEntries: [TableOfContentsEntry]? = nil,
        indexRecords: [IndexRecord] = [],
        colophon: ColophonContent? = nil,
    ) throws {
        let resolvedFootnotes = FootnoteResolver().resolve(units.map(\.document))
        footnotesByLabelKey = resolvedFootnotes.footnotesByLabelKey
        let firstBlocks = MarkdownDocument(blocks: resolvedFootnotes.bodyBlocks.first ?? [])
        let tableOfContentsInsertionIndex = tableOfContentsEntries.map {
            $0.isEmpty ? nil : self.tableOfContentsInsertionIndex(for: firstBlocks)
        } ?? nil

        if tableOfContentsInsertionIndex == 0, let tableOfContentsEntries {
            try renderTableOfContents(tableOfContentsEntries)
        }

        for (unitIndex, unit) in units.enumerated() {
            assetsBaseURL = unit.assetsBaseURL
            footnoteNamespace = FootnoteResolver.namespace(forDocument: unitIndex)
            let blocks = resolvedFootnotes.bodyBlocks[unitIndex]
            if unitIndex > 0, startsEachUnitOnNewPage, y != pageTopY {
                startNewPage()
            }

            for (index, block) in blocks.enumerated() {
                // A heading that ends a unit is only "last" when nothing can follow it
                // on the same page: the end of the document, or a forced page break.
                let endsPage = index == blocks.count - 1
                    && (unitIndex == units.count - 1 || startsEachUnitOnNewPage)
                try keepHeadingWithItsSection(
                    at: index,
                    in: blocks,
                    contentsIndex: unitIndex == 0 && tableOfContentsEntries != nil ? tableOfContentsInsertionIndex : nil,
                )
                keepHeadingWithNextBlock(block, isLast: endsPage)
                try render(block)
                if unitIndex == 0, tableOfContentsInsertionIndex == index + 1, let tableOfContentsEntries {
                    try renderTableOfContents(tableOfContentsEntries)
                }
            }
        }

        try renderFootnoteSection(resolvedFootnotes.footnotes)
        flushPendingIndexTerms()
        try renderIndex(indexRecords)
        try renderColophon(colophon)
        try stampPageNumbers()
    }

    /// Appends the colophon on a fresh page after the index. Its blocks go through the
    /// ordinary block renderer, so a heading reaches the outline and the contents,
    /// and the link is a real annotation. The index does not search it.
    private mutating func renderColophon(_ colophon: ColophonContent?) throws {
        guard let colophon else {
            return
        }
        if y != pageTopY {
            startNewPage()
        }
        assetsBaseURL = colophon.assetsBaseURL
        indexMatcher = nil
        for block in colophon.blocks {
            try render(block)
        }
    }

    private func footnoteKey(_ label: String) -> String {
        footnoteNamespace + footnoteLabelKey(label)
    }

    func indexRecords() -> [IndexRecord] {
        indexRegistry.records()
    }

    func pdfData() throws -> Data {
        try PDFDocumentWriter(
            pageSize: options.pageSize,
            fontSet: options.fontSet,
            pages: pages,
            images: images,
            title: options.title,
            author: options.author,
            streamCompression: options.streamCompression,
            taggedContent: taggedContentBuilder?.build(language: options.taggedPDF.language),
            conformance: options.conformance,
            documentStrings: options.documentStrings,
        ).data()
    }

    func tableOfContentsEntries(maximumDepth: Int) -> [TableOfContentsEntry] {
        pages.enumerated().flatMap { pageIndex, page in
            page.headingDestinations.compactMap { destination in
                guard pageIndex >= coverPageCount, destination.level <= maximumDepth else {
                    return nil
                }

                return TableOfContentsEntry(
                    destinationName: destination.name,
                    title: destination.title,
                    level: destination.level,
                    pageNumber: pageIndex + 1,
                )
            }
        }
    }

    private mutating func render(_ block: MarkdownBlock) throws {
        switch block {
        case let .heading(level, content):
            let element = beginStructureElement(.heading(level: level))
            defer { endStructureElement(element) }
            let style = style(for: .heading(level: level))
            let size = headingSize(level)
            let topSpacing = headingTopSpacing(level)
            ensureSpace(size * 1.8 + topSpacing)
            addHeadingTopSpacing(topSpacing)
            addHeadingDestination(level: level, content: content, y: y + size * 0.4)
            try drawWrapped(
                flatten(content, font: standardFont(for: style.fontRole), size: size, color: style.color),
                x: options.margins.left,
                maxWidth: contentWidth,
                lineHeight: size * style.lineHeightMultiplier,
                indexable: true,
            )
            y -= size * style.spacingAfterMultiplier
            headingEnd = (currentPageIndex, y)
        case let .paragraph(content):
            if !content.isEmpty, content.allSatisfy(\.isIndexMarker) {
                // A paragraph of nothing but index markers draws nothing and takes no
                // space. Its terms attach to the next line drawn, so they land on the
                // page that line lands on.
                for case let .indexMarker(term) in content {
                    pendingIndexTerms.append(term)
                }
            } else if try renderStandaloneImage(content) {
                y -= figureTrailingSpacing
            } else {
                let element = beginStructureElement(.paragraph)
                defer { endStructureElement(element) }
                let role: PDFOptions.ElementRole = listDepth > 0 ? .list : .paragraph
                let style = style(for: role)
                try drawWrapped(
                    flatten(content, font: standardFont(for: style.fontRole), size: fontSize(for: role), color: style.color),
                    x: options.margins.left,
                    maxWidth: contentWidth,
                    lineHeight: bodyLineHeight,
                    indexable: true,
                )
                y -= paragraphSpacing
            }
        case let .blockQuote(blocks):
            let element = beginStructureElement(.blockQuote)
            defer { endStructureElement(element) }
            ensureSpace(24)
            let savedLeft = options.margins.left
            indentLeftMargin(by: 14)
            y -= blockQuoteTopSpacing

            let quoteStyle = style(for: .blockQuote)
            // The origin is provisional. `y` is the first line's baseline, so the
            // rule starts an ascender above it, at the top of that line's box.
            // If the first block breaks the page before drawing, `startNewPage`
            // moves this origin to the new page. See `BlockQuoteFrame`.
            blockQuoteFrames.append(BlockQuoteFrame(
                page: currentPageIndex,
                top: min(pageTopY, y + fontSize(for: .paragraph) * 0.75),
            ))
            let frame: BlockQuoteFrame
            do {
                for nested in blocks {
                    try render(nested)
                }
                frame = blockQuoteFrames.removeLast()
            } catch {
                blockQuoteFrames.removeLast()
                throw error
            }

            // `y` already carries the last block's trailing spacing, which can
            // legally dip below the bottom margin without forcing a page break.
            let bottomY = max(y + paragraphSpacing, options.margins.bottom)
            // The fill is inserted under the page's content; the rule is appended
            // over it.
            drawBlockQuoteBackground(
                color: quoteStyle.backgroundColor,
                x: savedLeft,
                width: options.pageSize.width - options.margins.right - savedLeft,
                firstPage: frame.page,
                topY: frame.top,
                lastPage: currentPageIndex,
                bottomY: bottomY,
            )
            drawBlockQuoteRule(
                color: quoteStyle.borderColor,
                x: savedLeft + 3,
                firstPage: frame.page,
                topY: frame.top,
                lastPage: currentPageIndex,
                bottomY: bottomY,
            )

            y -= blockQuoteBottomSpacing
            options.margins.left = savedLeft
        case let .unorderedList(items):
            try renderList(items: items, start: nil)
        case let .orderedList(start, items):
            try renderList(items: items, start: start)
        case let .codeBlock(info, code):
            if isMermaidCodeBlock(info) {
                try renderMermaidBlock(code)
            } else if isChartCodeBlock(info) {
                try renderChartFenceBlock(code)
            } else if let tileType = tileFenceType(info) {
                try renderTileBlock(type: tileType, code: code)
            } else if isVerticalCodeBlock(info) {
                try renderVerticalBlock(code)
            } else {
                try renderCodeBlock(code, info: info)
            }
        case let .displayMath(math):
            try renderDisplayMath(math)
        case let .table(table):
            try renderTable(table)
        case .pageBreak:
            // Breaking a page that has drawn nothing yet would emit a blank page,
            // so a leading break and consecutive breaks collapse here.
            // `y == pageTopY` is the "nothing drawn" witness. Trailing breaks are
            // already dropped by the parser.
            if y != pageTopY {
                startNewPage()
            }
        case .thematicBreak:
            ensureSpace(18)
            markBlockQuoteContentDrawn()
            let artifact = beginArtifactIfTagged()
            defer { endMarkedContentIfNeeded(artifact) }
            currentPage.drawLine(
                x1: options.margins.left,
                y1: y,
                x2: options.pageSize.width - options.margins.right,
                y2: y,
                width: 0.75,
                color: style(for: .thematicBreak).borderColor ?? style(for: .thematicBreak).color,
            )
            y -= 18
        case let .html(html):
            let element = beginStructureElement(.paragraph)
            defer { endStructureElement(element) }
            let style = style(for: .html)
            try drawWrapped(
                [PDFTextRun(text: html, font: standardFont(for: style.fontRole), size: fontSize(for: .html), color: style.color)],
                x: options.margins.left,
                maxWidth: contentWidth,
                lineHeight: fontSize(for: .html) * style.lineHeightMultiplier,
            )
            y -= options.baseFontSize * style.spacingAfterMultiplier
        case .footnoteDefinition:
            break
        }
    }

    private func tableOfContentsInsertionIndex(for document: MarkdownDocument) -> Int {
        guard let first = document.blocks.first,
              case .heading(level: 1, _) = first
        else {
            return 0
        }

        return 1
    }

    private mutating func renderTableOfContents(_ entries: [TableOfContentsEntry]) throws {
        let tocElement = beginStructureElement(.tableOfContents)
        defer { endStructureElement(tocElement) }

        let titleSize = options.baseFontSize * 1.55
        let entrySize = options.baseFontSize * 0.95
        let lineHeight = entrySize * 1.35
        let titleStyle = style(for: .heading2)
        let widestPageNumber = try entries
            .map { try textWidth(PDFTextRun(text: pageLabel(forPageIndex: $0.pageNumber - 1), font: .helvetica, size: entrySize)) }
            .max() ?? 0
        let pageColumnWidth = max(28, widestPageNumber + 8)
        let title = options.tableOfContents.title.trimmingCharacters(in: .whitespacesAndNewlines)

        ensureSpace(titleSize * 2.2 + lineHeight)
        let titleElement = beginStructureElement(.paragraph)
        try drawRuns(
            [
                PDFTextRun(
                    text: title.isEmpty ? "Table of Contents" : title,
                    font: standardFont(for: titleStyle.fontRole),
                    size: titleSize,
                    color: titleStyle.color,
                ),
            ],
            x: options.margins.left,
            y: y,
        )
        endStructureElement(titleElement)
        y -= titleSize * 1.45

        for entry in entries {
            try renderTableOfContentsEntry(
                entry,
                entrySize: entrySize,
                lineHeight: lineHeight,
                pageColumnWidth: pageColumnWidth,
            )
        }

        y -= options.baseFontSize * 0.9
    }

    private mutating func renderTableOfContentsEntry(
        _ entry: TableOfContentsEntry,
        entrySize: Double,
        lineHeight: Double,
        pageColumnWidth: Double,
    ) throws {
        let itemElement = beginStructureElement(.tableOfContentsItem)
        defer { endStructureElement(itemElement) }

        let indent = Double(max(0, entry.level - 1)) * 14
        let x = options.margins.left + indent
        let pageText = pageLabel(forPageIndex: entry.pageNumber - 1)
        let bodyStyle = style(for: .body)
        let linkStyle = style(for: .link)
        let pageRun = PDFTextRun(text: pageText, font: standardFont(for: bodyStyle.fontRole), size: entrySize, color: bodyStyle.color)
        let pageRunWidth = try textWidth(pageRun)
        let pageX = options.pageSize.width - options.margins.right - pageRunWidth
        let titleWidth = max(36, contentWidth - indent - pageColumnWidth - 10)
        let titleLines = try wrappedLines(
            [
                PDFTextRun(
                    text: entry.title,
                    font: standardFont(for: bodyStyle.fontRole),
                    size: entrySize,
                    color: linkStyle.color,
                    linkDestination: "#\(entry.destinationName)",
                ),
            ],
            maxWidth: titleWidth,
        )

        ensureSpace(Double(titleLines.count) * lineHeight)
        for (index, line) in titleLines.enumerated() {
            try drawRuns(line, x: x, y: y)
            if index == titleLines.count - 1 {
                let lineWidth = try textWidth(line)
                drawTableOfContentsLeader(from: x + lineWidth + 5, to: pageX - 5, y: y + entrySize * 0.3)
                try currentPage.drawTextRun(
                    pageRun,
                    x: pageX,
                    y: y,
                    fontSet: options.fontSet,
                    embeddedFonts: embeddedFonts,
                )
            }
            y -= lineHeight
        }
    }

    private mutating func drawTableOfContentsLeader(from startX: Double, to endX: Double, y: Double) {
        guard endX - startX > 12 else {
            return
        }

        let artifact = beginArtifactIfTagged()
        defer { endMarkedContentIfNeeded(artifact) }
        currentPage.drawLine(
            x1: startX,
            y1: y,
            x2: endX,
            y2: y,
            width: 0.25,
            color: options.theme == .default
                ? PDFColor(red: 0.72, green: 0.72, blue: 0.72)
                : style(for: .thematicBreak).borderColor ?? PDFColor(red: 0.72, green: 0.72, blue: 0.72),
        )
    }

    // MARK: Page numbers

    /// The printed label of the page at `index`: its number under
    /// ``PDFOptions/PageNumbers`` when enabled, its physical number otherwise.
    private func pageLabel(forPageIndex index: Int) -> String {
        let config = options.pageNumbers
        guard config.isEnabled else {
            return String(index + 1)
        }
        return PDFPageLabel.text(config.firstPageNumber + index - coverPageCount, format: config.format)
    }

    /// Draws every page's number in the bottom margin once layout is final.
    ///
    /// The footer sits in the margin band below the body, vertically centred, so it
    /// cannot move body content and needs no layout pass of its own: the page count
    /// it prints is exact. It is drawn directly on each page (like block quote
    /// rules), as an artifact when the document is tagged.
    private mutating func stampPageNumbers() throws {
        let config = options.pageNumbers
        guard config.isEnabled else {
            return
        }

        let size = options.baseFontSize * 0.8
        guard options.margins.bottom >= size * 2 else {
            throw MarkdownPDFError.pageNumbersNeedBottomMargin(minimum: size * 2, actual: options.margins.bottom)
        }

        let bodyStyle = style(for: .body)
        let font = standardFont(for: bodyStyle.fontRole)
        let lastNumber = config.firstPageNumber + pages.count - coverPageCount - 1
        // Centre the glyph box (0.75 em above the baseline, 0.25 em below) in the margin.
        let baseline = options.margins.bottom / 2 - size * 0.25
        let isTagged = taggedContentBuilder != nil
        for (index, page) in pages.enumerated() {
            // The cover is never numbered, and the first numbered page is the one
            // after it.
            let printedIndex = index - coverPageCount
            if printedIndex < 0 || (printedIndex == 0 && config.skipsFirstPage) {
                continue
            }

            let number = config.firstPageNumber + printedIndex
            let run = PDFTextRun(
                text: PDFPageLabel.footerText(number, last: lastNumber, format: config.format),
                font: font,
                size: size,
                color: bodyStyle.color,
            )
            let width = try textWidth(run)
            let leftEdge = options.margins.left
            let rightEdge = options.pageSize.width - options.margins.right - width
            let x: Double = switch config.position {
            case .bottomCenter:
                leftEdge + (contentWidth - width) / 2
            case .bottomOutside:
                // Right-hand pages carry odd numbers, so odd numbers go to the right.
                number.isMultiple(of: 2) ? leftEdge : rightEdge
            case .bottomRight:
                rightEdge
            }

            if isTagged {
                page.beginArtifact()
            }
            try page.drawTextRun(run, x: x, y: baseline, fontSet: options.fontSet, embeddedFonts: embeddedFonts)
            if isTagged {
                page.endMarkedContent()
            }
        }
    }

    // MARK: Index

    private mutating func recordIndexTerm(_ term: String) {
        guard options.index.isEnabled, let entry = IndexRegistry.entry(for: term) else {
            return
        }
        indexRegistry.register(entry)
        indexRegistry.record(entry.id, page: currentPageIndex)
    }

    private mutating func flushPendingIndexTerms() {
        guard !pendingIndexTerms.isEmpty else {
            return
        }
        let terms = pendingIndexTerms
        pendingIndexTerms = []
        for term in terms {
            recordIndexTerm(term)
        }
    }

    /// Term-list matches in laid-out lines, keyed by the line each match starts on.
    /// Text from inline code and math, and zero-width marker runs, is not searched.
    private func indexHits(inLines lines: [[PDFTextRun]]) -> [Int: [IndexEntryID]] {
        guard let matcher = indexMatcher, !matcher.isEmpty else {
            return [:]
        }

        let texts = lines.map { line in
            line.filter { $0.isIndexable && $0.indexTerm == nil }.map(\.text).joined()
        }
        var hits: [Int: [IndexEntryID]] = [:]
        for match in matcher.matches(inLines: texts) {
            hits[match.line, default: []].append(match.entry)
        }
        return hits
    }

    /// A named destination at the top of a physical page, the target of index links.
    private func pageDestinationName(forPageIndex index: Int) -> String {
        "mdpdf-page-\(index + 1)"
    }

    private mutating func registerPageDestination(forPageIndex index: Int) {
        let name = pageDestinationName(forPageIndex: index)
        guard registeredNamedDestinations.insert(name).inserted else {
            return
        }
        pages[index].addNamedDestination(
            PDFHeadingDestination(
                name: name,
                title: name,
                level: 6,
                x: options.margins.left,
                y: min(options.pageSize.height, pageTopY),
            ),
        )
    }

    /// Appends the index on a fresh page: a level-one heading (so it reaches the
    /// outline and table of contents), then entries under letter headings.
    private mutating func renderIndex(_ records: [IndexRecord]) throws {
        guard options.index.isEnabled, !records.isEmpty else {
            return
        }

        if y != pageTopY {
            startNewPage()
        }
        let title = options.index.title.trimmingCharacters(in: .whitespacesAndNewlines)
        try render(.heading(level: 1, content: [.text(title.isEmpty ? "Index" : title)]))

        let indexElement = beginStructureElement(.index)
        defer { endStructureElement(indexElement) }
        let bodyStyle = style(for: .body)
        let headingStyle = style(for: .heading2)
        let entrySize = options.baseFontSize * 0.95
        let lineHeight = entrySize * 1.35
        let letterSize = entrySize * 1.2

        var currentGroup: String?
        for record in records {
            let group = IndexCollation.groupHeading(for: record.display)
            if group != currentGroup {
                currentGroup = group
                y -= entrySize * 0.5
                ensureSpace(letterSize * 1.6 + lineHeight * 2)
                let letterElement = beginStructureElement(.paragraph)
                try drawRuns(
                    [PDFTextRun(text: group, font: standardFont(for: headingStyle.fontRole), size: letterSize, color: headingStyle.color)],
                    x: options.margins.left,
                    y: y,
                )
                endStructureElement(letterElement)
                y -= letterSize * 1.5
            }

            try renderIndexEntry(record, level: 0, size: entrySize, lineHeight: lineHeight, bodyStyle: bodyStyle)
            for sub in record.subentries {
                try renderIndexEntry(sub, level: 1, size: entrySize, lineHeight: lineHeight, bodyStyle: bodyStyle)
            }
        }
    }

    private mutating func renderIndexEntry(
        _ record: IndexRecord,
        level: Int,
        size: Double,
        lineHeight: Double,
        bodyStyle: PDFOptions.ElementStyle,
    ) throws {
        let linkStyle = style(for: .link)
        let font = standardFont(for: bodyStyle.fontRole)
        func plain(_ text: String) -> PDFTextRun {
            PDFTextRun(text: text, font: font, size: size, color: bodyStyle.color)
        }

        let indent = Double(level) * 16
        let hangingIndent = 14.0
        let x = options.margins.left + indent
        let width = max(36, contentWidth - indent - hangingIndent)

        // Fill lines by hand so a reference and the comma after it never part: the
        // general wrapper breaks between any two runs, which would strand a comma at
        // the start of a line.
        let references = PDFPageLabel.references(forPages: record.pages) { pageLabel(forPageIndex: $0) }
        var lines = try wrappedLines([plain(record.display)], maxWidth: width)
        var current = lines.removeLast()
        var currentWidth = try textWidth(current)
        if !references.isEmpty {
            current.append(plain(","))
            currentWidth += try textWidth(plain(","))
        }
        let spaceWidth = try textWidth(plain(" "))
        for (position, reference) in references.enumerated() {
            registerPageDestination(forPageIndex: reference.targetPage)
            var unit = [PDFTextRun(
                text: reference.text,
                font: font,
                size: size,
                color: linkStyle.color,
                linkDestination: "#\(pageDestinationName(forPageIndex: reference.targetPage))",
            )]
            if position < references.count - 1 {
                unit.append(plain(","))
            }
            let unitWidth = try textWidth(unit)
            if currentWidth + spaceWidth + unitWidth > width {
                lines.append(current)
                current = unit
                currentWidth = unitWidth
            } else {
                current.append(plain(" "))
                current.append(contentsOf: unit)
                currentWidth += spaceWidth + unitWidth
            }
        }
        lines.append(current)

        let element = beginStructureElement(.paragraph)
        defer { endStructureElement(element) }
        for (lineIndex, line) in lines.enumerated() {
            ensureSpace(lineHeight)
            try drawRuns(line, x: x + (lineIndex == 0 ? 0 : hangingIndent), y: y)
            y -= lineHeight
        }
    }

    private mutating func renderFootnoteSection(_ footnotes: [ResolvedFootnote]) throws {
        guard !footnotes.isEmpty else {
            return
        }

        let footnoteStyle = style(for: .footnote)
        let titleSize = options.baseFontSize * 0.95
        let titleLineHeight = titleSize * 1.35
        ensureSpace(titleLineHeight * 3)
        if y < pageTopY - 1 {
            y -= options.baseFontSize * 0.5
        }

        let artifact = beginArtifactIfTagged()
        currentPage.drawLine(
            x1: options.margins.left,
            y1: y,
            x2: options.margins.left + min(contentWidth, 120),
            y2: y,
            width: 0.5,
            color: footnoteStyle.borderColor ?? footnoteStyle.color,
        )
        endMarkedContentIfNeeded(artifact)
        y -= titleLineHeight

        let titleElement = beginStructureElement(.paragraph)
        try drawRuns(
            [PDFTextRun(text: "Footnotes", font: .helveticaBold, size: titleSize, color: footnoteStyle.color)],
            x: options.margins.left,
            y: y,
        )
        endStructureElement(titleElement)
        y -= titleLineHeight

        for footnote in footnotes {
            try renderFootnote(footnote)
        }
    }

    private mutating func renderFootnote(_ footnote: ResolvedFootnote) throws {
        let footnoteStyle = style(for: .footnote)
        let linkStyle = style(for: .link)
        let size = fontSize(for: .footnote)
        let lineHeight = size * footnoteStyle.lineHeightMultiplier
        let labelWidth = max(22, size * 2.2)
        let bodyX = options.margins.left + labelWidth
        let bodyWidth = max(1, contentWidth - labelWidth)
        let blocks = footnote.blocks.isEmpty ? [.paragraph([])] : footnote.blocks
        let firstRuns = try flatten(
            footnoteInlines(for: blocks[0]),
            font: standardFont(for: footnoteStyle.fontRole),
            size: size,
            color: footnoteStyle.color,
        )
        let firstLines = try wrappedLines(firstRuns, maxWidth: bodyWidth)

        ensureSpace(lineHeight)
        addNamedDestination(footnote.definitionDestinationName, x: options.margins.left, y: y + size)
        let element = beginStructureElement(.paragraph)
        try drawRuns(
            [
                PDFTextRun(
                    text: "\(footnote.number).",
                    font: standardFont(for: footnoteStyle.fontRole),
                    size: size,
                    color: linkStyle.color,
                    underline: linkStyle.underline,
                    linkDestination: "#\(footnote.referenceDestinationName)",
                ),
            ],
            x: options.margins.left,
            y: y,
            applyBidi: false,
        )
        if let firstLine = firstLines.first {
            try drawRuns(firstLine, x: bodyX, y: y, maxWidth: bodyWidth)
        }
        y -= lineHeight

        for line in firstLines.dropFirst() {
            ensureSpace(lineHeight)
            try drawRuns(line, x: bodyX, y: y, maxWidth: bodyWidth)
            y -= lineHeight
        }
        endStructureElement(element)

        for block in blocks.dropFirst() {
            try renderFootnoteBlock(block, x: bodyX, maxWidth: bodyWidth, size: size, lineHeight: lineHeight)
        }
        y -= max(2, size * footnoteStyle.spacingAfterMultiplier)
    }

    private mutating func renderFootnoteBlock(
        _ block: MarkdownBlock,
        x: Double,
        maxWidth: Double,
        size: Double,
        lineHeight: Double,
    ) throws {
        let element = beginStructureElement(.paragraph)
        defer { endStructureElement(element) }
        let footnoteStyle = style(for: .footnote)
        try drawWrapped(
            flatten(footnoteInlines(for: block), font: standardFont(for: footnoteStyle.fontRole), size: size, color: footnoteStyle.color),
            x: x,
            maxWidth: maxWidth,
            lineHeight: lineHeight,
        )
    }

    private func footnoteInlines(for block: MarkdownBlock) -> [MarkdownInline] {
        switch block {
        case let .heading(_, content), let .paragraph(content):
            content
        case let .codeBlock(_, code):
            [.code(code)]
        case let .displayMath(math):
            [.inlineMath(MarkdownMath(source: math.source, mode: .inline))]
        case let .html(html):
            [.text(html)]
        case let .blockQuote(blocks):
            [.text(blocks.map(plainText).joined(separator: " "))]
        case let .unorderedList(items), let .orderedList(_, items):
            [.text(items.flatMap(\.blocks).map(plainText).joined(separator: " "))]
        case let .table(table):
            [.text((table.headers + table.rows.flatMap(\.self)).map { plainText($0) }.joined(separator: " "))]
        case .thematicBreak, .pageBreak, .footnoteDefinition:
            []
        }
    }

    private mutating func renderList(
        items: [MarkdownBlock.ListItem],
        start: Int?,
    ) throws {
        let listElement = beginStructureElement(
            .list,
            attributes: PDFTaggedContent.Attributes(
                listNumbering: start == nil ? .unordered : .ordered,
            ),
        )
        defer { endStructureElement(listElement) }

        var number = start ?? 0
        listDepth += 1
        defer { listDepth -= 1 }
        let keepsItems = options.keepTogether.contains(.listItems)
        for item in items {
            let label = start == nil ? nil : number
            if keepsItems {
                try keepTogether { layout in
                    try layout.renderListItem(item, number: label)
                }
            } else {
                try renderListItem(item, number: label)
            }
            number += 1
        }
        y -= listTrailingSpacing
    }

    /// Draws one list item: its marker, then its blocks, indented. `number` is the
    /// label of an ordered item, nil for a bullet or a task.
    private mutating func renderListItem(_ item: MarkdownBlock.ListItem, number: Int?) throws {
        let itemElement = beginStructureElement(.listItem)
        ensureSpace(leadingBlockHeight(of: item))
        if let number {
            let labelElement = beginStructureElement(.listLabel)
            let markerStyle = style(for: .listMarker)
            try drawRuns(
                [
                    PDFTextRun(
                        text: "\(number).",
                        font: standardFont(for: markerStyle.fontRole),
                        size: fontSize(for: .listMarker),
                        color: markerStyle.color,
                    ),
                ],
                x: options.margins.left,
                y: y,
                applyBidi: false,
            )
            endStructureElement(labelElement)
        } else if let checkbox = item.checkbox {
            let labelElement = beginStructureElement(.listLabel)
            drawTaskCheckbox(checkbox, x: options.margins.left, baselineY: y)
            endStructureElement(labelElement)
        } else {
            // Unordered item. Draw the bullet through the same `.listMarker`
            // role the ordered branch uses, so a theme styles both alike.
            let markerStyle = style(for: .listMarker)
            let markerFont = standardFont(for: markerStyle.fontRole)
            if let marker = unorderedMarkerText(for: markerFont) {
                let labelElement = beginStructureElement(.listLabel)
                try drawRuns(
                    [
                        PDFTextRun(
                            text: marker,
                            font: markerFont,
                            size: fontSize(for: .listMarker),
                            color: markerStyle.color,
                        ),
                    ],
                    x: options.margins.left,
                    y: y,
                    applyBidi: false,
                )
                endStructureElement(labelElement)
            }
        }
        let savedLeft = options.margins.left
        indentLeftMargin(by: 24)
        let bodyElement = beginStructureElement(.listBody)
        for block in item.blocks {
            try render(block)
        }
        endStructureElement(bodyElement)
        options.margins.left = savedLeft
        endStructureElement(itemElement)
    }

    /// The unordered-list marker the font bound to `font` can actually draw, or
    /// `nil` when it can draw none of the candidates.
    ///
    /// U+2022 is the intended marker, with an ASCII hyphen as the fallback. The
    /// two font profiles disagree about who is authoritative:
    ///
    /// - Base-14 (no embedded entry): WinAnsiEncoding maps U+2022 to `0x95`, so
    ///   the bullet is drawable. `PDFEmbeddedFontCatalog.covers` answers `false`
    ///   here because there is no embedded entry at all, so it must not be the
    ///   authority on this path. `PDFTextEncoding` is.
    /// - Embedded TrueType: the caller's font may lack both glyphs. A font
    ///   carrying only Hebrew, Arabic, Latin capitals and a little punctuation
    ///   has neither U+2022 nor `-`, and mapping either through it throws
    ///   `TrueTypeGlyphMappingError.missingGlyph`.
    ///
    /// Returning `nil` keeps the item's 24pt indent and omits only the
    /// decorative glyph, which is what the renderer did for every unordered
    /// list before markers existed. A marker is presentation, not content: the
    /// list is still tagged `/L`, so assistive technology is unaffected.
    private func unorderedMarkerText(for font: StandardFont) -> String? {
        let candidates = ["\u{2022}", "-"]
        guard embeddedFonts.entry(for: font) != nil else {
            // No embedded font is bound to this role, so the marker would be drawn
            // with an unembedded base-14 font. PDF/UA-1 and PDF/A-2a forbid those,
            // and `PDFDocumentWriter.validateConformance` fails the whole document
            // when one is used. A marker is presentation, not content: omit it
            // rather than refuse to render a document that rendered before.
            guard !options.conformance.isEnabled else {
                return nil
            }
            return candidates.first { candidate in
                candidate.unicodeScalars.allSatisfy(PDFTextEncoding.isRepresentable)
            }
        }
        return candidates.first { embeddedFonts.covers($0, font: font) }
    }

    /// Height the list item's first block will occupy, used to reserve space
    /// before the marker is drawn.
    ///
    /// Every item body is a paragraph, except a lone image, which
    /// ``renderStandaloneImage(_:)`` draws as a figure after calling
    /// `ensureSpace(drawHeight)` of its own. Reserving only `bodyLineHeight` for
    /// such an item strands the marker at the bottom of one page while its image
    /// starts the next. Reserve the figure's real height instead.
    ///
    /// The width available to the body is `contentWidth - 24`, because
    /// ``renderList(items:start:)`` indents `margins.left` by 24 after the marker.
    private mutating func leadingBlockHeight(of item: MarkdownBlock.ListItem) -> Double {
        guard case let .paragraph(content)? = item.blocks.first,
              content.count == 1,
              case let .image(_, source, _) = content[0],
              !source.hasPrefix("http://"),
              !source.hasPrefix("https://"),
              let image = try? loadImage(source: source)
        else {
            return bodyLineHeight
        }

        let maxWidth = max(1, contentWidth - 24)
        let maxHeight = imageMaxHeight
        let scale = min(1, maxWidth / Double(image.width), maxHeight / Double(image.height))
        return Double(image.height) * scale
    }

    /// Fills a block quote's background behind every page the quote occupies.
    ///
    /// The quote's height is unknown until its blocks have rendered, and by then its
    /// text is already in the content stream. So the fill is *inserted* just after
    /// the page background rather than appended. The rectangle is confined to the
    /// quote's own vertical extent, so it cannot cover content drawn above the quote
    /// on the same page.
    ///
    /// Nested quotes stack correctly: the outer quote finishes last and therefore
    /// inserts last, landing beneath the inner quote's fill.
    private func drawBlockQuoteBackground(
        color: PDFColor?,
        x: Double,
        width: Double,
        firstPage: Int,
        topY: Double,
        lastPage: Int,
        bottomY: Double,
    ) {
        guard let color, firstPage <= lastPage, width > 0 else {
            return
        }

        let isTagged = taggedContentBuilder != nil
        for page in firstPage ... lastPage {
            let segmentTop = page == firstPage ? topY : pageTopY
            let segmentBottom = page == lastPage ? bottomY : options.margins.bottom
            guard segmentTop > segmentBottom else {
                continue
            }
            pages[page].insertBackgroundRectangle(
                x: x,
                y: segmentBottom,
                width: width,
                height: segmentTop - segmentBottom,
                fill: color,
                asArtifact: isTagged,
            )
        }
    }

    /// Strokes a block quote's left rule down every page the quote occupies.
    ///
    /// Drawn after the quote's content rather than before it, which is safe: the
    /// rule sits in the 14pt gutter the quote opened, so it can never paint over
    /// text. A background fill could not be handled this way, because it would
    /// cover what is already drawn, and is therefore still ignored.
    ///
    /// A quote spanning pages gets one segment per page: from `topY` on the first
    /// and from the top margin on later ones, down to `bottomY` on the last and to
    /// the bottom margin on earlier ones.
    private func drawBlockQuoteRule(
        color: PDFColor?,
        x: Double,
        firstPage: Int,
        topY: Double,
        lastPage: Int,
        bottomY: Double,
    ) {
        guard let color, firstPage <= lastPage else {
            return
        }

        let isTagged = taggedContentBuilder != nil
        for page in firstPage ... lastPage {
            let segmentTop = page == firstPage ? topY : pageTopY
            let segmentBottom = page == lastPage ? bottomY : options.margins.bottom
            guard segmentTop > segmentBottom else {
                continue
            }
            // Decoration, not content. `beginArtifactIfTagged` only ever marks
            // `currentPage`, and this rule is stroked onto earlier pages too, so
            // mark each page directly. Untagged, it would fail PDF/UA-1.
            if isTagged {
                pages[page].beginArtifact()
            }
            pages[page].drawLine(
                x1: x,
                y1: segmentTop,
                x2: x,
                y2: segmentBottom,
                width: 2,
                color: color,
            )
            if isTagged {
                pages[page].endMarkedContent()
            }
        }
    }

    /// Records that content has been drawn inside every currently open quote, so
    /// their rule origins stop following page breaks.
    private mutating func markBlockQuoteContentDrawn() {
        guard !blockQuoteFrames.isEmpty else {
            return
        }
        for index in blockQuoteFrames.indices where !blockQuoteFrames[index].hasDrawn {
            blockQuoteFrames[index].hasDrawn = true
        }
    }

    private mutating func drawTaskCheckbox(
        _ checkbox: MarkdownBlock.ListItem.Checkbox,
        x: Double,
        baselineY: Double,
    ) {
        markBlockQuoteContentDrawn()
        let size = max(7, options.baseFontSize * 0.72)
        let boxX = x + max(0, (16 - size) / 2)
        let boxY = baselineY - size * 0.2
        let markerColor = style(for: .listMarker).color
        let marked = beginMarkedContentForCurrentElement()
        currentPage.drawRectangle(
            x: boxX,
            y: boxY,
            width: size,
            height: size,
            stroke: markerColor,
            fill: nil,
        )

        if checkbox == .checked {
            currentPage.drawPolyline(
                points: [
                    PDFPageCanvas.Point(x: boxX + size * 0.2, y: boxY + size * 0.48),
                    PDFPageCanvas.Point(x: boxX + size * 0.43, y: boxY + size * 0.22),
                    PDFPageCanvas.Point(x: boxX + size * 0.82, y: boxY + size * 0.78),
                ],
                width: 1.0,
                color: markerColor,
            )
        }
        endMarkedContentIfNeeded(marked)
    }

    private mutating func renderCodeBlock(_ code: String, info: String? = nil) throws {
        let codeElement = beginStructureElement(.code)
        defer { endStructureElement(codeElement) }

        let codeStyle = style(for: .codeBlock)
        let size = fontSize(for: .codeBlock)
        let lineHeight = size * codeStyle.lineHeightMultiplier
        let padding = codeBlockPadding
        let codeAreaWidth = max(1, contentWidth - padding * 2)
        var syntaxHighlighter = syntaxHighlighter(for: info)
        let sourceLines = code.split(separator: "\n", omittingEmptySubsequences: false)
        let lines = try sourceLines
            .map { line in
                let displayText = expandCodeTabs(String(line))
                return try wrappedLines(
                    codeLineRuns(
                        displayText,
                        size: size,
                        syntaxHighlighter: &syntaxHighlighter,
                    ),
                    maxWidth: codeAreaWidth,
                )
            }
            .flatMap(\.self)
        let drawableLines = lines.isEmpty ? [[]] : lines
        var lineOffset = 0

        while lineOffset < drawableLines.count {
            ensureSpace(lineHeight + padding * 2)
            let lineCount = min(
                drawableLines.count - lineOffset,
                codeBlockLineCapacity(lineHeight: lineHeight, padding: padding),
            )
            try renderCodeBlockFragment(
                Array(drawableLines[lineOffset ..< lineOffset + lineCount]),
                size: size,
                lineHeight: lineHeight,
                padding: padding,
            )
            lineOffset += lineCount
            if lineOffset < drawableLines.count {
                startNewPage()
            }
        }

        y -= codeBlockFollowingGap
    }

    private mutating func renderDisplayMath(_ math: MarkdownMath) throws {
        let mathElement = beginStructureElement(.paragraph)
        defer { endStructureElement(mathElement) }

        let style = style(for: .displayMath)
        let size = fontSize(for: .displayMath)
        let topSpacing = options.baseFontSize * style.spacingBeforeMultiplier
        let bottomSpacing = options.baseFontSize * style.spacingAfterMultiplier

        do {
            let parsed = try MathParser().parse(math.source)
            let layout = try mathLayout(for: style)
            let box = try layout.layout(parsed.root, size: size, displayStyle: true)
            let totalHeight = topSpacing + box.height + box.depth + bottomSpacing
            ensureSpace(totalHeight)
            y -= topSpacing
            let baselineY = y - box.height
            let x = options.margins.left + max(0, (contentWidth - box.width) / 2)

            currentPage.beginActualText(parsed.linearizedText)
            defer { currentPage.endMarkedContent() }
            try drawMathBox(box, x: x, baselineY: baselineY)
            // The cursor is the next line's baseline, and its glyphs rise an ascender above it: the drop carries that ascender, so the
            // next line does not touch the formula's lowest ink (a sum's lower limit, a fraction's denominator).
            let nextLineAscender = fontSize(for: listDepth > 0 ? .list : .paragraph) * 0.75
            y = baselineY - box.depth - bottomSpacing - nextLineAscender
        } catch let error as MarkdownPDFError {
            throw error
        } catch {
            let fallback = math.delimitedSource
            let runs = [
                PDFTextRun(
                    text: fallback,
                    font: standardFont(for: style.fontRole),
                    size: size,
                    color: style.color,
                ),
            ]
            let lineHeight = size * style.lineHeightMultiplier
            ensureSpace(topSpacing + lineHeight + bottomSpacing)
            y -= topSpacing
            try drawWrapped(runs, x: options.margins.left, maxWidth: contentWidth, lineHeight: lineHeight)
            y -= bottomSpacing
        }
    }

    private mutating func drawMathBox(
        _ box: MathBox,
        x: Double,
        baselineY: Double,
    ) throws {
        markBlockQuoteContentDrawn()
        let marked = beginMarkedContentForCurrentElement()
        defer { endMarkedContentIfNeeded(marked) }

        for element in box.elements {
            switch element {
            case let .text(run, offsetX, offsetY):
                try currentPage.drawTextRun(
                    PDFTextRun(run, face: mathFace),
                    x: x + offsetX,
                    y: baselineY + offsetY,
                    fontSet: options.fontSet,
                    embeddedFonts: embeddedFonts,
                )
            case let .rule(offsetX, offsetY, width, height, color):
                currentPage.drawRectangle(
                    x: x + offsetX,
                    y: baselineY + offsetY,
                    width: width,
                    height: height,
                    stroke: nil,
                    fill: color.pdfColor,
                )
            case let .line(x1, y1, x2, y2, thickness, color):
                currentPage.drawLine(
                    x1: x + x1,
                    y1: baselineY + y1,
                    x2: x + x2,
                    y2: baselineY + y2,
                    width: thickness,
                    color: color.pdfColor,
                )
            }
        }
    }

    private func syntaxHighlighter(for info: String?) -> SourceCodeSyntaxHighlighter? {
        guard options.codeSyntaxHighlighting.isEnabled,
              let language = SourceCodeLanguage(hint: info)
        else {
            return nil
        }

        return SourceCodeSyntaxHighlighter(language: language)
    }

    private func codeLineRuns(
        _ line: String,
        size: Double,
        syntaxHighlighter: inout SourceCodeSyntaxHighlighter?,
    ) -> [PDFTextRun] {
        guard var highlighter = syntaxHighlighter else {
            let codeStyle = style(for: .codeBlock)
            return [PDFTextRun(text: line, font: standardFont(for: codeStyle.fontRole), size: size, color: codeStyle.color)]
        }

        let tokens = highlighter.tokens(for: line)
        syntaxHighlighter = highlighter
        let codeStyle = style(for: .codeBlock)
        return tokens.map { token in
            PDFTextRun(
                text: token.text,
                font: standardFont(for: codeStyle.fontRole),
                size: size,
                color: color(for: token.kind),
            )
        }
    }

    private func color(for tokenKind: SourceCodeTokenKind) -> PDFColor {
        options.theme.codeSyntax.color(for: tokenKind)
    }

    private func isMermaidCodeBlock(_ info: String?) -> Bool {
        codeBlockLanguage(info) == "mermaid"
    }

    private func isChartCodeBlock(_ info: String?) -> Bool {
        codeBlockLanguage(info) == "chart"
    }

    private func isVerticalCodeBlock(_ info: String?) -> Bool {
        let language = codeBlockLanguage(info)
        return language == "vertical" || language == "tategaki"
    }

    /// Renders a fenced `vertical` block as top-to-bottom (tategaki) CJK: glyphs stack down
    /// a line from the top of the page, lines advance right to left, and the run flows onto
    /// further pages when it fills one. The `vert` feature gives brackets and the
    /// ideographic comma and full stop their vertical forms; ideographs stand upright.
    /// Without an embedded (CJK-covering) font there is nothing to shape vertically, so the
    /// text falls back to an ordinary code block rather than being lost.
    private mutating func renderVerticalBlock(_ code: String) throws {
        let text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphStyle = style(for: .paragraph)
        let font = standardFont(for: paragraphStyle.fontRole)
        guard !text.isEmpty, let entry = embeddedFonts.entry(for: font) else {
            try renderCodeBlock(code, info: nil)
            return
        }
        let size = fontSize(for: .paragraph)
        let shaper = VerticalTextShaper(fontData: entry.resource.fontProgram, metadata: entry.resource.metadata)
        // A source line is a vertical line: each becomes its own column. A font without
        // vertical metrics, or one that cannot draw any of the text (a Latin-only face
        // handed a CJK block maps everything to `.notdef`), is not a vertical setup; the
        // text falls back to a code block rather than being lost as tofu.
        let lines = try text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { try shaper.shape($0.trimmingCharacters(in: .whitespaces), fontSize: size) }
        let glyphCount = lines.reduce(0) { $0 + $1.count }
        guard shaper.hasVerticalMetrics, lines.contains(where: { line in line.contains { $0.glyphID != 0 } }) else {
            try renderCodeBlock(code, info: nil)
            return
        }
        guard glyphCount > 0 else {
            return
        }
        let origin = shaper.verticalOrigin(fontSize: size)
        let unitsPerEm = Double(entry.resource.metadata.head.unitsPerEm)
        let scale = unitsPerEm > 0 ? size / unitsPerEm : 0
        let columnStep = size * 1.6 // one em plus inter-line gap

        // A vertical block takes the whole page region; start it on a fresh page.
        if y < pageTopY - 1 {
            startNewPage()
        }
        let topY = pageTopY
        let bottomY = options.margins.bottom
        let firstColumnCenter = options.pageSize.width - options.margins.right - size / 2

        var pageGlyphs: [VerticalTextShaper.VerticalGlyph] = []
        var pagePositions: [PDFPageCanvas.Point] = []
        var columnCenter = firstColumnCenter
        var penY = topY - origin

        func flushPage() throws {
            guard !pageGlyphs.isEmpty else {
                return
            }
            let element = beginStructureElement(.paragraph)
            defer { endStructureElement(element) }
            let marked = beginMarkedContentForCurrentElement()
            defer { endMarkedContentIfNeeded(marked) }
            let mapping = try shaper.mapping(for: pageGlyphs, fontSize: size)
            try currentPage.drawVerticalText(
                mapping: mapping,
                positions: pagePositions,
                fontResource: entry.resource,
                fontSize: size,
                color: paragraphStyle.color,
            )
            pageGlyphs = []
            pagePositions = []
        }

        func advanceColumn() throws {
            columnCenter -= columnStep
            penY = topY - origin
            if columnCenter < options.margins.left + size / 2 {
                try flushPage()
                startNewPage()
                columnCenter = firstColumnCenter
                penY = topY - origin
            }
        }

        var isFirstLine = true
        for line in lines {
            if !isFirstLine {
                try advanceColumn()
            }
            isFirstLine = false
            for glyph in line {
                if penY < bottomY {
                    try advanceColumn()
                }
                let advanceWidth = Double(glyph.advanceWidth) * scale
                pageGlyphs.append(glyph)
                pagePositions.append(PDFPageCanvas.Point(x: columnCenter - advanceWidth / 2, y: penY))
                penY -= glyph.advance
            }
        }
        try flushPage()
        y = bottomY
    }

    private func codeBlockLanguage(_ info: String?) -> String? {
        guard let language = info?
            .split(whereSeparator: \.isWhitespace)
            .first?
            .lowercased()
        else {
            return nil
        }

        return language
    }

    private mutating func renderMermaidBlock(_ code: String) throws {
        if ChartBlock.isMermaidPieCandidate(code) {
            switch ChartBlock.parseMermaidPie(code) {
            case let .chart(chart):
                try renderChart(chart, sourceCode: code, fallbackPrefix: "Unsupported Mermaid chart")
            case let .unsupported(reason):
                try renderUnsupportedMermaid(reason: "unsupported Mermaid pie chart: \(reason)", code: code)
            }
            return
        }

        switch MermaidDiagram.parse(code) {
        case let .diagram(diagram):
            switch try mermaidRenderPlan(for: diagram) {
            case let .plan(plan):
                ensureSpace(plan.height + 12)
                let figureElement = beginStructureElement(
                    .figure,
                    attributes: PDFTaggedContent.Attributes(alternateDescription: "Mermaid diagram"),
                )
                let marked = beginMarkedContentForCurrentElement()
                try drawMermaidPlan(plan)
                endMarkedContentIfNeeded(marked)
                endStructureElement(figureElement)
                y -= plan.height + figureTrailingSpacing
            case let .fallback(reason):
                try renderUnsupportedMermaid(reason: reason, code: code)
            }
        case let .unsupported(reason):
            try renderUnsupportedMermaid(reason: reason, code: code)
        }
    }

    private mutating func renderUnsupportedMermaid(reason: String, code: String) throws {
        try renderCodeBlock("Unsupported Mermaid diagram: \(reason)\n\(code)")
    }

    private mutating func renderChartFenceBlock(_ code: String) throws {
        switch ChartBlock.parseChartFence(code) {
        case let .chart(chart):
            try renderChart(chart, sourceCode: code, fallbackPrefix: "Unsupported chart")
        case let .unsupported(reason):
            try renderCodeBlock("Unsupported chart: \(reason)\n\(code)")
        }
    }

    private mutating func renderChart(
        _ chart: ChartBlock,
        sourceCode: String,
        fallbackPrefix: String,
    ) throws {
        switch try chartRenderPlan(for: chart) {
        case let .plan(plan):
            ensureSpace(plan.height + 12)
            switch try chartRenderPlan(for: chart) {
            case let .plan(positionedPlan):
                let figureElement = beginStructureElement(
                    .figure,
                    attributes: PDFTaggedContent.Attributes(
                        alternateDescription: chartAlternateDescription(positionedPlan.chart),
                    ),
                )
                let marked = beginMarkedContentForCurrentElement()
                try drawChartPlan(positionedPlan)
                endMarkedContentIfNeeded(marked)
                endStructureElement(figureElement)
                y -= positionedPlan.height + figureTrailingSpacing
            case let .fallback(reason):
                try renderCodeBlock("\(fallbackPrefix): \(reason)\n\(sourceCode)")
            }
        case let .fallback(reason):
            try renderCodeBlock("\(fallbackPrefix): \(reason)\n\(sourceCode)")
        }
    }

    private func chartAlternateDescription(_ chart: ChartBlock) -> String {
        if let title = chart.title, !title.isEmpty {
            return title
        }
        return switch chart.kind {
        case .pie:
            "Pie chart"
        case .bar:
            "Bar chart"
        case .line:
            "Line chart"
        case .scatter:
            "Scatter chart"
        }
    }

    private func chartRenderPlan(for chart: ChartBlock) throws -> ChartRenderPlanResult {
        guard contentWidth >= 180 else {
            return .fallback("content area is too narrow for native chart rendering")
        }

        let height = min(contentHeight, max(190, min(260, contentWidth * 0.55)))
        guard height >= 170 else {
            return .fallback("content area is too short for native chart rendering")
        }
        guard chart.series.count <= chartPalette.count else {
            return .fallback("too many series for the portable chart palette")
        }
        if let title = chart.title,
           try textWidth(PDFTextRun(text: title, font: .helveticaBold, size: chartTitleSize)) > contentWidth - 16
        {
            return .fallback("chart title is wider than the content area")
        }
        for series in chart.series {
            guard !series.name.isEmpty else {
                return .fallback("series names must not be empty")
            }
        }
        for label in chart.categories {
            guard !label.isEmpty else {
                return .fallback("category labels must not be empty")
            }
        }

        switch chart.kind {
        case .pie:
            return try pieChartRenderPlan(for: chart, height: height)
        case .bar, .line, .scatter:
            return try cartesianChartRenderPlan(for: chart, height: height)
        }
    }

    private func pieChartRenderPlan(for chart: ChartBlock, height: Double) throws -> ChartRenderPlanResult {
        guard let series = chart.series.first, !series.points.isEmpty else {
            return .fallback("pie chart has no slices")
        }
        let titleHeight = chart.title == nil ? 8.0 : 26.0
        let legendWidth = try max(92, min(150, widestChartLabelWidth(chart.categories) + 24))
        let plotWidth = contentWidth - legendWidth - 18
        let radius = min(plotWidth / 2 - 8, (height - titleHeight - 18) / 2)
        guard radius >= 42 else {
            return .fallback("pie chart leaves too little room for slices and legend")
        }

        return .plan(ChartRenderPlan(
            chart: chart,
            height: height,
            plotFrame: nil,
            xTicks: [],
            yTicks: [],
            xDomain: (0, 0),
            yDomain: (0, 0),
            pieRadius: radius,
            legendWidth: legendWidth,
        ))
    }

    private func cartesianChartRenderPlan(for chart: ChartBlock, height: Double) throws -> ChartRenderPlanResult {
        let allPoints = chart.series.flatMap(\.points)
        guard !allPoints.isEmpty else {
            return .fallback("chart has no data points")
        }

        let yValues = allPoints.map(\.y) + (chart.kind == .bar ? [0] : [])
        let yTicks = niceChartTicks(min: yValues.min() ?? 0, max: yValues.max() ?? 1, targetCount: 5)
        guard let yFirst = yTicks.first, let yLast = yTicks.last, yLast > yFirst else {
            return .fallback("chart y axis could not be scaled")
        }
        let yLabelWidth = try max(34, yTicks.map { try chartTextWidth(formatChartNumber($0)) }.max() ?? 34)
        let leftAxisWidth = min(max(38, yLabelWidth + 10), 68)
        let titleHeight = chart.title == nil ? 8.0 : 26.0
        let legendHeight = 30.0
        let bottomAxisHeight = chart.xLabel == nil ? 34.0 : 48.0
        // The y-axis title has a row of its own between the legend and the plot, over the top gridline, so it never runs through the first bar.
        let yTitleHeight = chart.yLabel == nil ? 0.0 : chartLabelSize + 6
        let plotFrame = ChartFrame(
            left: options.margins.left + leftAxisWidth,
            top: y - titleHeight - legendHeight - yTitleHeight,
            width: contentWidth - leftAxisWidth - 12,
            height: height - titleHeight - legendHeight - yTitleHeight - bottomAxisHeight,
        )
        guard plotFrame.width >= 96, plotFrame.height >= 72 else {
            return .fallback("chart plot area is too small")
        }

        let xTicks: [Double]
        let xDomain: (min: Double, max: Double)
        switch chart.kind {
        case .bar:
            guard !chart.categories.isEmpty else {
                return .fallback("bar charts require categories")
            }
            let bandWidth = plotFrame.width / Double(chart.categories.count)
            for category in chart.categories {
                if try chartTextWidth(category) > bandWidth * 0.92 {
                    return .fallback("category label `\(category)` would overlap adjacent labels")
                }
            }
            xTicks = chart.series[0].points.map(\.x)
            xDomain = (0, Double(max(0, chart.categories.count - 1)))
        case .line:
            let values = allPoints.map(\.x)
            xDomain = expandedDomain(min: values.min() ?? 0, max: values.max() ?? 1)
            xTicks = chart.categories.isEmpty ? niceChartTicks(min: xDomain.min, max: xDomain.max, targetCount: 5) : chart.series[0].points.map(\.x)
            if !chart.categories.isEmpty {
                let bandWidth = plotFrame.width / Double(chart.categories.count)
                for category in chart.categories where try chartTextWidth(category) > bandWidth * 0.92 {
                    return .fallback("category label `\(category)` would overlap adjacent labels")
                }
            }
        case .scatter:
            let values = allPoints.map(\.x)
            let domain = expandedDomain(min: values.min() ?? 0, max: values.max() ?? 1)
            xTicks = niceChartTicks(min: domain.min, max: domain.max, targetCount: 5)
            xDomain = (xTicks.first ?? domain.min, xTicks.last ?? domain.max)
            if let reason = try chartTickOverlapReason(ticks: xTicks, domain: xDomain, plotFrame: plotFrame) {
                return .fallback(reason)
            }
        case .pie:
            xTicks = []
            xDomain = (0, 0)
        }

        return .plan(ChartRenderPlan(
            chart: chart,
            height: height,
            plotFrame: plotFrame,
            xTicks: xTicks,
            yTicks: yTicks,
            xDomain: xDomain,
            yDomain: (yFirst, yLast),
            pieRadius: nil,
            legendWidth: nil,
        ))
    }

    private func chartTickOverlapReason(
        ticks: [Double],
        domain: (min: Double, max: Double),
        plotFrame: ChartFrame,
    ) throws -> String? {
        guard ticks.count > 1, domain.max > domain.min else {
            return nil
        }
        let positions = ticks.map { plotFrame.left + ($0 - domain.min) / (domain.max - domain.min) * plotFrame.width }
        let widths = try ticks.map { try chartTextWidth(formatChartNumber($0)) }
        for index in 1 ..< ticks.count {
            let previousRight = positions[index - 1] + widths[index - 1] / 2
            let currentLeft = positions[index] - widths[index] / 2
            if currentLeft < previousRight + 4 {
                return "x axis tick labels would overlap"
            }
        }
        return nil
    }

    private mutating func drawChartPlan(_ plan: ChartRenderPlan) throws {
        markBlockQuoteContentDrawn()
        let topY = y
        currentPage.drawRectangle(
            x: options.margins.left - 4,
            y: topY - plan.height,
            width: contentWidth + 8,
            height: plan.height,
            stroke: PDFColor(red: 0.72, green: 0.76, blue: 0.80),
            fill: PDFColor(red: 0.98, green: 0.985, blue: 0.99),
        )

        if let title = plan.chart.title {
            try drawChartText(
                title,
                x: options.margins.left + contentWidth / 2,
                y: topY - 17,
                font: .helveticaBold,
                size: chartTitleSize,
                alignment: .center,
            )
        }

        switch plan.chart.kind {
        case .pie:
            try drawPieChart(plan, topY: topY)
        case .bar:
            try drawBarChart(plan, topY: topY)
        case .line:
            try drawLineChart(plan, topY: topY)
        case .scatter:
            try drawScatterChart(plan, topY: topY)
        }
    }

    private mutating func drawPieChart(_ plan: ChartRenderPlan, topY: Double) throws {
        guard let radius = plan.pieRadius,
              let legendWidth = plan.legendWidth,
              let series = plan.chart.series.first
        else {
            return
        }

        let titleHeight = plan.chart.title == nil ? 8.0 : 26.0
        let centerX = options.margins.left + radius + 14
        let centerY = topY - titleHeight - (plan.height - titleHeight) / 2
        let total = series.points.reduce(0) { $0 + $1.y }
        var angle = Double.pi / 2

        for (index, point) in series.points.enumerated() {
            let sweep = -Double.pi * 2 * point.y / total
            let nextAngle = angle + sweep
            currentPage.drawPieSlice(
                centerX: centerX,
                centerY: centerY,
                radius: radius,
                startAngle: angle,
                endAngle: nextAngle,
                fill: chartPalette[index % chartPalette.count],
            )
            angle = nextAngle
        }

        let legendX = options.margins.left + contentWidth - legendWidth + 4
        var legendY = topY - titleHeight - 16
        for (index, point) in series.points.enumerated() {
            let color = chartPalette[index % chartPalette.count]
            currentPage.drawRectangle(x: legendX, y: legendY - 8, width: 9, height: 9, stroke: nil, fill: color)
            try drawChartText(
                "\(point.label ?? "") \(formatChartNumber(point.y))",
                x: legendX + 14,
                y: legendY - 7,
                size: chartLabelSize,
            )
            legendY -= 15
        }
    }

    private mutating func drawBarChart(_ plan: ChartRenderPlan, topY: Double) throws {
        guard let plotFrame = plan.plotFrame else {
            return
        }
        try drawCartesianBase(plan, plotFrame: plotFrame, topY: topY)

        let baselineY = chartY(0, domain: plan.yDomain, frame: plotFrame)
        let bandWidth = plotFrame.width / Double(plan.chart.categories.count)
        let groupWidth = bandWidth * 0.68
        let barWidth = max(2, groupWidth / Double(plan.chart.series.count))

        for (seriesIndex, series) in plan.chart.series.enumerated() {
            let color = chartPalette[seriesIndex % chartPalette.count]
            for (pointIndex, point) in series.points.enumerated() {
                let x = plotFrame.left
                    + Double(pointIndex) * bandWidth
                    + (bandWidth - groupWidth) / 2
                    + Double(seriesIndex) * barWidth
                let valueY = chartY(point.y, domain: plan.yDomain, frame: plotFrame)
                let y = min(baselineY, valueY)
                currentPage.drawRectangle(
                    x: x,
                    y: y,
                    width: max(1.5, barWidth - 1),
                    height: max(0.8, abs(valueY - baselineY)),
                    stroke: nil,
                    fill: color,
                )
            }
        }

        try drawCategoricalXAxis(categories: plan.chart.categories, plotFrame: plotFrame)
        try drawChartLegend(plan.chart.series.map(\.name), topY: topY)
    }

    private mutating func drawLineChart(_ plan: ChartRenderPlan, topY: Double) throws {
        guard let plotFrame = plan.plotFrame else {
            return
        }
        try drawCartesianBase(plan, plotFrame: plotFrame, topY: topY)

        for (seriesIndex, series) in plan.chart.series.enumerated() {
            let color = chartPalette[seriesIndex % chartPalette.count]
            let points = series.points.map {
                PDFPageCanvas.Point(
                    x: chartX($0.x, domain: plan.xDomain, frame: plotFrame),
                    y: chartY($0.y, domain: plan.yDomain, frame: plotFrame),
                )
            }
            currentPage.drawPolyline(points: points, width: 1.2, color: color)
            for point in points {
                currentPage.drawCircle(x: point.x, y: point.y, radius: 2.5, stroke: .white, fill: color)
            }
        }

        if plan.chart.categories.isEmpty {
            try drawNumericXAxis(ticks: plan.xTicks, domain: plan.xDomain, plotFrame: plotFrame)
        } else {
            try drawCategoricalXAxis(categories: plan.chart.categories, plotFrame: plotFrame)
        }
        try drawChartLegend(plan.chart.series.map(\.name), topY: topY)
    }

    private mutating func drawScatterChart(_ plan: ChartRenderPlan, topY: Double) throws {
        guard let plotFrame = plan.plotFrame else {
            return
        }
        try drawCartesianBase(plan, plotFrame: plotFrame, topY: topY)

        for (seriesIndex, series) in plan.chart.series.enumerated() {
            let color = chartPalette[seriesIndex % chartPalette.count]
            for point in series.points {
                let marker = PDFPageCanvas.Point(
                    x: chartX(point.x, domain: plan.xDomain, frame: plotFrame),
                    y: chartY(point.y, domain: plan.yDomain, frame: plotFrame),
                )
                if seriesIndex % 3 == 2 {
                    currentPage.drawPolygon(
                        points: [
                            PDFPageCanvas.Point(x: marker.x, y: marker.y + 3.2),
                            PDFPageCanvas.Point(x: marker.x - 3.2, y: marker.y - 2.8),
                            PDFPageCanvas.Point(x: marker.x + 3.2, y: marker.y - 2.8),
                        ],
                        stroke: .white,
                        fill: color,
                    )
                } else if seriesIndex % 3 == 1 {
                    currentPage.drawRectangle(
                        x: marker.x - 2.8,
                        y: marker.y - 2.8,
                        width: 5.6,
                        height: 5.6,
                        stroke: .white,
                        fill: color,
                    )
                } else {
                    currentPage.drawCircle(x: marker.x, y: marker.y, radius: 3, stroke: .white, fill: color)
                }
            }
        }

        try drawNumericXAxis(ticks: plan.xTicks, domain: plan.xDomain, plotFrame: plotFrame)
        try drawChartLegend(plan.chart.series.map(\.name), topY: topY)
    }

    private mutating func drawCartesianBase(
        _ plan: ChartRenderPlan,
        plotFrame: ChartFrame,
        topY _: Double,
    ) throws {
        for tick in plan.yTicks {
            let tickY = chartY(tick, domain: plan.yDomain, frame: plotFrame)
            currentPage.drawLine(
                x1: plotFrame.left,
                y1: tickY,
                x2: plotFrame.right,
                y2: tickY,
                width: 0.25,
                color: PDFColor(red: 0.84, green: 0.86, blue: 0.88),
            )
            try drawChartText(
                formatChartNumber(tick),
                x: plotFrame.left - 6,
                y: tickY - chartLabelSize * 0.35,
                size: chartLabelSize,
                color: .gray,
                alignment: .right,
            )
        }

        currentPage.drawLine(x1: plotFrame.left, y1: plotFrame.bottom, x2: plotFrame.left, y2: plotFrame.top, width: 0.65)
        currentPage.drawLine(x1: plotFrame.left, y1: plotFrame.bottom, x2: plotFrame.right, y2: plotFrame.bottom, width: 0.65)

        if let yLabel = plan.chart.yLabel {
            try drawChartText(
                yLabel,
                x: plotFrame.left,
                y: plotFrame.top + 6,
                size: chartLabelSize,
                color: .gray,
            )
        }
        if let xLabel = plan.chart.xLabel {
            try drawChartText(
                xLabel,
                x: plotFrame.left + plotFrame.width / 2,
                y: plotFrame.bottom - 36,
                size: chartLabelSize,
                color: .gray,
                alignment: .center,
            )
        }
    }

    private mutating func drawCategoricalXAxis(categories: [String], plotFrame: ChartFrame) throws {
        let bandWidth = plotFrame.width / Double(categories.count)
        for (index, rawCategory) in categories.enumerated() {
            let category = try truncatedChartLabel(rawCategory, maxWidth: min(80, bandWidth - 4))
            try drawChartText(
                category,
                x: plotFrame.left + Double(index) * bandWidth + bandWidth / 2,
                y: plotFrame.bottom - 13,
                size: chartLabelSize,
                color: .gray,
                alignment: .center,
            )
        }
    }

    private mutating func drawNumericXAxis(
        ticks: [Double],
        domain: (min: Double, max: Double),
        plotFrame: ChartFrame,
    ) throws {
        for tick in ticks {
            let tickX = chartX(tick, domain: domain, frame: plotFrame)
            currentPage.drawLine(
                x1: tickX,
                y1: plotFrame.bottom,
                x2: tickX,
                y2: plotFrame.top,
                width: 0.2,
                color: PDFColor(red: 0.88, green: 0.89, blue: 0.91),
            )
            try drawChartText(
                formatChartNumber(tick),
                x: tickX,
                y: plotFrame.bottom - 13,
                size: chartLabelSize,
                color: .gray,
                alignment: .center,
            )
        }
    }

    private mutating func drawChartLegend(_ labels: [String], topY: Double) throws {
        guard !labels.isEmpty else {
            return
        }

        let y = topY - (labels.count > 1 ? 39 : 33)
        let textX = options.margins.left + 18
        let spacer = "   "
        let spacerWidth = try chartTextWidth(spacer)
        var textCursor = textX
        var legendText = ""

        for (index, rawLabel) in labels.enumerated() {
            let label = try truncatedChartLabel(rawLabel, maxWidth: 92)
            let color = chartPalette[index % chartPalette.count]
            currentPage.drawRectangle(x: textCursor - 14, y: y - 7, width: 10, height: 8, stroke: nil, fill: color)
            let labelWidth = try chartTextWidth(label)
            textCursor += labelWidth
            legendText += label
            if index < labels.count - 1 {
                textCursor += spacerWidth
                legendText += spacer
            }
        }
        try drawChartText(legendText, x: textX, y: y - 6, size: chartLabelSize)
    }

    private mutating func drawChartText(
        _ text: String,
        x: Double,
        y: Double,
        font: StandardFont = .helvetica,
        size: Double? = nil,
        color: PDFColor = .black,
        alignment: ChartTextAlignment = .left,
    ) throws {
        let run = PDFTextRun(text: text, font: font, size: size ?? chartLabelSize, color: color)
        let width = try textWidth(run)
        let drawX = switch alignment {
        case .left:
            x
        case .center:
            x - width / 2
        case .right:
            x - width
        }
        try currentPage.drawTextRun(run, x: drawX, y: y, fontSet: options.fontSet, embeddedFonts: embeddedFonts)
    }

    private func chartX(_ value: Double, domain: (min: Double, max: Double), frame: ChartFrame) -> Double {
        guard domain.max > domain.min else {
            return frame.left
        }
        return frame.left + (value - domain.min) / (domain.max - domain.min) * frame.width
    }

    private func chartY(_ value: Double, domain: (min: Double, max: Double), frame: ChartFrame) -> Double {
        guard domain.max > domain.min else {
            return frame.bottom
        }
        return frame.bottom + (value - domain.min) / (domain.max - domain.min) * frame.height
    }

    private func niceChartTicks(min rawMin: Double, max rawMax: Double, targetCount: Int) -> [Double] {
        let domain = expandedDomain(min: rawMin, max: rawMax)
        let span = niceChartNumber(domain.max - domain.min, round: false)
        let step = niceChartNumber(span / Double(max(1, targetCount - 1)), round: true)
        let graphMin = floor(domain.min / step) * step
        let graphMax = ceil(domain.max / step) * step
        var ticks: [Double] = []
        var value = graphMin
        while value <= graphMax + step * 0.5, ticks.count < 20 {
            ticks.append(value)
            value += step
        }
        return ticks
    }

    private func niceChartNumber(_ value: Double, round: Bool) -> Double {
        guard value > 0 else {
            return 1
        }
        let exponent = floor(log10(value))
        let fraction = value / pow(10, exponent)
        let niceFraction: Double = if round {
            if fraction < 1.5 {
                1
            } else if fraction < 3 {
                2
            } else if fraction < 7 {
                5
            } else {
                10
            }
        } else if fraction <= 1 {
            1
        } else if fraction <= 2 {
            2
        } else if fraction <= 5 {
            5
        } else {
            10
        }
        return niceFraction * pow(10, exponent)
    }

    private func expandedDomain(min rawMin: Double, max rawMax: Double) -> (min: Double, max: Double) {
        if rawMax > rawMin {
            return (rawMin, rawMax)
        }
        let padding = max(1, abs(rawMin) * 0.1)
        return (rawMin - padding, rawMax + padding)
    }

    private func formatChartNumber(_ value: Double) -> String {
        guard value.isFinite else {
            return "-"
        }
        let absValue = abs(value)
        // `Int(value.rounded())` traps once the magnitude exceeds `Int.max` (~9.22e18).
        // Keep the plain-integer form for values that fit; render an integer-valued
        // magnitude too large for `Int` with a compact `%g` instead of trapping. The
        // 9.2e18 bound stays safely under `Int.max` and covers every realistic count.
        if abs(value.rounded() - value) < 0.0001 {
            return absValue < 9.2e18 ? "\(Int(value.rounded()))" : String(format: "%g", value)
        }
        if absValue >= 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }

    private func chartTextWidth(_ text: String) throws -> Double {
        try textWidth(PDFTextRun(text: text, font: .helvetica, size: chartLabelSize))
    }

    /// A version of `text` that fits within `maxWidth` at the chart label size, trimming
    /// characters and appending an ellipsis when needed. Used so an over-long legend or
    /// category label degrades gracefully instead of forcing the whole chart to fall back
    /// to source.
    private func truncatedChartLabel(_ text: String, maxWidth: Double) throws -> String {
        if try chartTextWidth(text) <= maxWidth {
            return text
        }
        let ellipsis = "\u{2026}"
        var characters = Array(text)
        while !characters.isEmpty {
            characters.removeLast()
            let candidate = String(characters).trimmingCharacters(in: .whitespaces) + ellipsis
            if try chartTextWidth(candidate) <= maxWidth {
                return candidate
            }
        }
        return ellipsis
    }

    private func widestChartLabelWidth(_ labels: [String]) throws -> Double {
        try labels.map { try chartTextWidth($0) }.max() ?? 0
    }

    private func mermaidRenderPlan(for diagram: MermaidDiagram) throws -> MermaidRenderPlanResult {
        // With groups, the diagram is laid out as its groups and the nodes outside them; each
        // group is then laid out inside its own frame.
        let outerDiagram = diagram.groups.isEmpty ? diagram : diagram.collapsedForLayout()
        let layers = outerDiagram.layers()
        let minimumScale = 0.55
        var scale = 1.0

        while true {
            let result: MermaidRenderPlanResult
            switch try measureMermaidNodes(diagram.nodes, scale: scale) {
            case let .fallback(reason):
                return .fallback(reason)
            case let .measurements(measurements):
                result = try mermaidRenderPlan(
                    diagram: diagram,
                    outerDirection: outerDiagram.direction,
                    layers: layers,
                    measurements: measurements,
                    scale: scale,
                )
            }

            // A diagram that overflows the page width or height is uniformly shrunk
            // (smaller font and boxes) and re-planned until it fits, rather than falling
            // back to source. Only overflow retries; other fallbacks pass through.
            if case let .fallback(reason) = result,
               reason.contains("wider than the content area") || reason.contains("taller than one page"),
               scale > minimumScale
            {
                scale = max(minimumScale, scale * 0.85)
                continue
            }
            return result
        }
    }

    private func measureMermaidNodes(_ nodes: [MermaidDiagram.Node], scale: Double = 1) throws -> MermaidMeasurementResult {
        let fontSize = options.baseFontSize * 0.88 * scale
        let lineHeight = fontSize * 1.18
        let horizontalPadding = 10.0 * scale
        let verticalPadding = 7.0 * scale
        let maxNodeWidth = max(48, min(180, contentWidth - 20))
        let minNodeWidth = min(96 * scale, maxNodeWidth)
        let labelWidthLimit = max(24, maxNodeWidth - horizontalPadding * 2)
        var measurements: [String: MermaidNodeMeasurement] = [:]

        for node in nodes {
            // A newline in a label is a line break the author wrote (`<br/>`); each line is
            // then wrapped to the node width on its own.
            let labelLines = try node.label.split(separator: "\n", omittingEmptySubsequences: false).flatMap { segment in
                try wrappedLines([PDFTextRun(text: String(segment), font: .helvetica, size: fontSize)], maxWidth: labelWidthLimit)
            }
            let lineWidths = try labelLines.map { line in
                try inkWidth(ofLine: line)
            }
            let widestLine = lineWidths.max() ?? 0
            guard widestLine <= labelWidthLimit + 0.1 else {
                return .fallback("node label `\(node.label)` is wider than the diagram node limit")
            }

            let textHeight = Double(labelLines.count) * lineHeight + verticalPadding * 2
            var size = node.shape.boxSize(forText: (
                width: max(minNodeWidth, widestLine + horizontalPadding * 2),
                height: max(34 * scale, textHeight),
            ))
            if node.shape == .stadium {
                // The rounded ends take half the height each, so the text keeps its room between them.
                size.width += size.height / 2
            }
            measurements[node.id] = MermaidNodeMeasurement(
                id: node.id,
                labelLines: labelLines,
                width: size.width,
                height: size.height,
                fontSize: fontSize,
                lineHeight: lineHeight,
                verticalPadding: verticalPadding,
                shape: node.shape,
                textHeight: Double(labelLines.count) * lineHeight,
            )
        }

        return .measurements(measurements)
    }

    /// Plans a diagram whose layers are already known: the nodes and groups of its outer level.
    /// A group is laid out inside its own frame first, and its frame then takes part in the
    /// outer layout as one item.
    private func mermaidRenderPlan(
        diagram: MermaidDiagram,
        outerDirection: MermaidDiagram.Direction,
        layers: [[MermaidDiagram.Node]],
        measurements: [String: MermaidNodeMeasurement],
        scale: Double,
    ) throws -> MermaidRenderPlanResult {
        let outerPadding = 8.0
        var items = measurements.mapValues { MermaidLayoutItem(id: $0.id, width: $0.width, height: $0.height) }
        var groupLayouts: [String: MermaidGroupLayout] = [:]
        for group in diagram.groups {
            switch try mermaidGroupLayout(group, in: diagram, measurements: measurements, scale: scale) {
            case let .fallback(reason):
                return .fallback(reason)
            case let .layout(groupLayout):
                groupLayouts[group.id] = groupLayout
                items[group.id] = MermaidLayoutItem(id: group.id, width: groupLayout.width, height: groupLayout.height)
            }
        }

        let vertical = outerDirection.isVertical
        let outcome = vertical
            ? verticalMermaidLayout(
                layers: layers, items: items, originX: options.margins.left,
                frameWidth: contentWidth, fillsFrame: true, startOffset: outerPadding,
            )
            : horizontalMermaidLayout(
                layers: layers, items: items, originX: options.margins.left,
                frameWidth: contentWidth, fillsFrame: true, startOffset: outerPadding,
            )
        let layout: MermaidLayout
        switch outcome {
        case let .fallback(reason):
            return .fallback(reason)
        case let .layout(found):
            layout = found
        }

        let height = vertical
            ? max(outerPadding * 2, layout.bottom + outerPadding)
            : layout.contentHeight + outerPadding * 2
        guard height <= contentHeight else {
            return .fallback("diagram is taller than one page")
        }

        var boxes: [MermaidNodeBox] = []
        var groupBoxes: [MermaidGroupBox] = []
        for placement in layout.placements {
            if let groupLayout = groupLayouts[placement.id] {
                groupBoxes.append(MermaidGroupBox(layout: groupLayout, id: placement.id, x: placement.x, topOffset: placement.topOffset))
                let insideX = placement.x + (groupLayout.width - groupLayout.inner.width) / 2
                let insideTop = placement.topOffset + groupLayout.contentTop
                for inner in groupLayout.inner.placements {
                    if let measurement = measurements[inner.id] {
                        boxes.append(MermaidNodeBox(measurement: measurement, x: insideX + inner.x, topOffset: insideTop + inner.topOffset))
                    }
                }
            } else if let measurement = measurements[placement.id] {
                boxes.append(MermaidNodeBox(measurement: measurement, x: placement.x, topOffset: placement.topOffset))
            }
        }

        if let reason = try mermaidEdgeLabelFallbackReason(
            boxes: boxes,
            groups: groupBoxes,
            edges: diagram.edges,
            planHeight: height,
        ) {
            return .fallback(reason)
        }

        return .plan(MermaidRenderPlan(height: height, boxes: boxes, edges: diagram.edges, groups: groupBoxes))
    }

    /// Lays one group out: its title, then its members in the group's own direction.
    private func mermaidGroupLayout(
        _ group: MermaidDiagram.Group,
        in diagram: MermaidDiagram,
        measurements: [String: MermaidNodeMeasurement],
        scale: Double,
    ) throws -> MermaidGroupLayoutResult {
        let outerPadding = 8.0
        let padding = 8.0 * scale
        let titleGap = 4.0 * scale
        let fontSize = options.baseFontSize * 0.8 * scale
        let lineHeight = fontSize * 1.18
        let availableWidth = contentWidth - outerPadding * 2 - padding * 2

        let titleLines = try group.title.split(separator: "\n", omittingEmptySubsequences: false).flatMap { segment in
            try wrappedLines([PDFTextRun(text: String(segment), font: .helveticaBold, size: fontSize)], maxWidth: availableWidth)
        }
        let titleWidth = try titleLines.map { try inkWidth(ofLine: $0) }.max() ?? 0

        let inner = diagram.innerDiagram(of: group)
        let items = Dictionary(uniqueKeysWithValues: inner.nodes.compactMap { node in
            measurements[node.id].map { (node.id, MermaidLayoutItem(id: $0.id, width: $0.width, height: $0.height)) }
        })
        let outcome = inner.direction.isVertical
            ? verticalMermaidLayout(
                layers: inner.layers(), items: items, originX: 0,
                frameWidth: availableWidth, fillsFrame: false, startOffset: 0,
            )
            : horizontalMermaidLayout(
                layers: inner.layers(), items: items, originX: 0,
                frameWidth: availableWidth, fillsFrame: false, startOffset: 0,
            )
        switch outcome {
        case let .fallback(reason):
            return .fallback(reason)
        case let .layout(innerLayout):
            let titleBlock = titleLines.isEmpty ? 0 : Double(titleLines.count) * lineHeight + titleGap
            return .layout(MermaidGroupLayout(
                title: titleLines,
                fontSize: fontSize,
                lineHeight: lineHeight,
                padding: padding,
                width: max(innerLayout.width, titleWidth) + padding * 2,
                height: padding + titleBlock + innerLayout.bottom + padding,
                contentTop: padding + titleBlock,
                inner: innerLayout,
            ))
        }
    }

    /// Lays layers out as rows of items. A row may use `frameWidth`; a layout that `fillsFrame`
    /// is that wide and centres its rows, otherwise it is as wide as its widest row. `originX`
    /// is its left edge and `startOffset` the distance of the first row from the top.
    private func verticalMermaidLayout(
        layers: [[MermaidDiagram.Node]],
        items: [String: MermaidLayoutItem],
        originX: Double,
        frameWidth: Double,
        fillsFrame: Bool,
        startOffset: Double,
    ) -> MermaidLayoutResult {
        let rowSpacing = 36.0
        let preferredColumnSpacing = 24.0
        let minimumColumnSpacing = 12.0

        struct Row {
            var items: [MermaidLayoutItem]
            var height: Double
            var spacing: Double
            var width: Double
        }

        var rows: [Row] = []
        for layer in layers {
            let rowItems = layer.compactMap { items[$0.id] }
            let rowHeight = rowItems.map(\.height).max() ?? 0
            var spacing = rowItems.count > 1 ? preferredColumnSpacing : 0
            var rowWidth = rowItems.reduce(0) { $0 + $1.width } + Double(max(0, rowItems.count - 1)) * spacing
            if rowWidth > frameWidth {
                spacing = rowItems.count > 1 ? minimumColumnSpacing : 0
                rowWidth = rowItems.reduce(0) { $0 + $1.width } + Double(max(0, rowItems.count - 1)) * spacing
            }
            guard rowWidth <= frameWidth + 0.1 else {
                return .fallback("diagram row is wider than the content area")
            }
            rows.append(Row(items: rowItems, height: rowHeight, spacing: spacing, width: rowWidth))
        }

        let width = fillsFrame ? frameWidth : (rows.map(\.width).max() ?? 0)
        var placements: [MermaidPlacement] = []
        var offset = startOffset
        for row in rows {
            var x = originX + (width - row.width) / 2
            for item in row.items {
                placements.append(MermaidPlacement(id: item.id, x: x, topOffset: offset + (row.height - item.height) / 2))
                x += item.width + row.spacing
            }
            offset += row.height + rowSpacing
        }

        return .layout(MermaidLayout(
            width: width,
            bottom: offset - rowSpacing,
            contentHeight: offset - rowSpacing - startOffset,
            placements: placements,
        ))
    }

    /// Lays layers out as columns of items, with the same frame rules as the vertical layout.
    private func horizontalMermaidLayout(
        layers: [[MermaidDiagram.Node]],
        items: [String: MermaidLayoutItem],
        originX: Double,
        frameWidth: Double,
        fillsFrame: Bool,
        startOffset: Double,
    ) -> MermaidLayoutResult {
        let columnSpacing = 34.0
        let compactColumnSpacing = 18.0
        let nodeSpacing = 20.0
        let columns = layers.map { layer in
            layer.compactMap { items[$0.id] }
        }
        let columnWidths = columns.map { $0.map(\.width).max() ?? 0 }
        let columnHeights = columns.map { column in
            column.reduce(0) { $0 + $1.height } + Double(max(0, column.count - 1)) * nodeSpacing
        }

        var spacing = columnSpacing
        var totalWidth = columnWidths.reduce(0, +) + Double(max(0, columnWidths.count - 1)) * spacing
        if totalWidth > frameWidth {
            spacing = compactColumnSpacing
            totalWidth = columnWidths.reduce(0, +) + Double(max(0, columnWidths.count - 1)) * spacing
        }
        guard totalWidth <= frameWidth + 0.1 else {
            return .fallback("diagram columns are wider than the content area")
        }

        let innerHeight = columnHeights.max() ?? 0
        let width = fillsFrame ? frameWidth : totalWidth
        var placements: [MermaidPlacement] = []
        var x = originX + (width - totalWidth) / 2
        for columnIndex in columns.indices {
            var topOffset = startOffset + (innerHeight - columnHeights[columnIndex]) / 2
            for item in columns[columnIndex] {
                placements.append(MermaidPlacement(
                    id: item.id,
                    x: x + (columnWidths[columnIndex] - item.width) / 2,
                    topOffset: topOffset,
                ))
                topOffset += item.height + nodeSpacing
            }
            x += columnWidths[columnIndex] + spacing
        }

        return .layout(MermaidLayout(
            width: width,
            bottom: startOffset + innerHeight,
            contentHeight: innerHeight,
            placements: placements,
        ))
    }

    private func mermaidEdgeLabelFallbackReason(
        boxes: [MermaidNodeBox],
        groups: [MermaidGroupBox],
        edges: [MermaidDiagram.Edge],
        planHeight: Double,
    ) throws -> String? {
        let contentFrame = MermaidFrame(
            left: options.margins.left,
            top: 0,
            width: contentWidth,
            height: planHeight,
        )
        var framesByID = Dictionary(uniqueKeysWithValues: boxes.map { ($0.id, $0.frame(topY: 0)) })
        for group in groups {
            framesByID[group.id] = group.frame(topY: 0)
        }
        let nodeFrames = boxes.map { $0.frame(topY: 0).expanded(by: 2) }

        for edge in edges where edge.isDrawn {
            guard let label = edge.label,
                  let sourceFrame = framesByID[edge.source],
                  let targetFrame = framesByID[edge.target]
            else {
                continue
            }

            let endpoints = mermaidEdgeEndpoints(source: sourceFrame, target: targetFrame)
            let labelFrame = try mermaidEdgeLabelFrame(label, start: endpoints.start, end: endpoints.end)

            guard contentFrame.contains(labelFrame) else {
                return "edge label `\(label)` does not fit inside the diagram content area"
            }
            if nodeFrames.contains(where: { labelFrame.intersects($0) }) {
                return "edge label `\(label)` collides with a diagram node"
            }
            if groups.contains(where: { group in
                let frame = group.frame(topY: 0)
                return labelFrame.intersects(frame) && !frame.contains(labelFrame)
            }) {
                return "edge label `\(label)` collides with a group frame"
            }
        }

        return nil
    }

    private static let mermaidPageFill = PDFColor(red: 0.97, green: 0.98, blue: 0.99)
    private static let mermaidGroupFill = PDFColor(red: 0.93, green: 0.95, blue: 0.97)

    private mutating func drawMermaidPlan(_ plan: MermaidRenderPlan) throws {
        markBlockQuoteContentDrawn()
        let topY = y
        currentPage.drawRectangle(
            x: options.margins.left - 4,
            y: topY - plan.height,
            width: contentWidth + 8,
            height: plan.height,
            stroke: PDFColor(red: 0.72, green: 0.78, blue: 0.84),
            fill: PDFColor(red: 0.97, green: 0.98, blue: 0.99),
        )

        for group in plan.groups {
            try drawMermaidGroup(group, topY: topY)
        }

        var framesByID = Dictionary(uniqueKeysWithValues: plan.boxes.map { ($0.id, $0.frame(topY: topY)) })
        for group in plan.groups {
            framesByID[group.id] = group.frame(topY: topY)
        }
        for edge in plan.edges where edge.isDrawn {
            guard let sourceFrame = framesByID[edge.source],
                  let targetFrame = framesByID[edge.target]
            else {
                continue
            }
            try drawMermaidEdge(
                edge,
                sourceFrame: sourceFrame,
                targetFrame: targetFrame,
                groupFrames: plan.groups.map { $0.frame(topY: topY) },
            )
        }

        for box in plan.boxes {
            try drawMermaidNode(box, topY: topY)
        }
    }

    /// A group's frame, drawn behind its nodes, with its title centred at the top.
    private mutating func drawMermaidGroup(_ group: MermaidGroupBox, topY: Double) throws {
        let frame = group.frame(topY: topY)
        currentPage.drawRectangle(
            x: frame.left,
            y: frame.bottom,
            width: group.width,
            height: group.height,
            stroke: PDFColor(red: 0.62, green: 0.69, blue: 0.77),
            fill: Self.mermaidGroupFill,
        )

        var textY = frame.top - group.padding - group.fontSize
        for line in group.titleLines {
            let lineWidth = try inkWidth(ofLine: line)
            try drawRuns(line, x: frame.left + (group.width - lineWidth) / 2, y: textY)
            textY -= group.lineHeight
        }
    }

    private mutating func drawMermaidEdge(
        _ edge: MermaidDiagram.Edge,
        sourceFrame: MermaidFrame,
        targetFrame: MermaidFrame,
        groupFrames: [MermaidFrame] = [],
    ) throws {
        let endpoints = mermaidEdgeEndpoints(source: sourceFrame, target: targetFrame)

        drawArrow(from: endpoints.start, to: endpoints.end, dashed: edge.dashed, arrowhead: edge.hasArrowhead)
        if let label = edge.label {
            // A label inside a group is painted in the group's colour, not the page's.
            let labelFrame = try mermaidEdgeLabelFrame(label, start: endpoints.start, end: endpoints.end)
            let insideGroup = groupFrames.contains { $0.contains(labelFrame) }
            try drawMermaidEdgeLabel(
                label,
                start: endpoints.start,
                end: endpoints.end,
                fill: insideGroup ? Self.mermaidGroupFill : Self.mermaidPageFill,
            )
        }
    }

    private func mermaidEdgeEndpoints(
        source: MermaidFrame,
        target: MermaidFrame,
    ) -> (start: MermaidPoint, end: MermaidPoint) {
        let horizontalDistance = abs(target.centerX - source.centerX)
        let verticalDistance = abs(target.centerY - source.centerY)

        if horizontalDistance > verticalDistance {
            if target.centerX >= source.centerX {
                return (
                    MermaidPoint(x: source.right, y: source.centerY),
                    MermaidPoint(x: target.left, y: target.centerY),
                )
            }
            return (
                MermaidPoint(x: source.left, y: source.centerY),
                MermaidPoint(x: target.right, y: target.centerY),
            )
        }

        if target.centerY <= source.centerY {
            return (
                MermaidPoint(x: source.centerX, y: source.bottom),
                MermaidPoint(x: target.centerX, y: target.top),
            )
        }
        return (
            MermaidPoint(x: source.centerX, y: source.top),
            MermaidPoint(x: target.centerX, y: target.bottom),
        )
    }

    private mutating func drawArrow(from start: MermaidPoint, to end: MermaidPoint, dashed: Bool = false, arrowhead: Bool = true) {
        currentPage.drawLine(
            x1: start.x,
            y1: start.y,
            x2: end.x,
            y2: end.y,
            width: 0.8,
            color: PDFColor(red: 0.25, green: 0.31, blue: 0.38),
            dashed: dashed,
        )

        guard arrowhead else {
            return
        }

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0.1 else {
            return
        }

        let angle = atan2(dy, dx)
        let arrowLength = 6.0
        let spread = 0.48
        let first = MermaidPoint(
            x: end.x - arrowLength * cos(angle - spread),
            y: end.y - arrowLength * sin(angle - spread),
        )
        let second = MermaidPoint(
            x: end.x - arrowLength * cos(angle + spread),
            y: end.y - arrowLength * sin(angle + spread),
        )

        currentPage.drawLine(x1: end.x, y1: end.y, x2: first.x, y2: first.y, width: 0.8, color: PDFColor(red: 0.25, green: 0.31, blue: 0.38))
        currentPage.drawLine(x1: end.x, y1: end.y, x2: second.x, y2: second.y, width: 0.8, color: PDFColor(red: 0.25, green: 0.31, blue: 0.38))
    }

    private mutating func drawMermaidEdgeLabel(
        _ label: String,
        start: MermaidPoint,
        end: MermaidPoint,
        fill: PDFColor,
    ) throws {
        let run = mermaidEdgeLabelRun(label)
        let frame = try mermaidEdgeLabelFrame(label, start: start, end: end)
        currentPage.drawRectangle(
            x: frame.left,
            y: frame.bottom,
            width: frame.width,
            height: frame.height,
            stroke: nil,
            fill: fill,
        )
        try currentPage.drawTextRun(
            run,
            x: frame.left + 3,
            y: frame.bottom + 3,
            fontSet: options.fontSet,
            embeddedFonts: embeddedFonts,
        )
    }

    private func mermaidEdgeLabelFrame(
        _ label: String,
        start: MermaidPoint,
        end: MermaidPoint,
    ) throws -> MermaidFrame {
        let run = mermaidEdgeLabelRun(label)
        let width = try textWidth(run)
        let height = run.size + 4
        return MermaidFrame(
            left: (start.x + end.x) / 2 - width / 2 - 3,
            top: (start.y + end.y) / 2 + height / 2,
            width: width + 6,
            height: height,
        )
    }

    private func mermaidEdgeLabelRun(_ label: String) -> PDFTextRun {
        PDFTextRun(
            text: label,
            font: .helveticaOblique,
            size: options.baseFontSize * 0.72,
            color: .gray,
        )
    }

    private mutating func drawMermaidNode(_ box: MermaidNodeBox, topY: Double) throws {
        let frame = box.frame(topY: topY)
        let stroke = PDFColor(red: 0.18, green: 0.31, blue: 0.48)
        let fill = PDFColor(red: 0.90, green: 0.94, blue: 0.98)
        switch box.shape {
        case .rectangle:
            currentPage.drawRectangle(x: frame.left, y: frame.bottom, width: box.width, height: box.height, stroke: stroke, fill: fill)
        case .rounded:
            currentPage.drawRoundedRectangle(
                x: frame.left, y: frame.bottom, width: box.width, height: box.height, radius: 6, stroke: stroke, fill: fill,
            )
        case .stadium:
            currentPage.drawRoundedRectangle(
                x: frame.left, y: frame.bottom, width: box.width, height: box.height, radius: box.height / 2, stroke: stroke, fill: fill,
            )
        case .diamond:
            currentPage.drawPolygon(
                points: MermaidDiagram.Node.Shape.diamondOutline(left: frame.left, bottom: frame.bottom, width: box.width, height: box.height),
                stroke: stroke,
                fill: fill,
            )
        }

        // A rectangle keeps its text where it always was (pinned by `MermaidLayoutGoldenTests`); the other shapes centre the text block in the box.
        let topInset = box.shape == .rectangle ? box.verticalPadding : (box.height - box.textHeight) / 2
        var textY = frame.top - topInset - box.fontSize
        for line in box.labelLines {
            let lineWidth = try inkWidth(ofLine: line)
            try drawRuns(line, x: frame.left + (box.width - lineWidth) / 2, y: textY)
            textY -= box.lineHeight
        }
    }

    private mutating func renderTable(_ table: MarkdownBlock.Table) throws {
        let tableElement = beginStructureElement(.table)
        defer { endStructureElement(tableElement) }

        let cellPadding = 4.0
        let cellStyle = style(for: .tableCell)
        let fontSize = fontSize(for: .tableCell)
        let lineHeight = fontSize * cellStyle.lineHeightMultiplier
        let columns = tableColumnCount(table)
        let columnWidths = try measuredTableColumnWidths(
            table,
            columns: columns,
            cellPadding: cellPadding,
            fontSize: fontSize,
        )
        let header = try preparedTableRow(
            cells: table.headers,
            columns: columns,
            columnWidths: columnWidths,
            cellPadding: cellPadding,
            fontSize: fontSize,
            header: true,
        )

        try renderPreparedTableRow(
            header,
            alignments: table.alignments,
            columnWidths: columnWidths,
            cellPadding: cellPadding,
            fontSize: fontSize,
            lineHeight: lineHeight,
            header: true,
            repeatedHeader: nil,
        )

        for row in table.rows {
            let preparedRow = try preparedTableRow(
                cells: row,
                columns: columns,
                columnWidths: columnWidths,
                cellPadding: cellPadding,
                fontSize: fontSize,
                header: false,
            )
            try renderPreparedTableRow(
                preparedRow,
                alignments: table.alignments,
                columnWidths: columnWidths,
                cellPadding: cellPadding,
                fontSize: fontSize,
                lineHeight: lineHeight,
                header: false,
                repeatedHeader: header,
            )
        }

        y -= 12
    }

    private func tableColumnCount(_ table: MarkdownBlock.Table) -> Int {
        let counts = [table.headers.count, table.alignments.count] + table.rows.map(\.count)
        return max(1, counts.max() ?? 1)
    }

    private func measuredTableColumnWidths(
        _ table: MarkdownBlock.Table,
        columns: Int,
        cellPadding: Double,
        fontSize: Double,
    ) throws -> [Double] {
        let minimumColumnWidth = min(36, contentWidth / Double(columns))
        let maximumColumnWidth = columns == 1 ? contentWidth : contentWidth * 0.65
        let metrics = try (0 ..< columns).map { column in
            try tableColumnMetrics(
                table,
                column: column,
                columns: columns,
                minimumWidth: minimumColumnWidth,
                maximumWidth: maximumColumnWidth,
                cellPadding: cellPadding,
                fontSize: fontSize,
            )
        }
        let preferredWidths = metrics.map(\.preferredWidth)
        let minimumWidths = metrics.map(\.minimumWidth)
        let preferredTotal = preferredWidths.reduce(0, +)

        if preferredTotal <= contentWidth {
            let slack = contentWidth - preferredTotal
            return preferredWidths.map { $0 + slack / Double(columns) }
        }

        let minimumTotal = minimumWidths.reduce(0, +)
        guard minimumTotal < contentWidth else {
            return Array(repeating: contentWidth / Double(columns), count: columns)
        }

        let shrinkableTotal = zip(preferredWidths, minimumWidths)
            .map { $0 - $1 }
            .reduce(0, +)
        guard shrinkableTotal > 0 else {
            return Array(repeating: contentWidth / Double(columns), count: columns)
        }

        let overflow = preferredTotal - contentWidth
        return zip(preferredWidths, minimumWidths).map { preferred, minimum in
            let shrinkable = preferred - minimum
            return preferred - overflow * (shrinkable / shrinkableTotal)
        }
    }

    private func tableColumnMetrics(
        _ table: MarkdownBlock.Table,
        column: Int,
        columns: Int,
        minimumWidth: Double,
        maximumWidth: Double,
        cellPadding: Double,
        fontSize: Double,
    ) throws -> TableColumnMetrics {
        let headerRuns = try tableRuns(
            table.headers,
            column: column,
            style: style(for: .tableHeader),
            size: fontSize,
        )
        let bodyRuns = try table.rows.map {
            try tableRuns($0, column: column, style: style(for: .tableCell), size: fontSize)
        }
        let allRuns = [headerRuns] + bodyRuns
        let contentWidths = try allRuns.map { try textWidth($0) }
        let tokenWidths = try allRuns
            .flatMap(tokenize)
            .filter { $0.text != "\n" }
            .map { try textWidth($0) }
        let preferredContentWidth = contentWidths.max() ?? 0
        let widestTokenWidth = tokenWidths.max() ?? 0
        let paddedPreferredWidth = preferredContentWidth + cellPadding * 2
        let paddedTokenWidth = widestTokenWidth + cellPadding * 2
        let preferredWidth = min(maximumWidth, max(minimumWidth, paddedPreferredWidth))
        let tokenFloor = min(maximumWidth, max(minimumWidth, paddedTokenWidth))
        let fairFloor = max(minimumWidth, min(tokenFloor, contentWidth / Double(columns)))

        return TableColumnMetrics(
            minimumWidth: fairFloor,
            preferredWidth: max(preferredWidth, fairFloor),
        )
    }

    private func tableRuns(
        _ cells: [[MarkdownInline]],
        column: Int,
        style: PDFOptions.ElementStyle,
        size: Double,
    ) throws -> [PDFTextRun] {
        guard column < cells.count else {
            return []
        }
        return try flatten(cells[column], font: standardFont(for: style.fontRole), size: size, color: style.color)
    }

    private func preparedTableRow(
        cells: [[MarkdownInline]],
        columns: Int,
        columnWidths: [Double],
        cellPadding: Double,
        fontSize: Double,
        header: Bool,
    ) throws -> TablePreparedRow {
        let cellLines = try (0 ..< columns).map { column in
            let cell = column < cells.count ? cells[column] : []
            let width = column < columnWidths.count ? columnWidths[column] : contentWidth / Double(columns)
            let style = header ? style(for: .tableHeader) : style(for: .tableCell)
            return try wrappedLines(
                flatten(cell, font: standardFont(for: style.fontRole), size: fontSize, color: style.color),
                maxWidth: max(1, width - cellPadding * 2),
            )
        }
        return TablePreparedRow(cellLines: cellLines)
    }

    private mutating func renderPreparedTableRow(
        _ row: TablePreparedRow,
        alignments: [MarkdownBlock.Alignment],
        columnWidths: [Double],
        cellPadding: Double,
        fontSize: Double,
        lineHeight: Double,
        header: Bool,
        repeatedHeader: TablePreparedRow?,
    ) throws {
        let cellLines = row.cellLines
        let maxLines = max(1, cellLines.map(\.count).max() ?? 1)
        var lineOffset = 0

        while lineOffset < maxLines {
            try ensureTableRowFragmentSpace(
                lineHeight + cellPadding * 2,
                header: repeatedHeader,
                alignments: alignments,
                columnWidths: columnWidths,
                cellPadding: cellPadding,
                fontSize: fontSize,
                lineHeight: lineHeight,
            )
            let lineCount = min(
                maxLines - lineOffset,
                tableRowLineCapacity(lineHeight: lineHeight, cellPadding: cellPadding),
            )
            try renderTableRowFragment(
                cellLines: cellLines,
                alignments: alignments,
                columnWidths: columnWidths,
                cellPadding: cellPadding,
                fontSize: fontSize,
                lineHeight: lineHeight,
                header: header,
                lineOffset: lineOffset,
                lineCount: lineCount,
            )
            lineOffset += lineCount
            if lineOffset < maxLines {
                startNewPage()
                if let repeatedHeader {
                    try renderPreparedTableRow(
                        repeatedHeader,
                        alignments: alignments,
                        columnWidths: columnWidths,
                        cellPadding: cellPadding,
                        fontSize: fontSize,
                        lineHeight: lineHeight,
                        header: true,
                        repeatedHeader: nil,
                    )
                }
            }
        }
    }

    private mutating func ensureTableRowFragmentSpace(
        _ height: Double,
        header: TablePreparedRow?,
        alignments: [MarkdownBlock.Alignment],
        columnWidths: [Double],
        cellPadding: Double,
        fontSize: Double,
        lineHeight: Double,
    ) throws {
        guard y - height < options.margins.bottom else {
            return
        }

        startNewPage()
        guard let header else {
            return
        }

        try renderPreparedTableRow(
            header,
            alignments: alignments,
            columnWidths: columnWidths,
            cellPadding: cellPadding,
            fontSize: fontSize,
            lineHeight: lineHeight,
            header: true,
            repeatedHeader: nil,
        )

        if y - height < options.margins.bottom {
            startNewPage()
        }
    }

    private mutating func renderStandaloneImage(_ content: [MarkdownInline]) throws -> Bool {
        guard content.count == 1,
              case let .image(alt, source, _) = content[0]
        else {
            return false
        }

        if source.hasPrefix("http://") || source.hasPrefix("https://") {
            try drawImagePlaceholder(text: "[Remote image: \(alt.isEmpty ? source : alt)]")
            return true
        }

        let image: PDFImage
        do {
            image = try loadImage(source: source)
        } catch {
            // An image we cannot resolve or decode (a missing file, a
            // site-absolute path with no matching asset root, or an unsupported
            // format such as SVG) must not fail the whole document. Degrade to a
            // visible placeholder, the same way a remote image does, and keep
            // rendering. See issue #211.
            try drawImagePlaceholder(text: "[Image: \(alt.isEmpty ? source : alt)]")
            return true
        }

        let maxWidth = contentWidth
        let maxHeight = imageMaxHeight
        let widthScale = maxWidth / Double(image.width)
        let heightScale = maxHeight / Double(image.height)
        let scale = min(1, widthScale, heightScale)
        let drawWidth = Double(image.width) * scale
        let drawHeight = Double(image.height) * scale

        ensureSpace(drawHeight)
        markBlockQuoteContentDrawn()
        let figureElement = beginStructureElement(
            .figure,
            attributes: PDFTaggedContent.Attributes(
                alternateDescription: alt.isEmpty ? source : alt,
            ),
        )
        let marked = beginMarkedContentForCurrentElement()
        currentPage.drawImage(
            name: image.name,
            x: options.margins.left,
            y: y - drawHeight,
            width: drawWidth,
            height: drawHeight,
        )
        endMarkedContentIfNeeded(marked)
        endStructureElement(figureElement)
        y -= drawHeight
        return true
    }

    private mutating func drawImagePlaceholder(text: String) throws {
        let element = beginStructureElement(.paragraph)
        defer { endStructureElement(element) }
        let imageStyle = style(for: .imagePlaceholder)
        try drawWrapped(
            [
                PDFTextRun(
                    text: text,
                    font: standardFont(for: imageStyle.fontRole),
                    size: fontSize(for: .imagePlaceholder),
                    color: imageStyle.color,
                ),
            ],
            x: options.margins.left,
            maxWidth: contentWidth,
            lineHeight: options.baseFontSize * 1.35,
        )
    }

    private mutating func loadImage(source: String) throws -> PDFImage {
        // Keyed by base as well as source: two merged sources may spell different
        // files the same way (`../figures/a.png`).
        let key = "\(assetsBaseURL?.absoluteString ?? "")\u{0}\(source)"
        if let image = imageCache[key] {
            return image
        }

        var image = try sharedImages.image(source: source, baseURL: assetsBaseURL)
        image.name = "Im\(images.count + 1)"
        images.append(image)
        imageCache[key] = image
        return image
    }

    private func flatten(
        _ inlines: [MarkdownInline],
        font: StandardFont,
        size: Double,
        color: PDFColor = .black,
        underline: Bool = false,
        strikethrough: Bool = false,
        linkDestination: String? = nil,
    ) throws -> [PDFTextRun] {
        var runs: [PDFTextRun] = []

        for inline in inlines {
            switch inline {
            case let .text(text):
                runs.append(PDFTextRun(text: text, font: font, size: size, color: color, underline: underline, strikethrough: strikethrough, linkDestination: linkDestination))
            case .softBreak:
                runs.append(PDFTextRun(text: " ", font: font, size: size, color: color, underline: underline, strikethrough: strikethrough, linkDestination: linkDestination))
            case .lineBreak:
                runs.append(PDFTextRun(text: "\n", font: font, size: size, color: color, underline: underline, strikethrough: strikethrough, linkDestination: linkDestination))
            case let .code(text):
                let inlineCodeStyle = style(for: .inlineCode)
                runs.append(PDFTextRun(
                    text: text,
                    font: standardFont(for: inlineCodeStyle.fontRole),
                    size: size * inlineCodeStyle.sizeMultiplier,
                    color: color == style(for: .body).color ? inlineCodeStyle.color : color,
                    underline: underline,
                    strikethrough: strikethrough,
                    linkDestination: linkDestination,
                    isIndexable: false,
                ))
            case let .inlineMath(math):
                try runs.append(contentsOf: inlineMathRuns(
                    math,
                    size: size,
                    inheritedColor: color,
                    underline: underline,
                    strikethrough: strikethrough,
                    linkDestination: linkDestination,
                ).map { run in
                    var run = run
                    run.isIndexable = false
                    return run
                })
            case let .emphasis(children):
                try runs.append(contentsOf: flatten(
                    children,
                    font: .helveticaOblique,
                    size: size,
                    color: color,
                    underline: underline,
                    strikethrough: strikethrough,
                    linkDestination: linkDestination,
                ))
            case let .strong(children):
                try runs.append(contentsOf: flatten(
                    children,
                    font: .helveticaBold,
                    size: size,
                    color: color,
                    underline: underline,
                    strikethrough: strikethrough,
                    linkDestination: linkDestination,
                ))
            case let .strikethrough(children):
                try runs.append(contentsOf: flatten(children, font: font, size: size, color: color, underline: underline, strikethrough: true, linkDestination: linkDestination))
            case let .link(children, destination, _):
                let linkStyle = style(for: .link)
                try runs.append(contentsOf: flatten(
                    children,
                    font: font,
                    size: size,
                    color: linkStyle.color,
                    underline: linkStyle.underline,
                    strikethrough: strikethrough,
                    linkDestination: destination,
                ))
            case let .image(alt, source, _):
                let imageStyle = style(for: .imagePlaceholder)
                let label = alt.isEmpty ? source : alt
                runs.append(PDFTextRun(
                    text: "[Image: \(label)]",
                    font: standardFont(for: imageStyle.fontRole),
                    size: size,
                    color: imageStyle.color,
                    underline: underline,
                    strikethrough: strikethrough,
                    linkDestination: linkDestination,
                    isIndexable: false,
                ))
            case let .indexMarker(term):
                var marker = PDFTextRun(text: "", font: font, size: size, color: color)
                marker.indexTerm = term
                runs.append(marker)
            case let .footnoteReference(label):
                if let footnote = footnotesByLabelKey[footnoteKey(label)] {
                    let linkStyle = style(for: .link)
                    runs.append(PDFTextRun(
                        text: "\(footnote.number)",
                        font: font,
                        size: size * 0.72,
                        color: linkStyle.color,
                        underline: false,
                        strikethrough: strikethrough,
                        linkDestination: "#\(footnote.definitionDestinationName)",
                        baselineOffset: size * 0.38,
                        namedDestination: footnote.referenceDestinationName,
                        isIndexable: false,
                    ))
                } else {
                    runs.append(PDFTextRun(
                        text: "[^\(label)]",
                        font: font,
                        size: size,
                        color: color,
                        underline: underline,
                        strikethrough: strikethrough,
                        linkDestination: linkDestination,
                        isIndexable: false,
                    ))
                }
            }
        }

        return runs
    }

    private func inlineMathRuns(
        _ math: MarkdownMath,
        size: Double,
        inheritedColor: PDFColor,
        underline: Bool,
        strikethrough: Bool,
        linkDestination: String?,
    ) throws -> [PDFTextRun] {
        try requireEmbeddedMathFont(for: style(for: .inlineMath))
        do {
            let parsed = try MathParser().parse(math.source)
            return inlineMathRuns(
                for: parsed.root,
                size: size,
                inheritedColor: inheritedColor,
                underline: underline,
                strikethrough: strikethrough,
                linkDestination: linkDestination,
            )
        } catch let error as MarkdownPDFError {
            throw error
        } catch {
            return [inlineMathTextRun(
                math.delimitedSource,
                size: size,
                inheritedColor: inheritedColor,
                underline: underline,
                strikethrough: strikethrough,
                linkDestination: linkDestination,
            )]
        }
    }

    private func inlineMathRuns(
        for node: MathNode,
        size: Double,
        inheritedColor: PDFColor,
        underline: Bool,
        strikethrough: Bool,
        linkDestination: String?,
    ) -> [PDFTextRun] {
        switch node {
        case let .sequence(children):
            return children.flatMap {
                inlineMathRuns(
                    for: $0,
                    size: size,
                    inheritedColor: inheritedColor,
                    underline: underline,
                    strikethrough: strikethrough,
                    linkDestination: linkDestination,
                )
            }
        case let .text(text):
            return [inlineMathTextRun(
                text,
                size: size,
                inheritedColor: inheritedColor,
                underline: underline,
                strikethrough: strikethrough,
                linkDestination: linkDestination,
            )]
        case let .symbol(display, linearized, _):
            // Draw the Unicode glyph when the active font covers it, else the
            // ASCII transliteration (matching `.unicodeWhereCovered` on the box
            // path). The base-14 portable profile covers no math glyphs.
            let font = mathFace ?? standardFont(for: style(for: .inlineMath).fontRole)
            let text = embeddedFonts.covers(display, font: font) ? display : linearized
            return [inlineMathTextRun(
                text,
                size: size,
                inheritedColor: inheritedColor,
                underline: underline,
                strikethrough: strikethrough,
                linkDestination: linkDestination,
            )]
        case .fraction, .radical, .space:
            if let run = inlineMathBoxRun(
                for: node,
                size: size,
                inheritedColor: inheritedColor,
                underline: underline,
                strikethrough: strikethrough,
                linkDestination: linkDestination,
            ) {
                return [run]
            }
            return [inlineMathTextRun(
                MathLinearizer().linearize(node),
                size: size,
                inheritedColor: inheritedColor,
                underline: underline,
                strikethrough: strikethrough,
                linkDestination: linkDestination,
            )]
        case .accent, .matrix, .scaledDelimiter:
            return [inlineMathTextRun(
                MathLinearizer().linearize(node),
                size: size,
                inheritedColor: inheritedColor,
                underline: underline,
                strikethrough: strikethrough,
                linkDestination: linkDestination,
            )]
        case let .scripts(base, subscriptNode, superscriptNode):
            let scriptSize = size * 0.68
            var runs = inlineMathRuns(
                for: base,
                size: size,
                inheritedColor: inheritedColor,
                underline: underline,
                strikethrough: strikethrough,
                linkDestination: linkDestination,
            )
            if let subscriptNode {
                runs += inlineMathRuns(
                    for: subscriptNode,
                    size: scriptSize,
                    inheritedColor: inheritedColor,
                    underline: underline,
                    strikethrough: strikethrough,
                    linkDestination: linkDestination,
                ).map { run in
                    PDFTextRun(
                        text: run.text,
                        font: run.font,
                        size: run.size,
                        color: run.color,
                        underline: run.underline,
                        strikethrough: run.strikethrough,
                        linkDestination: run.linkDestination,
                        baselineOffset: run.baselineOffset - size * 0.22,
                        inlineMathBox: run.inlineMathBox,
                    )
                }
            }
            if let superscriptNode {
                runs += inlineMathRuns(
                    for: superscriptNode,
                    size: scriptSize,
                    inheritedColor: inheritedColor,
                    underline: underline,
                    strikethrough: strikethrough,
                    linkDestination: linkDestination,
                ).map { run in
                    PDFTextRun(
                        text: run.text,
                        font: run.font,
                        size: run.size,
                        color: run.color,
                        underline: run.underline,
                        strikethrough: run.strikethrough,
                        linkDestination: run.linkDestination,
                        baselineOffset: run.baselineOffset + size * 0.38,
                        inlineMathBox: run.inlineMathBox,
                    )
                }
            }
            return runs
        }
    }

    private func inlineMathTextRun(
        _ text: String,
        size: Double,
        inheritedColor: PDFColor,
        underline: Bool,
        strikethrough: Bool,
        linkDestination: String?,
    ) -> PDFTextRun {
        let mathStyle = style(for: .inlineMath)
        return PDFTextRun(
            text: text,
            font: mathFace ?? standardFont(for: mathStyle.fontRole),
            size: size * mathStyle.sizeMultiplier,
            color: inheritedColor == style(for: .body).color ? mathStyle.color : inheritedColor,
            underline: underline,
            strikethrough: strikethrough,
            linkDestination: linkDestination,
        )
    }

    /// Lays a fraction or radical out as a typeset inline box. Returns nil when
    /// the math layout cannot be built (for example when a font-backed math
    /// profile lacks an embedded math table), so the caller can fall back to the
    /// readable linearization.
    private func inlineMathBoxRun(
        for node: MathNode,
        size: Double,
        inheritedColor: PDFColor,
        underline: Bool,
        strikethrough: Bool,
        linkDestination: String?,
    ) -> PDFTextRun? {
        let mathStyle = style(for: .inlineMath)
        let boxSize = size * mathStyle.sizeMultiplier
        guard let layout = try? mathLayout(for: mathStyle),
              let box = try? layout.layout(node, size: boxSize, displayStyle: false),
              box.width > 0
        else {
            return nil
        }
        return PDFTextRun(
            text: MathLinearizer().linearize(node),
            font: standardFont(for: mathStyle.fontRole),
            size: boxSize,
            color: inheritedColor == style(for: .body).color ? mathStyle.color : inheritedColor,
            underline: underline,
            strikethrough: strikethrough,
            linkDestination: linkDestination,
            inlineMathBox: box,
        )
    }

    /// Draws wrapped lines. With `indexable`, index terms found in the text are
    /// recorded against the page each match's first line lands on.
    private mutating func drawWrapped(
        _ runs: [PDFTextRun],
        x: Double,
        maxWidth: Double,
        lineHeight: Double,
        indexable: Bool = false,
    ) throws {
        let lines = try wrappedLines(runs, maxWidth: maxWidth)
        let hits = indexable ? indexHits(inLines: lines) : [:]
        for (lineIndex, line) in lines.enumerated() {
            ensureSpace(lineHeight)
            for entry in hits[lineIndex] ?? [] {
                indexRegistry.record(entry, page: currentPageIndex)
            }
            try drawRuns(line, x: x, y: y, maxWidth: maxWidth)
            y -= lineHeight
        }
    }

    private mutating func renderCodeBlockFragment(
        _ lines: [[PDFTextRun]],
        size: Double,
        lineHeight: Double,
        padding: Double,
    ) throws {
        markBlockQuoteContentDrawn()
        let topY = y
        let height = Double(lines.count) * lineHeight + padding * 2
        let codeStyle = style(for: .codeBlock)
        let artifact = beginArtifactIfTagged()
        currentPage.drawRectangle(
            x: options.margins.left,
            y: topY - height,
            width: contentWidth,
            height: height,
            stroke: nil,
            fill: codeStyle.backgroundColor,
        )
        endMarkedContentIfNeeded(artifact)

        var lineY = topY - padding - size
        for line in lines {
            try drawRuns(line, x: options.margins.left + padding, y: lineY, applyBidi: false)
            lineY -= lineHeight
        }
        y = topY - height
    }

    private func codeBlockLineCapacity(
        lineHeight: Double,
        padding: Double,
    ) -> Int {
        max(1, Int(floor((availablePageHeight - padding * 2) / lineHeight)))
    }

    private func expandCodeTabs(_ line: String) -> String {
        var expanded = ""
        var column = 0

        for character in line {
            if character == "\t" {
                let spaces = codeBlockTabWidth - column % codeBlockTabWidth
                expanded += String(repeating: " ", count: spaces)
                column += spaces
            } else {
                expanded.append(character)
                column += 1
            }
        }

        return expanded
    }

    private mutating func renderTableRowFragment(
        cellLines: [[[PDFTextRun]]],
        alignments: [MarkdownBlock.Alignment],
        columnWidths: [Double],
        cellPadding: Double,
        fontSize: Double,
        lineHeight: Double,
        header: Bool,
        lineOffset: Int,
        lineCount: Int,
    ) throws {
        let rowElement = beginStructureElement(.tableRow)
        defer { endStructureElement(rowElement) }

        let rowHeight = Double(lineCount) * lineHeight + cellPadding * 2
        let rowBottom = y - rowHeight
        var x = options.margins.left
        let headerStyle = style(for: .tableHeader)
        let cellStyle = style(for: .tableCell)

        for column in 0 ..< cellLines.count {
            let columnWidth = column < columnWidths.count ? columnWidths[column] : 0
            let artifact = beginArtifactIfTagged()
            currentPage.drawRectangle(
                x: x,
                y: rowBottom,
                width: columnWidth,
                height: rowHeight,
                stroke: header ? headerStyle.borderColor : cellStyle.borderColor,
                fill: header ? headerStyle.backgroundColor : cellStyle.backgroundColor,
            )
            endMarkedContentIfNeeded(artifact)

            let visibleLines = cellLines[column].dropFirst(lineOffset).prefix(lineCount)
            let cellElement = beginStructureElement(
                header ? .tableHeader : .tableCell,
                attributes: header ? PDFTaggedContent.Attributes(tableHeaderScope: .column) : PDFTaggedContent.Attributes(),
            )
            var lineY = y - cellPadding - fontSize
            // Index terms are matched within the lines drawn here, so a term that wraps
            // across a page break inside one cell is not seen.
            let hits = indexHits(inLines: Array(visibleLines))
            for (lineIndex, line) in visibleLines.enumerated() {
                for entry in hits[lineIndex] ?? [] {
                    indexRegistry.record(entry, page: currentPageIndex)
                }
                let width = try inkWidth(ofLine: Array(line))
                let alignment = column < alignments.count ? alignments[column] : .leading
                let textX = switch alignment {
                case .leading:
                    x + cellPadding
                case .center:
                    x + (columnWidth - width) / 2
                case .trailing:
                    x + columnWidth - cellPadding - width
                }
                let drawWidth = alignment == .leading ? max(0, columnWidth - cellPadding * 2) : nil
                try drawRuns(Array(line), x: textX, y: lineY, maxWidth: drawWidth)
                lineY -= lineHeight
            }
            endStructureElement(cellElement)
            x += columnWidth
        }
        y = rowBottom
    }

    private func tableRowLineCapacity(
        lineHeight: Double,
        cellPadding: Double,
    ) -> Int {
        max(1, Int(floor((availablePageHeight - cellPadding * 2) / lineHeight)))
    }

    private func wrappedLines(
        _ runs: [PDFTextRun],
        maxWidth: Double,
    ) throws -> [[PDFTextRun]] {
        let tokens = tokenize(runs)
        var lines: [[PDFTextRun]] = []
        var current: [PDFTextRun] = []
        var currentWidth = 0.0

        for token in try tokens.flatMap({ try splitOversizedToken($0, maxWidth: maxWidth) }) {
            if token.text == "\n" {
                lines.append(current)
                current = []
                currentWidth = 0
                continue
            }

            let width = try textWidth(token)
            // The space that ends a word takes no room at the end of a line: it hangs
            // past the measure, where nothing is drawn. So a word wraps only when it
            // does not fit without that space, and spaces alone never start a line.
            if currentWidth + width > maxWidth, !current.isEmpty, try !hangs(token, after: currentWidth, maxWidth: maxWidth) {
                lines.append(current)
                current = [token]
                currentWidth = width
            } else {
                current.append(token)
                currentWidth += width
            }
        }

        if !current.isEmpty || lines.isEmpty {
            lines.append(current)
        }

        return lines
    }

    private func splitOversizedToken(
        _ token: PDFTextRun,
        maxWidth: Double,
    ) throws -> [PDFTextRun] {
        guard token.text != "\n",
              token.inlineMathBox == nil,
              maxWidth > 0,
              try textWidth(token) > maxWidth,
              try inkWidth(token) > maxWidth
        else {
            return [token]
        }

        var parts: [PDFTextRun] = []
        var buffer = ""
        for character in token.text {
            let candidate = buffer + String(character)
            if !buffer.isEmpty,
               try textWidth(token.withText(candidate)) > maxWidth
            {
                parts.append(token.withText(buffer))
                buffer = String(character)
            } else {
                buffer = candidate
            }
        }

        if !buffer.isEmpty {
            parts.append(token.withText(buffer))
        }
        return parts
    }

    private func tokenize(_ runs: [PDFTextRun]) -> [PDFTextRun] {
        var tokens: [PDFTextRun] = []
        let lineBreaker = LineBreakOpportunityDetector()

        for run in runs {
            // An inline math box is an atomic, indivisible token: it must not be
            // split into word segments, which would drop its laid-out box.
            if run.inlineMathBox != nil || run.indexTerm != nil {
                tokens.append(run)
                continue
            }
            for segment in lineBreaker.segments(in: run.text) where !segment.isEmpty {
                tokens.append(run.withText(segment))
            }
        }

        return tokens
    }

    private mutating func beginStructureElement(
        _ role: PDFTaggedContent.Role,
        attributes: PDFTaggedContent.Attributes = PDFTaggedContent.Attributes(),
    ) -> Int? {
        guard var builder = taggedContentBuilder else {
            return nil
        }
        let id = builder.beginElement(role: role, attributes: attributes)
        taggedContentBuilder = builder
        return id
    }

    private mutating func endStructureElement(_ id: Int?) {
        guard let id, var builder = taggedContentBuilder else {
            return
        }
        builder.endElement(id)
        taggedContentBuilder = builder
    }

    private mutating func beginMarkedContentForCurrentElement() -> Bool {
        guard markedContentDepth == 0,
              var builder = taggedContentBuilder,
              let mark = builder.markCurrentElement(onPage: currentPageIndex)
        else {
            return false
        }

        taggedContentBuilder = builder
        markedContentDepth += 1
        currentPage.beginMarkedContent(tag: PDFSyntax.Name(mark.role.rawValue), mcid: mark.mcid)
        return true
    }

    private mutating func endMarkedContentIfNeeded(_ didBegin: Bool) {
        guard didBegin else {
            return
        }
        currentPage.endMarkedContent()
        markedContentDepth = max(0, markedContentDepth - 1)
    }

    private mutating func beginArtifactIfTagged() -> Bool {
        guard markedContentDepth == 0, taggedContentBuilder != nil else {
            return false
        }
        markedContentDepth += 1
        currentPage.beginArtifact()
        return true
    }

    private mutating func drawRuns(
        _ runs: [PDFTextRun],
        x: Double,
        y: Double,
        maxWidth: Double? = nil,
        applyBidi: Bool = true,
    ) throws {
        guard !runs.isEmpty else {
            return
        }
        // Index markers are zero-width and draw nothing. Record them (and any terms a
        // markers-only paragraph left pending) against this line's page, then draw
        // the rest.
        let hasMarkers = runs.contains { $0.indexTerm != nil }
        if hasMarkers || !pendingIndexTerms.isEmpty {
            flushPendingIndexTerms()
            for case let term? in runs.map(\.indexTerm) {
                recordIndexTerm(term)
            }
        }
        let runs = hasMarkers ? runs.filter { $0.indexTerm == nil } : runs
        guard !runs.isEmpty else {
            return
        }
        markBlockQuoteContentDrawn()

        let marked = beginMarkedContentForCurrentElement()
        defer { endMarkedContentIfNeeded(marked) }

        if applyBidi, let bidiLine = try bidiLine(from: runs, x: x, maxWidth: maxWidth) {
            for run in bidiLine.visualRuns.sorted(by: { $0.sourceScalarOffset < $1.sourceScalarOffset }) {
                try drawBidiPositionedRun(run, y: y)
            }
            return
        }

        var cursor = x
        for run in runs {
            if let destination = run.namedDestination {
                addNamedDestination(destination, x: cursor, y: y + run.baselineOffset + run.size)
            }
            if let box = run.inlineMathBox {
                currentPage.beginActualText(run.text)
                try drawMathBox(box, x: cursor, baselineY: y + run.baselineOffset)
                currentPage.endMarkedContent()
                cursor += box.width
                continue
            }
            try currentPage.drawTextRun(
                run,
                x: cursor,
                y: y,
                fontSet: options.fontSet,
                embeddedFonts: embeddedFonts,
            )
            cursor += try textWidth(run)
        }
    }

    private func bidiLine(
        from runs: [PDFTextRun],
        x: Double,
        maxWidth: Double?,
    ) throws -> BidiLine? {
        guard let template = runs.first,
              runs.allSatisfy({ isSingleStyleBidiRun($0, matching: template) })
        else {
            return nil
        }

        let logicalText = runs.map(\.text).joined()
        let ordering = BidiParagraphOrdering()
        guard ordering.containsRightToLeftText(logicalText) else {
            return nil
        }

        let paragraph = try ordering.order(logicalText)
        // Measure each run from its LOGICAL source text, not the visually reordered
        // display text: a cursive run must be shaped in logical order to get its
        // (ligated) width, and for a non-joining run the width is the same either way
        // since advances do not depend on order.
        let logicalRuns = paragraph.visualRuns.map { run in
            template.withText(run.sourceText)
        }
        let lineWidth = try textWidth(logicalRuns)
        var cursor = x
        if paragraph.baseDirection == .rightToLeft, let maxWidth {
            cursor += max(0, maxWidth - lineWidth)
        }

        var positionedRuns: [BidiPositionedRun] = []
        for run in paragraph.visualRuns {
            let positioned = try positionedBidiRuns(for: run, template: template, x: cursor)
            positionedRuns.append(contentsOf: positioned)
            cursor += try textWidth(template.withText(run.sourceText))
        }
        return BidiLine(visualRuns: positionedRuns)
    }

    private func drawBidiPositionedRun(_ run: BidiPositionedRun, y: Double) throws {
        if let mapping = run.preShapedMapping,
           let entry = embeddedFonts.entry(for: run.sourceTextRun.font)
        {
            try currentPage.drawCIDText(
                mapping: mapping,
                fontResource: entry.resource,
                fontSize: run.sourceTextRun.size,
                x: run.x,
                y: y,
                color: run.sourceTextRun.color,
                rightToLeft: run.isRightToLeft,
                decorationsFor: run.sourceTextRun,
            )
            return
        }
        if let mapping = try mirroredBidiGlyphMapping(for: run),
           let entry = embeddedFonts.entry(for: run.sourceTextRun.font)
        {
            try currentPage.drawCIDText(
                mapping: mapping,
                fontResource: entry.resource,
                fontSize: run.sourceTextRun.size,
                x: run.x,
                y: y,
                color: run.sourceTextRun.color,
                decorationsFor: run.sourceTextRun,
            )
            return
        }

        try currentPage.drawTextRun(
            run.sourceTextRun,
            x: run.x,
            y: y,
            fontSet: options.fontSet,
            embeddedFonts: embeddedFonts,
        )
    }

    private func isSingleStyleBidiRun(_ run: PDFTextRun, matching template: PDFTextRun) -> Bool {
        run.font == template.font
            && run.size == template.size
            && run.color == template.color
            && run.underline == template.underline
            && run.strikethrough == template.strikethrough
            && run.linkDestination == nil
            && run.baselineOffset == template.baselineOffset
            && run.namedDestination == nil
    }

    private func positionedBidiRuns(
        for run: BidiParagraphOrdering.Run,
        template: PDFTextRun,
        x: Double,
    ) throws -> [BidiPositionedRun] {
        // A cursive run (Arabic and the other joining scripts) must be shaped as a
        // whole in LOGICAL order, because a letter's form depends on its neighbours.
        // The per-character path below would shape each letter in isolation, so it is
        // skipped here. The mapping stays logical (correct `/ToUnicode`); an RTL run
        // draws its glyphs reversed for visual placement.
        if ArabicShaper.containsJoiningScript(run.sourceText),
           let entry = embeddedFonts.entry(for: template.font),
           entry.arabicShaper.canShapeArabic
        {
            let mapping = try entry.arabicShaper.shapedMapping(text: run.sourceText, fontSize: template.size)
            return [BidiPositionedRun(
                sourceTextRun: template.withText(run.sourceText),
                displayText: run.sourceText,
                x: x,
                sourceScalarOffset: run.sourceScalarRange.lowerBound,
                preShapedMapping: mapping,
                isRightToLeft: run.direction == .rightToLeft,
            )]
        }

        // A pointed Hebrew run is shaped as a whole so its niqqud are placed on their
        // letters by GPOS. Hebrew does not join, but the per-character path below would
        // draw each mark at its nominal position; shaping keeps the mapping logical
        // (correct `/ToUnicode`) and an RTL run draws its glyphs reversed.
        if HebrewShaper.containsPointedHebrew(run.sourceText),
           let entry = embeddedFonts.entry(for: template.font),
           entry.hebrewShaper.canPositionHebrewMarks
        {
            let mapping = try entry.hebrewShaper.shapedMapping(text: run.sourceText, fontSize: template.size)
            return [BidiPositionedRun(
                sourceTextRun: template.withText(run.sourceText),
                displayText: run.sourceText,
                x: x,
                sourceScalarOffset: run.sourceScalarRange.lowerBound,
                preShapedMapping: mapping,
                isRightToLeft: run.direction == .rightToLeft,
            )]
        }

        let sourceCharacters = Array(run.sourceText)
        let displayCharacters = Array(run.displayText)
        let sourceScalarOffsets = scalarOffsetsByCharacter(in: run.sourceText)
        guard sourceCharacters.count == displayCharacters.count else {
            return [
                BidiPositionedRun(
                    sourceTextRun: template.withText(run.sourceText),
                    displayText: run.sourceText,
                    x: x,
                    sourceScalarOffset: run.sourceScalarRange.lowerBound,
                ),
            ]
        }

        var cursor = x
        var positionedRuns: [BidiPositionedRun] = []
        for displayIndex in sourceCharacters.indices {
            let sourceIndex = run.direction == .rightToLeft
                ? sourceCharacters.count - 1 - displayIndex
                : displayIndex
            let displayText = String(displayCharacters[displayIndex])
            let textRun = template.withText(String(sourceCharacters[sourceIndex]))
            positionedRuns.append(
                BidiPositionedRun(
                    sourceTextRun: textRun,
                    displayText: displayText,
                    x: cursor,
                    sourceScalarOffset: run.sourceScalarRange.lowerBound + sourceScalarOffsets[sourceIndex],
                ),
            )
            cursor += try textWidth(template.withText(displayText))
        }
        return positionedRuns
    }

    private func mirroredBidiGlyphMapping(for run: BidiPositionedRun) throws -> ShapedTextMapping? {
        guard run.sourceTextRun.text != run.displayText,
              let entry = embeddedFonts.entry(for: run.sourceTextRun.font),
              let sourceScalar = onlyScalar(in: run.sourceTextRun.text),
              let displayScalar = onlyScalar(in: run.displayText)
        else {
            return nil
        }
        let syntheticCode = try mirroredPDFCharacterCode(source: sourceScalar, display: displayScalar, entry: entry)

        let displayMapping = try embeddedFonts.mapping(
            for: run.sourceTextRun.withText(run.displayText),
            entry: entry,
        )
        guard let displayGlyph = displayMapping.glyphs.first, displayMapping.glyphs.count == 1 else {
            return nil
        }

        guard let syntheticScalar = UnicodeScalar(0x100000 + UInt32(syntheticCode)) else {
            throw PDFEmbeddedFontError.unavailableMirroredGlyphCode(source: sourceScalar, display: displayScalar)
        }
        let glyph = ShapedTextMapping.Glyph(
            glyphID: displayGlyph.glyphID,
            cid: syntheticCode,
            pdfCharacterCode: syntheticCode,
            advanceWidth: displayGlyph.advanceWidth,
            advance: displayGlyph.width,
            cmapScalar: syntheticScalar,
        )
        return try ShapedTextMapping(
            sourceText: run.sourceTextRun.text,
            clusters: [
                ShapedTextMapping.Cluster(
                    sourceScalarRange: 0 ..< 1,
                    normalizedText: run.displayText,
                    glyphs: [glyph],
                    toUnicodeScalars: [sourceScalar],
                ),
            ],
        )
    }

    private func mirroredPDFCharacterCode(
        source: UnicodeScalar,
        display: UnicodeScalar,
        entry: PDFEmbeddedFontCatalog.Entry,
    ) throws -> UInt16 {
        guard let pairOffset = mirroredPairOffset(source: source, display: display) else {
            throw PDFEmbeddedFontError.unavailableMirroredGlyphCode(source: source, display: display)
        }

        let code = UInt32(entry.resource.metadata.maxp.numGlyphs) + UInt32(pairOffset)
        guard code <= UInt16.max else {
            throw PDFEmbeddedFontError.unavailableMirroredGlyphCode(source: source, display: display)
        }
        return UInt16(code)
    }

    private func mirroredPairOffset(source: UnicodeScalar, display: UnicodeScalar) -> UInt16? {
        switch (source.value, display.value) {
        case (0x28, 0x29):
            1
        case (0x29, 0x28):
            2
        case (0x3C, 0x3E):
            3
        case (0x3E, 0x3C):
            4
        case (0x5B, 0x5D):
            5
        case (0x5D, 0x5B):
            6
        case (0x7B, 0x7D):
            7
        case (0x7D, 0x7B):
            8
        default:
            nil
        }
    }

    private func onlyScalar(in text: String) -> UnicodeScalar? {
        let scalars = Array(text.unicodeScalars)
        return scalars.count == 1 ? scalars[0] : nil
    }

    private func scalarOffsetsByCharacter(in text: String) -> [Int] {
        var offsets: [Int] = []
        var scalarOffset = 0
        for character in text {
            offsets.append(scalarOffset)
            scalarOffset += character.unicodeScalars.count
        }
        return offsets
    }

    private func textWidth(_ run: PDFTextRun) throws -> Double {
        if let box = run.inlineMathBox {
            return box.width
        }
        return try embeddedFonts.width(of: run, fallbackFontSet: options.fontSet)
    }

    private func textWidth(_ runs: [PDFTextRun]) throws -> Double {
        try runs.reduce(0) { partial, run in
            let width = try textWidth(run)
            return partial + width
        }
    }

    /// The width of a run without the spaces that end it. At the end of a line those
    /// spaces draw nothing, so they count neither against the measure nor toward the
    /// width a line is aligned by.
    private func inkWidth(_ run: PDFTextRun) throws -> Double {
        guard run.inlineMathBox == nil, run.text.last == " " else {
            return try textWidth(run)
        }
        var text = Substring(run.text)
        while text.last == " " {
            text.removeLast()
        }
        return text.isEmpty ? 0 : try textWidth(run.withText(String(text)))
    }

    /// Whether a token that passes the measure may stay on the line all the same:
    /// its ink ends inside the measure and only its spaces pass it, or it is spaces
    /// alone.
    private func hangs(_ token: PDFTextRun, after lineWidth: Double, maxWidth: Double) throws -> Bool {
        let ink = try inkWidth(token)
        return ink == 0 || lineWidth + ink <= maxWidth
    }

    /// The width of a drawn line: every run in full but the last, which is measured
    /// without the spaces that end it. Runs of nothing but spaces at the end of the
    /// line are left out the same way.
    private func inkWidth(ofLine runs: [PDFTextRun]) throws -> Double {
        var end = runs.endIndex
        while end > runs.startIndex {
            let run = runs[end - 1]
            guard run.inlineMathBox == nil, run.indexTerm == nil, run.text.allSatisfy({ $0 == " " }) else {
                break
            }
            end -= 1
        }
        guard end > runs.startIndex else {
            return 0
        }
        return try textWidth(Array(runs[..<(end - 1)])) + inkWidth(runs[end - 1])
    }

    private func mathLayout(for style: PDFOptions.ElementStyle) throws -> MathLayout {
        let font = standardFont(for: style.fontRole)
        return try MathLayout(
            font: MathFontStyle(font),
            color: MathColor(style.color),
            measureText: { try textWidth(PDFTextRun($0, face: mathFace)) },
            metrics: mathMetrics(for: style),
            // Draw each math symbol with its Unicode glyph when the active font
            // covers it, and fall back to the ASCII transliteration when it does
            // not. The portable base-14 profile covers no math glyphs (all ASCII),
            // an embedded math font covers them all (all glyphs), and a partial
            // font gets glyphs where it can. The radical sign is drawn as vector
            // strokes regardless. See MathTypeset SymbolStyle.
            symbolStyle: .unicodeWhereCovered,
            symbolCoverage: { embeddedFonts.covers($0, font: mathFace ?? font) },
        )
    }

    /// The face typeset formulas are drawn with: the embedded math font when there is one, else the text faces.
    private var mathFace: StandardFont? {
        embeddedFonts.entry(for: .math) == nil ? nil : .math
    }

    private func mathMetrics(for style: PDFOptions.ElementStyle) throws -> MathLayoutMetrics {
        let font = mathFace ?? standardFont(for: style.fontRole)
        if let metrics = embeddedFonts.entry(for: font)?.mathMetrics {
            return metrics
        }
        try requireEmbeddedMathFont(for: style)
        return .default
    }

    private func requireEmbeddedMathFont(for style: PDFOptions.ElementStyle) throws {
        guard options.mathTypesetting.requiresEmbeddedMathFont else {
            return
        }

        let font = standardFont(for: style.fontRole)
        let entry = embeddedFonts.entry(for: font)
        guard entry?.mathMetrics != nil else {
            throw MarkdownPDFError.missingEmbeddedMathFont(
                font: entry?.resource.baseName ?? font.baseName(in: options.fontSet),
            )
        }
    }

    private func style(for role: PDFOptions.ElementRole) -> PDFOptions.ElementStyle {
        var resolved = options.theme.style(for: role)
        resolved.lineHeightMultiplier *= lineHeightScale
        // Inside a block quote, the quote's own role supplies the body face and
        // color. Nested blocks otherwise render with `.paragraph` / `.list`, which
        // is why `.blockQuote`'s `fontRole` and `color` had no effect at all.
        //
        // The bullet is part of the quoted prose, so it takes the quote's color, but
        // keeps its own face: a quote in italics should not italicise its bullets.
        // Headings, code, and tables keep their roles entirely. A quote restyles
        // prose; a table is tabular data that happens to sit inside one, and its
        // header background and borders are set by the table's own roles.
        if blockQuoteDepth > 0 {
            let quote = options.theme.style(for: .blockQuote)
            switch role {
            case .paragraph, .list:
                resolved.fontRole = quote.fontRole
                resolved.color = quote.color
            case .listMarker:
                resolved.color = quote.color
            default:
                break
            }
        }
        return resolved
    }

    private func fontSize(for role: PDFOptions.ElementRole) -> Double {
        options.baseFontSize * style(for: role).sizeMultiplier
    }

    private func standardFont(for role: PDFOptions.FontRole) -> StandardFont {
        switch role {
        case .regular:
            .helvetica
        case .bold:
            .helveticaBold
        case .italic:
            .helveticaOblique
        case .monospaced:
            .courier
        }
    }

    private mutating func ensureSpace(_ height: Double) {
        if y - height < options.margins.bottom {
            startNewPage()
        }
    }

    /// Draws what `body` draws, moved to the top of the next page when it does not
    /// fit in what is left of this one and does fit on a page of its own. A body
    /// taller than a page is drawn where it stands and breaks as it always did.
    ///
    /// Nothing moves at the top of a page, where there is no more room to be had,
    /// nor directly under a heading: ``keepHeadingWithItsSection(at:in:contentsIndex:)``
    /// has already placed the heading for what follows it, and moving on from here
    /// would leave the heading behind.
    private mutating func keepTogether(_ body: (inout Layout) throws -> Void) throws {
        let followsHeading = headingEnd.map { $0.page == currentPageIndex && $0.y == y } ?? false
        if !isMeasuring, y < pageTopY, !followsHeading,
           try !fits(onFreshPage: false, body),
           try fits(onFreshPage: true, body)
        {
            startNewPage()
        }
        try body(&self)
    }

    /// Whether `body` draws without breaking a page, from here or from the top of a
    /// new page.
    ///
    /// The answer comes from running `body` itself on a copy of the layout, so it is
    /// the layout's own arithmetic and cannot drift from it. The copy draws on
    /// pages of its own and records structure and index hits in registries of its
    /// own, all discarded: page canvases are the only state the layout shares by
    /// reference, and nothing a block draws depends on what the registries hold.
    /// Blocks inside the copy are not measured again, which keeps the work linear in
    /// the nesting depth. Skipping them cannot change the answer: an inner block is
    /// only ever moved when it would break a page, and then the body does not fit.
    private func fits(onFreshPage: Bool, _ body: (inout Layout) throws -> Void) throws -> Bool {
        var trial = self
        trial.isMeasuring = true
        trial.pages = Array(repeating: PDFPageCanvas(), count: pages.count - 1) + [PDFPageCanvas()]
        trial.indexRegistry = IndexRegistry()
        if taggedContentBuilder != nil {
            trial.taggedContentBuilder = PDFTaggedContentBuilder()
        }
        if onFreshPage {
            trial.startNewPage()
        }
        let pageCount = trial.pages.count
        try body(&trial)
        return trial.pages.count == pageCount
    }

    /// Breaks the page before the heading at `index` when that keeps the heading
    /// with what ``PDFOptions/keepTogether`` ties to it.
    ///
    /// With ``PDFOptions/KeepTogether/sections`` that is every block up to the next
    /// heading. With ``PDFOptions/KeepTogether/listItems`` it is the first item of a
    /// list that follows the heading directly, since that item will not break. The
    /// larger group is tried first, and a group that fits on no page is left to the
    /// smaller one. `contentsIndex` is the block the table of contents is drawn
    /// before; a group that would hold the contents is left alone.
    private mutating func keepHeadingWithItsSection(
        at index: Int,
        in blocks: [MarkdownBlock],
        contentsIndex: Int?,
    ) throws {
        guard !options.keepTogether.isEmpty, !isMeasuring, y < pageTopY, blocks[index].isHeading else {
            return
        }

        var groups: [[MarkdownBlock]] = []
        if options.keepTogether.contains(.sections) {
            let end = blocks[(index + 1)...].firstIndex(where: \.isHeading) ?? blocks.endIndex
            let holdsContents = contentsIndex.map { $0 > index && $0 < end } ?? false
            if end > index + 1, !holdsContents {
                groups.append(Array(blocks[index ..< end]))
            }
        }
        if options.keepTogether.contains(.listItems),
           index + 1 < blocks.count,
           contentsIndex != index + 1,
           let firstItem = blocks[index + 1].firstListItemAlone
        {
            groups.append([blocks[index], firstItem])
        }

        for group in groups {
            let body: (inout Layout) throws -> Void = { layout in
                layout.keepHeadingWithNextBlock(group[0], isLast: false)
                for block in group {
                    try layout.render(block)
                }
            }
            if try fits(onFreshPage: false, body) {
                return
            }
            if try fits(onFreshPage: true, body) {
                startNewPage()
                return
            }
        }
    }

    private mutating func startNewPage() {
        pages.append(PDFPageCanvas())
        drawPageBackgroundIfNeeded()
        y = pageTopY
        // A quote whose first block broke the page before drawing anything has not
        // started yet. Move its origin, or it leaves a rule beside empty space.
        for index in blockQuoteFrames.indices where !blockQuoteFrames[index].hasDrawn {
            blockQuoteFrames[index].page = pages.count - 1
            blockQuoteFrames[index].top = pageTopY
        }
    }

    private mutating func drawPageBackgroundIfNeeded() {
        defer { currentPage.markContentStart() }
        guard let background = options.theme.pageBackground else {
            return
        }

        let artifact = beginArtifactIfTagged()
        currentPage.drawRectangle(
            x: 0,
            y: 0,
            width: options.pageSize.width,
            height: options.pageSize.height,
            stroke: nil,
            fill: background,
        )
        endMarkedContentIfNeeded(artifact)
    }

    private mutating func keepHeadingWithNextBlock(
        _ block: MarkdownBlock,
        isLast: Bool,
    ) {
        guard !isLast,
              case let .heading(level, _) = block
        else {
            return
        }

        let topSpacing = y < pageTopY - 1 ? headingTopSpacing(level) : 0
        let height = topSpacing + headingSize(level) * 1.8 + headingKeepWithNextHeight(level)
        ensureSpace(height)
    }

    private mutating func addHeadingTopSpacing(_ spacing: Double) {
        guard y < pageTopY - 1 else {
            return
        }

        y -= spacing
    }

    private mutating func addHeadingDestination(
        level: Int,
        content: [MarkdownInline],
        y: Double,
    ) {
        let title = plainText(content).trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "Heading" : title
        currentPage.addHeadingDestination(
            PDFHeadingDestination(
                name: headingNames.uniqueName(for: displayTitle),
                title: displayTitle,
                level: level,
                x: options.headingDestinationsAtPageTop ? 0 : options.margins.left,
                y: options.headingDestinationsAtPageTop ? options.pageSize.height : min(options.pageSize.height, y),
                inOutline: level <= min(max(options.outlineMaxHeadingLevel, 1), 6),
            ),
        )
    }

    private mutating func addNamedDestination(_ name: String, x: Double, y: Double) {
        guard registeredNamedDestinations.insert(name).inserted else {
            return
        }

        currentPage.addNamedDestination(
            PDFHeadingDestination(
                name: name,
                title: name,
                level: 6,
                x: x,
                y: min(options.pageSize.height, y),
            ),
        )
    }

    private func plainText(_ inlines: [MarkdownInline]) -> String {
        inlines.map(plainText).joined()
    }

    private func plainText(_ inline: MarkdownInline) -> String {
        switch inline {
        case let .text(text), let .code(text):
            text
        case let .inlineMath(math):
            (try? MathParser().parse(math.source))?.linearizedText ?? math.delimitedSource
        case .softBreak, .lineBreak:
            " "
        case let .emphasis(children), let .strong(children), let .strikethrough(children):
            plainText(children)
        case let .link(children, _, _):
            plainText(children)
        case let .image(alt, source, _):
            alt.isEmpty ? source : alt
        case let .footnoteReference(label):
            "[^\(label)]"
        case .indexMarker:
            ""
        }
    }

    private func plainText(_ block: MarkdownBlock) -> String {
        switch block {
        case let .heading(_, content), let .paragraph(content):
            plainText(content)
        case let .blockQuote(blocks):
            blocks.map(plainText).joined(separator: " ")
        case let .unorderedList(items), let .orderedList(_, items):
            items.flatMap(\.blocks).map(plainText).joined(separator: " ")
        case let .codeBlock(_, code):
            code
        case let .displayMath(math):
            (try? MathParser().parse(math.source))?.linearizedText ?? math.delimitedSource
        case let .table(table):
            (table.headers + table.rows.flatMap(\.self)).map { plainText($0) }.joined(separator: " ")
        case .thematicBreak, .pageBreak:
            ""
        case let .html(html):
            html
        case let .footnoteDefinition(_, blocks):
            blocks.map(plainText).joined(separator: " ")
        }
    }

    private func headingTopSpacing(_ level: Int) -> Double {
        options.baseFontSize * style(for: .heading(level: level)).spacingBeforeMultiplier
    }

    private func headingKeepWithNextHeight(_ level: Int) -> Double {
        switch level {
        case 1, 2:
            options.baseFontSize * 9.0
        case 3:
            options.baseFontSize * 4.5
        default:
            options.baseFontSize * 2.6
        }
    }

    private func headingSize(_ level: Int) -> Double {
        fontSize(for: .heading(level: level))
    }

    private var bodyLineHeight: Double {
        let role: PDFOptions.ElementRole = listDepth > 0 ? .list : .paragraph
        return fontSize(for: role) * style(for: role).lineHeightMultiplier
    }

    /// Vertical space a figure (Mermaid diagram, native chart, standalone image)
    /// leaves beneath itself.
    ///
    /// `plan.height` covers the drawn frame, including its own internal padding.
    /// The 12pt sits entirely below that frame, and a following paragraph's
    /// ascender consumes most of it, so the next line reads as touching the frame.
    /// Add the block model's ``paragraphSpacing`` on top, the same separation a
    /// paragraph leaves behind it.
    ///
    /// Only the drawn height is reserved with `ensureSpace`; this trailing gap is
    /// applied to `y` afterwards. Reserving it would push a figure that fits onto
    /// the next page for the sake of whitespace that may have nothing after it.
    private var figureTrailingSpacing: Double {
        12 + paragraphSpacing
    }

    private var paragraphSpacing: Double {
        if listDepth > 0 {
            return 2
        }
        return options.baseFontSize * style(for: .paragraph).spacingAfterMultiplier
    }

    private var codeBlockPadding: Double {
        6
    }

    /// How far the cursor drops below a code block's bottom edge.
    ///
    /// The cursor is the next line's baseline, so the glyphs rise an ascender
    /// (`0.75 * size`, the same top-of-line-box convention block quotes use) above
    /// it. The drop therefore carries two parts: the ascender, so the next line's
    /// top does not touch the box, plus the visible gap that sits above the box,
    /// which is the previous paragraph's trailing spacing plus its line height less
    /// the descender (`0.25 * size`). Space after the box then equals the space
    /// before it.
    private var codeBlockFollowingGap: Double {
        let role: PDFOptions.ElementRole = listDepth > 0 ? .list : .paragraph
        let size = fontSize(for: role)
        let visibleGapAbove = paragraphSpacing + bodyLineHeight - size * 0.25
        return visibleGapAbove + size * 0.75
    }

    private var codeBlockTabWidth: Int {
        4
    }

    private var listTrailingSpacing: Double {
        if listDepth > 1 {
            return 1
        }
        return options.baseFontSize * style(for: .list).spacingAfterMultiplier
    }

    private var blockQuoteTopSpacing: Double {
        options.baseFontSize * style(for: .blockQuote).spacingBeforeMultiplier
    }

    private var blockQuoteBottomSpacing: Double {
        options.baseFontSize * style(for: .blockQuote).spacingAfterMultiplier
    }

    /// The narrowest content column any nested container is allowed to leave, so
    /// runaway indentation cannot drive the usable width to zero. An inch holds
    /// several characters, enough to keep wrapping sane at any nesting depth.
    private static let minimumIndentedContentWidth: Double = 72

    /// Indents the left margin for a nested container, but never so far that the
    /// content column would drop below ``minimumIndentedContentWidth``.
    ///
    /// List items (`24`) and block quotes (`14`) both indent through here. Placing
    /// the clamp on only one of them left the other free to push the margin past
    /// the page edge: a list of quotes, or quotes alternating with lists, drove the
    /// content column negative and reproduced the page-count explosion the clamp
    /// exists to prevent. Past the clamp, further nesting of either kind stops
    /// indenting and content stays at the deepest usable column. The caller saves
    /// and restores the previous margin, so the clamp only bounds the descent.
    private mutating func indentLeftMargin(by amount: Double) {
        let deepest = options.pageSize.width - options.margins.right - Self.minimumIndentedContentWidth
        options.margins.left = min(options.margins.left + amount, max(options.margins.left, deepest))
    }

    private var contentWidth: Double {
        options.pageSize.width - options.margins.left - options.margins.right
    }

    private var contentHeight: Double {
        options.pageSize.height - options.margins.top - options.margins.bottom
    }

    private var availablePageHeight: Double {
        y - options.margins.bottom
    }

    /// The tallest a standalone image may be drawn: the configured fraction of the
    /// page height, clamped to a sane range and to the content area.
    private var imageMaxHeight: Double {
        let requested = options.imageMaxHeightFraction.isFinite
            ? options.imageMaxHeightFraction
            : PDFOptions.defaultImageMaxHeightFraction
        let fraction = min(max(requested, 0.05), 1)
        return max(1, min(contentHeight, options.pageSize.height * fraction))
    }

    /// The configured line height scale, clamped to the supported range. A value that
    /// is not finite falls back to the default.
    private var lineHeightScale: Double {
        guard options.lineHeightScale.isFinite else {
            return PDFOptions.defaultLineHeightScale
        }
        let range = PDFOptions.lineHeightScaleRange
        return min(max(options.lineHeightScale, range.lowerBound), range.upperBound)
    }

    private var pageTopY: Double {
        options.pageSize.height - options.margins.top
    }

    private var currentPage: PDFPageCanvas {
        pages[pages.count - 1]
    }

    private var currentPageIndex: Int {
        pages.count - 1
    }

    private var chartTitleSize: Double {
        options.baseFontSize * 0.95
    }

    private var chartLabelSize: Double {
        max(7.2, options.baseFontSize * 0.72)
    }

    private var chartPalette: [PDFColor] {
        [
            PDFColor(red: 0.11, green: 0.47, blue: 0.71),
            PDFColor(red: 0.89, green: 0.47, blue: 0.20),
            PDFColor(red: 0.20, green: 0.63, blue: 0.17),
            PDFColor(red: 0.58, green: 0.40, blue: 0.74),
            PDFColor(red: 0.55, green: 0.34, blue: 0.29),
            PDFColor(red: 0.89, green: 0.10, blue: 0.11),
            PDFColor(red: 0.50, green: 0.50, blue: 0.50),
            PDFColor(red: 0.74, green: 0.74, blue: 0.13),
        ]
    }

    private enum ChartTextAlignment {
        case left
        case center
        case right
    }

    private enum ChartRenderPlanResult {
        case plan(ChartRenderPlan)
        case fallback(String)
    }

    private struct ChartRenderPlan {
        var chart: ChartBlock
        var height: Double
        var plotFrame: ChartFrame?
        var xTicks: [Double]
        var yTicks: [Double]
        var xDomain: (min: Double, max: Double)
        var yDomain: (min: Double, max: Double)
        var pieRadius: Double?
        var legendWidth: Double?
    }

    private struct ChartFrame {
        var left: Double
        var top: Double
        var width: Double
        var height: Double

        var right: Double {
            left + width
        }

        var bottom: Double {
            top - height
        }
    }

    private enum MermaidMeasurementResult {
        case measurements([String: MermaidNodeMeasurement])
        case fallback(String)
    }

    private enum MermaidRenderPlanResult {
        case plan(MermaidRenderPlan)
        case fallback(String)
    }

    private struct MermaidRenderPlan {
        var height: Double
        var boxes: [MermaidNodeBox]
        var edges: [MermaidDiagram.Edge]
        var groups: [MermaidGroupBox] = []
    }

    /// A node or a group, measured, before it is placed.
    private struct MermaidLayoutItem {
        var id: String
        var width: Double
        var height: Double
    }

    private struct MermaidPlacement {
        var id: String
        var x: Double
        var topOffset: Double
    }

    private struct MermaidLayout {
        var width: Double
        /// The offset of the bottom edge of the last row or the tallest column.
        var bottom: Double
        var contentHeight: Double
        var placements: [MermaidPlacement]
    }

    private enum MermaidLayoutResult {
        case layout(MermaidLayout)
        case fallback(String)
    }

    /// A group laid out in its own frame: its title, then its members in relative positions.
    private struct MermaidGroupLayout {
        var title: [[PDFTextRun]]
        var fontSize: Double
        var lineHeight: Double
        var padding: Double
        var width: Double
        var height: Double
        /// The distance from the top of the frame to the top of its members.
        var contentTop: Double
        var inner: MermaidLayout
    }

    private enum MermaidGroupLayoutResult {
        case layout(MermaidGroupLayout)
        case fallback(String)
    }

    private struct MermaidGroupBox {
        var id: String
        var titleLines: [[PDFTextRun]]
        var x: Double
        var topOffset: Double
        var width: Double
        var height: Double
        var fontSize: Double
        var lineHeight: Double
        var padding: Double

        init(layout: MermaidGroupLayout, id: String, x: Double, topOffset: Double) {
            self.id = id
            titleLines = layout.title
            self.x = x
            self.topOffset = topOffset
            width = layout.width
            height = layout.height
            fontSize = layout.fontSize
            lineHeight = layout.lineHeight
            padding = layout.padding
        }

        func frame(topY: Double) -> MermaidFrame {
            MermaidFrame(left: x, top: topY - topOffset, width: width, height: height)
        }
    }

    private struct MermaidNodeMeasurement {
        var id: String
        var labelLines: [[PDFTextRun]]
        var width: Double
        var height: Double
        var fontSize: Double
        var lineHeight: Double
        var verticalPadding: Double
        var shape: MermaidDiagram.Node.Shape = .rectangle
        /// The height of the text block; the box is taller than it for a diamond, so the text sits in the middle of it.
        var textHeight: Double = 0
    }

    private struct MermaidNodeBox {
        var id: String
        var shape: MermaidDiagram.Node.Shape
        var textHeight: Double
        var labelLines: [[PDFTextRun]]
        var x: Double
        var topOffset: Double
        var width: Double
        var height: Double
        var fontSize: Double
        var lineHeight: Double
        var verticalPadding: Double

        init(measurement: MermaidNodeMeasurement, x: Double, topOffset: Double) {
            id = measurement.id
            shape = measurement.shape
            textHeight = measurement.textHeight
            labelLines = measurement.labelLines
            self.x = x
            self.topOffset = topOffset
            width = measurement.width
            height = measurement.height
            fontSize = measurement.fontSize
            lineHeight = measurement.lineHeight
            verticalPadding = measurement.verticalPadding
        }

        func frame(topY: Double) -> MermaidFrame {
            let top = topY - topOffset
            return MermaidFrame(left: x, top: top, width: width, height: height)
        }
    }

    private struct MermaidFrame {
        var left: Double
        var top: Double
        var width: Double
        var height: Double

        var right: Double {
            left + width
        }

        var bottom: Double {
            top - height
        }

        var centerX: Double {
            left + width / 2
        }

        var centerY: Double {
            top - height / 2
        }

        func contains(_ child: MermaidFrame) -> Bool {
            child.left >= left
                && child.right <= right
                && child.top <= top
                && child.bottom >= bottom
        }

        func intersects(_ other: MermaidFrame) -> Bool {
            left < other.right
                && right > other.left
                && bottom < other.top
                && top > other.bottom
        }

        func expanded(by amount: Double) -> MermaidFrame {
            MermaidFrame(
                left: left - amount,
                top: top + amount,
                width: width + amount * 2,
                height: height + amount * 2,
            )
        }
    }

    private struct MermaidPoint {
        var x: Double
        var y: Double
    }
}

private extension PDFTextRun {
    func withText(_ newText: String) -> PDFTextRun {
        PDFTextRun(
            text: newText,
            font: font,
            size: size,
            color: color,
            underline: underline,
            strikethrough: strikethrough,
            linkDestination: linkDestination,
            baselineOffset: baselineOffset,
            namedDestination: namedDestination,
            inlineMathBox: inlineMathBox,
            isIndexable: isIndexable,
        )
    }
}

// MARK: - Board tiles

/// Drawing of the board tiles: a pill, a progress bar and a row of figure cards, in the PDF.
///
/// The colors are the hues of the page's status colors in print (blue running, gray waiting, amber blocked, green
/// done, red failed), and the word of the state is always printed, so no color is ever the only signal. Every figure
/// is drawn from the exact numbers of ``TileBlock``.
extension Layout {
    /// The tile type of a ```` ```tile TYPE ```` fence, or nil when the fence is not a tile fence.
    private func tileFenceType(_ info: String?) -> String? {
        let words = info?.split(whereSeparator: \.isWhitespace).map(String.init) ?? []
        guard words.count == 2, words[0].lowercased() == "tile" else {
            return nil
        }
        return words[1].lowercased()
    }

    private mutating func renderTileBlock(type: String, code: String) throws {
        switch TileBlock.parse(type: type, body: code) {
        case let .tile(tile):
            switch tile {
            case let .pill(pill): try drawPill(pill)
            case let .progress(progress): try drawProgress(progress)
            case let .kpi(cards): try drawKPI(cards)
            case let .timeline(timeline): try drawTimeline(timeline)
            case let .flow(flow): try drawFlow(flow)
            case let .callout(callout): try drawCallout(callout)
            case let .cta(cta): try drawCTA(cta)
            case let .hero(hero): try drawHero(hero)
            case let .cards(cards): try drawCards(cards)
            }
        case let .unsupported(reason):
            try renderCodeBlock("Unsupported tile: \(reason)\n\(code)")
        }
    }

    private static func tileFill(_ status: TileBlock.Status) -> PDFColor {
        switch status {
        case .running: PDFColor(red: 0.86, green: 0.92, blue: 1.0)
        case .waiting: PDFColor(red: 0.93, green: 0.94, blue: 0.95)
        case .blocked: PDFColor(red: 1.0, green: 0.93, blue: 0.78)
        case .done: PDFColor(red: 0.86, green: 0.96, blue: 0.88)
        case .failed: PDFColor(red: 1.0, green: 0.88, blue: 0.88)
        }
    }

    private static func tileInk(_ status: TileBlock.Status) -> PDFColor {
        switch status {
        case .running: PDFColor(red: 0.11, green: 0.26, blue: 0.73)
        case .waiting: PDFColor(red: 0.33, green: 0.37, blue: 0.42)
        case .blocked: PDFColor(red: 0.57, green: 0.31, blue: 0.04)
        case .done: PDFColor(red: 0.08, green: 0.46, blue: 0.21)
        case .failed: PDFColor(red: 0.69, green: 0.13, blue: 0.13)
        }
    }

    private static func toneColor(_ tone: TileBlock.Tone) -> PDFColor {
        switch tone {
        case .good: PDFColor(red: 0.08, green: 0.46, blue: 0.21)
        case .bad: PDFColor(red: 0.69, green: 0.13, blue: 0.13)
        case .neutral: PDFColor(red: 0.33, green: 0.37, blue: 0.42)
        }
    }

    private static let tileRule = PDFColor(red: 0.8, green: 0.82, blue: 0.85)
    private static let tileMuted = PDFColor(red: 0.35, green: 0.38, blue: 0.43)

    private func tileRun(_ text: String, bold: Bool = false, size: Double, color: PDFColor) -> PDFTextRun {
        PDFTextRun(text: text, font: standardFont(for: bold ? .bold : .regular), size: size, color: color)
    }

    // MARK: pill

    private mutating func drawPill(_ pill: TileBlock.Pill) throws {
        let size = fontSize(for: .paragraph)
        let padding = 5.0
        let height = size + 2 * padding
        let label = pill.label.map { tileRun($0 + "  ", size: size, color: .black) }
        let word = tileRun(pill.status.rawValue, bold: true, size: size, color: Self.tileInk(pill.status))
        // the label's trailing spaces are part of its advance here: they are the gap to the state word
        let labelWidth = try label.map { try textWidth([$0]) } ?? 0
        let wordWidth = try inkWidth(ofLine: [word])
        let width = min(contentWidth, labelWidth + wordWidth + 4 * padding)
        ensureSpace(height)
        let figure = beginStructureElement(
            .figure, attributes: PDFTaggedContent.Attributes(alternateDescription: "Status"),
        )
        let marked = beginMarkedContentForCurrentElement()
        markBlockQuoteContentDrawn()
        let left = options.margins.left
        currentPage.drawRectangle(
            x: left, y: y - height, width: width, height: height,
            stroke: Self.tileInk(pill.status), fill: Self.tileFill(pill.status),
        )
        let baseline = y - padding - size * 0.8
        var x = left + padding * 2
        if let label {
            try drawRuns([label], x: x, y: baseline)
            x += labelWidth
        }
        try drawRuns([word], x: x, y: baseline)
        endMarkedContentIfNeeded(marked)
        endStructureElement(figure)
        y -= height + figureTrailingSpacing
    }

    // MARK: progress

    private mutating func drawProgress(_ progress: TileBlock.Progress) throws {
        let size = fontSize(for: .paragraph)
        let barHeight = 8.0
        let textHeight = size * 1.4
        let height = textHeight + 4 + barHeight
        ensureSpace(height)
        let name = progress.label ?? "Progress"
        let figure = beginStructureElement(
            .figure, attributes: PDFTaggedContent.Attributes(alternateDescription: "\(name): \(progress.numbers)"),
        )
        let marked = beginMarkedContentForCurrentElement()
        markBlockQuoteContentDrawn()
        let left = options.margins.left
        let baseline = y - size
        var x = left
        if let label = progress.label {
            let labelRun = tileRun(label + " ", size: size, color: .black)
            try drawRuns([labelRun], x: x, y: baseline)
            x += try inkWidth(ofLine: [labelRun]) + size * 0.3
        }
        try drawRuns([tileRun(progress.numbers, bold: true, size: size, color: .black)], x: x, y: baseline)
        let trackTop = y - textHeight - 4
        currentPage.drawRectangle(
            x: left, y: trackTop - barHeight, width: contentWidth, height: barHeight,
            stroke: Self.tileRule, fill: PDFColor(red: 0.93, green: 0.94, blue: 0.96),
        )
        let fillWidth = contentWidth * Double(progress.hundredths) / 10000
        if fillWidth > 0 {
            currentPage.drawRectangle(
                x: left, y: trackTop - barHeight, width: fillWidth, height: barHeight,
                stroke: nil, fill: Self.tileInk(progress.status),
            )
        }
        endMarkedContentIfNeeded(marked)
        endStructureElement(figure)
        y -= height + figureTrailingSpacing
    }

    // MARK: timeline

    /// Dated events down a rail: a dot on the rail at each event, the date (and time) small above the title, then the body.
    /// An event is kept in one piece on a page; the rail is drawn for the length of each event and the gap after it.
    private mutating func drawTimeline(_ timeline: TileBlock.Timeline) throws {
        let size = fontSize(for: .paragraph)
        let railX = options.margins.left + 5
        let textX = options.margins.left + 20
        let textWidth = contentWidth - 20
        let gap = size * 0.9
        let accent = PDFColor(red: 0.11, green: 0.26, blue: 0.73)
        for (index, event) in timeline.events.enumerated() {
            let stamp = event.time.map { event.date + " " + $0 } ?? event.date
            let titleLines = try wrappedLines([tileRun(event.title, bold: true, size: size, color: .black)], maxWidth: textWidth)
            let bodyLines = try event.body.map {
                try wrappedLines([tileRun($0, size: size, color: .black)], maxWidth: textWidth)
            } ?? []
            let lineHeight = size * 1.35
            let height = lineHeight * Double(1 + titleLines.count + bodyLines.count)
            ensureSpace(height)
            let figure = beginStructureElement(
                .figure, attributes: PDFTaggedContent.Attributes(alternateDescription: "Timeline event"),
            )
            let marked = beginMarkedContentForCurrentElement()
            markBlockQuoteContentDrawn()
            let isLast = index == timeline.events.count - 1
            let railBottom = y - height - (isLast ? 0 : gap)
            let railTop = index == 0 ? y - lineHeight * 0.6 : y + gap
            currentPage.drawLine(x1: railX, y1: railTop, x2: railX, y2: railBottom, width: 1.2, color: Self.tileRule)
            var baseline = y - size * 0.8
            currentPage.drawCircle(x: railX, y: baseline + size * 0.3, radius: 3.2, stroke: nil, fill: accent)
            try drawRuns([tileRun(stamp, size: size * 0.85, color: Self.tileMuted)], x: textX, y: baseline)
            for line in titleLines + bodyLines {
                baseline -= lineHeight
                try drawRuns(line, x: textX, y: baseline)
            }
            endMarkedContentIfNeeded(marked)
            endStructureElement(figure)
            y -= height + (isLast ? figureTrailingSpacing : gap)
        }
    }

    // MARK: callout, cta, hero, cards

    private static let tileAccent = PDFColor(red: 0.11, green: 0.26, blue: 0.73)

    /// Inline Markdown as wrapped lines of runs: emphasis, code and links are kept, a link run carries its destination.
    private func panelLines(
        _ markdown: String,
        bold: Bool = false,
        size: Double,
        color: PDFColor = .black,
        width: Double,
    ) throws -> [[PDFTextRun]] {
        let font = standardFont(for: bold ? .bold : .regular)
        let runs = try flatten(InlineParser().parse(markdown), font: font, size: size, color: color)
        return try wrappedLines(runs, maxWidth: width)
    }

    /// Draws the lines from `top`, one below the other, and returns the baseline of the last one.
    private mutating func drawPanelLines(_ lines: [[PDFTextRun]], x: Double, top: Double, lineHeight: Double) throws -> Double {
        var baseline = top
        for line in lines {
            baseline -= lineHeight
            try drawRuns(line, x: x, y: baseline + lineHeight * 0.22)
        }
        return baseline
    }

    private mutating func drawCallout(_ callout: TileBlock.Callout) throws {
        let size = fontSize(for: .paragraph)
        let padding = 10.0
        let lineHeight = size * 1.35
        let inner = contentWidth - 2 * padding - 4
        let title = try panelLines(callout.title, bold: true, size: size, width: inner)
        let body = try callout.body.map { try panelLines($0, size: size, width: inner) } ?? []
        let height = 2 * padding + lineHeight * Double(title.count + body.count)
        ensureSpace(height)
        let figure = beginStructureElement(.figure, attributes: PDFTaggedContent.Attributes(alternateDescription: "Note"))
        let marked = beginMarkedContentForCurrentElement()
        markBlockQuoteContentDrawn()
        let left = options.margins.left
        currentPage.drawRectangle(
            x: left, y: y - height, width: contentWidth, height: height,
            stroke: Self.tileRule, fill: PDFColor(red: 0.94, green: 0.96, blue: 1.0),
        )
        currentPage.drawRectangle(x: left, y: y - height, width: 3.5, height: height, stroke: nil, fill: Self.tileAccent)
        let last = try drawPanelLines(title + body, x: left + padding + 4, top: y - padding, lineHeight: lineHeight)
        _ = last
        endMarkedContentIfNeeded(marked)
        endStructureElement(figure)
        y -= height + figureTrailingSpacing
    }

    /// A row of buttons: the label is a link, the first button is filled and the others outlined. Returns the height of the row.
    private mutating func drawButtons(_ buttons: [TileBlock.Button], x: Double, top: Double, size: Double) throws -> Double {
        let height = size + 10
        var cursor = x
        for (index, button) in buttons.enumerated() {
            let fill = index == 0
            let label = PDFTextRun(
                text: button.label, font: standardFont(for: .bold), size: size,
                color: fill ? .white : Self.tileAccent, linkDestination: button.destination,
            )
            let width = try inkWidth(ofLine: [label]) + 20
            currentPage.drawRoundedRectangle(
                x: cursor, y: top - height, width: width, height: height, radius: 5,
                stroke: Self.tileAccent, fill: fill ? Self.tileAccent : .white, lineWidth: 1,
            )
            try drawRuns([label], x: cursor + 10, y: top - height + 5 + size * 0.2)
            cursor += width + 8
        }
        return height
    }

    private mutating func drawCTA(_ cta: TileBlock.CTA) throws {
        let size = fontSize(for: .paragraph)
        let padding = 12.0
        let lineHeight = size * 1.35
        let inner = contentWidth - 2 * padding
        let title = try panelLines(cta.title, bold: true, size: size * 1.2, width: inner)
        let body = try cta.body.map { try panelLines($0, size: size, width: inner) } ?? []
        let buttonsHeight = cta.buttons.isEmpty ? 0 : size + 10 + 8
        let height = 2 * padding + lineHeight * 1.2 * Double(title.count) + lineHeight * Double(body.count) + buttonsHeight
        ensureSpace(height)
        let figure = beginStructureElement(.figure, attributes: PDFTaggedContent.Attributes(alternateDescription: cta.title))
        let marked = beginMarkedContentForCurrentElement()
        markBlockQuoteContentDrawn()
        let left = options.margins.left
        currentPage.drawRoundedRectangle(
            x: left, y: y - height, width: contentWidth, height: height, radius: 8,
            stroke: Self.tileRule, fill: PDFColor(red: 0.97, green: 0.98, blue: 0.99), lineWidth: 1,
        )
        var cursor = try drawPanelLines(title, x: left + padding, top: y - padding, lineHeight: lineHeight * 1.2)
        cursor = try drawPanelLines(body, x: left + padding, top: cursor, lineHeight: lineHeight)
        if !cta.buttons.isEmpty {
            _ = try drawButtons(cta.buttons, x: left + padding, top: cursor - 8, size: size)
        }
        endMarkedContentIfNeeded(marked)
        endStructureElement(figure)
        y -= height + figureTrailingSpacing
    }

    private mutating func drawHero(_ hero: TileBlock.Hero) throws {
        let size = fontSize(for: .paragraph)
        let lineHeight = size * 1.35
        let eyebrow = try hero.eyebrow.map { try panelLines($0, size: size * 0.85, color: Self.tileMuted, width: contentWidth) } ?? []
        let title = try hero.title.map { try panelLines($0, bold: true, size: size * 1.9, width: contentWidth) } ?? []
        let body = try hero.body.map { try panelLines($0, size: size * 1.1, width: contentWidth) } ?? []
        let buttonsHeight = hero.buttons.isEmpty ? 0 : size + 10 + 10
        let height = lineHeight * 0.9 * Double(eyebrow.count) + lineHeight * 2.2 * Double(title.count)
            + lineHeight * 1.15 * Double(body.count) + buttonsHeight + 6
        ensureSpace(height)
        let figure = beginStructureElement(.figure, attributes: PDFTaggedContent.Attributes(alternateDescription: hero.title ?? "Introduction"))
        let marked = beginMarkedContentForCurrentElement()
        markBlockQuoteContentDrawn()
        let left = options.margins.left
        var cursor = try drawPanelLines(eyebrow, x: left, top: y, lineHeight: lineHeight * 0.9)
        cursor = try drawPanelLines(title, x: left, top: cursor - 2, lineHeight: lineHeight * 2.2)
        cursor = try drawPanelLines(body, x: left, top: cursor - 2, lineHeight: lineHeight * 1.15)
        if !hero.buttons.isEmpty {
            _ = try drawButtons(hero.buttons, x: left, top: cursor - 10, size: size)
        }
        endMarkedContentIfNeeded(marked)
        endStructureElement(figure)
        y -= height + figureTrailingSpacing
    }

    private mutating func drawCards(_ grid: TileBlock.Cards) throws {
        let size = fontSize(for: .paragraph)
        let gap = 10.0
        let padding = 10.0
        let lineHeight = size * 1.3
        let columns = Double(grid.columns)
        let width = (contentWidth - gap * (columns - 1)) / columns
        let inner = width - 2 * padding
        let rows = stride(from: 0, to: grid.cards.count, by: grid.columns).map {
            Array(grid.cards[$0 ..< min($0 + grid.columns, grid.cards.count)])
        }
        for row in rows {
            struct Prepared {
                var badge: [[PDFTextRun]]
                var title: [[PDFTextRun]]
                var body: [[PDFTextRun]]
            }
            var prepared: [Prepared] = []
            for card in row {
                let titleRuns = try panelLines(card.title, bold: true, size: size * 1.05, color: card.link == nil ? .black : Self.tileAccent, width: inner)
                    .map { line in card.link.map { destination in line.map { var run = $0
                        run.linkDestination = destination
                        return run
                    } } ?? line }
                try prepared.append(Prepared(
                    badge: card.badge.map { try panelLines($0, size: size * 0.8, color: Self.tileMuted, width: inner) } ?? [],
                    title: titleRuns,
                    body: card.body.map { try panelLines($0, size: size, width: inner) } ?? [],
                ))
            }
            let lines = prepared.map { $0.badge.count + $0.title.count + $0.body.count }.max() ?? 1
            let height = 2 * padding + lineHeight * Double(lines)
            ensureSpace(height)
            let figure = beginStructureElement(.figure, attributes: PDFTaggedContent.Attributes(alternateDescription: "Cards"))
            let marked = beginMarkedContentForCurrentElement()
            markBlockQuoteContentDrawn()
            for (index, item) in prepared.enumerated() {
                let left = options.margins.left + Double(index) * (width + gap)
                currentPage.drawRoundedRectangle(
                    x: left, y: y - height, width: width, height: height, radius: 6,
                    stroke: Self.tileRule, fill: PDFColor(red: 0.99, green: 0.99, blue: 1.0), lineWidth: 1,
                )
                var cursor = try drawPanelLines(item.badge, x: left + padding, top: y - padding, lineHeight: lineHeight)
                cursor = try drawPanelLines(item.title, x: left + padding, top: cursor, lineHeight: lineHeight)
                _ = try drawPanelLines(item.body, x: left + padding, top: cursor, lineHeight: lineHeight)
            }
            endMarkedContentIfNeeded(marked)
            endStructureElement(figure)
            y -= height + gap
        }
        y += gap - figureTrailingSpacing - 4
    }

    // MARK: flow

    /// A dependency graph: rounded boxes in columns, outlined and tinted by their state, joined by curved arrows, with the title above when one is
    /// written. The units of the layout are the page's (the SAME closed form as the SVG), scaled by one factor so a wide picture fits the measure.
    private mutating func drawFlow(_ flow: TileBlock.Flow) throws {
        let size = fontSize(for: .paragraph)
        if let title = flow.title {
            ensureSpace(size * 2.4)
            try drawRuns([tileRun(title, bold: true, size: size, color: .black)], x: options.margins.left, y: y - size)
            y -= size * 1.8
        }
        let layout = flow.layout
        typealias Units = TileBlock.Flow.Layout
        let scale = min(1.0, contentWidth / Double(layout.width))
        let height = Double(layout.height) * scale
        ensureSpace(height)
        let alternative = flow.edges
            .map { "\(flow.nodes[$0.source].shown) to \(flow.nodes[$0.target].shown)" }
            .joined(separator: "; ")
        let figure = beginStructureElement(
            .figure,
            attributes: PDFTaggedContent.Attributes(alternateDescription: alternative.isEmpty ? flow.title ?? "Flow" : alternative),
        )
        let marked = beginMarkedContentForCurrentElement()
        markBlockQuoteContentDrawn()
        let left = options.margins.left
        let top = y
        func px(_ units: Int) -> Double {
            left + Double(units) * scale
        }
        func py(_ units: Int) -> Double {
            top - Double(units) * scale
        }
        let edgeColor = PDFColor(red: 0.55, green: 0.58, blue: 0.63)
        for edge in flow.edges {
            let start = layout.x(ofLayer: layout.layers[edge.source]) + Units.nodeWidth
            let end = layout.x(ofLayer: layout.layers[edge.target])
            let startY = layout.y(ofRow: layout.rows[edge.source]) + Units.nodeHeight / 2
            let endY = layout.y(ofRow: layout.rows[edge.target]) + Units.nodeHeight / 2
            let middle = (start + end) / 2
            currentPage.drawCurve(
                from: .init(x: px(start), y: py(startY)), control1: .init(x: px(middle), y: py(startY)),
                control2: .init(x: px(middle), y: py(endY)), to: .init(x: px(end), y: py(endY)),
                width: max(0.6, 1.4 * scale), color: edgeColor,
            )
            let head = [
                PDFPageCanvas.Point(x: px(end - 8), y: py(endY - 4)),
                PDFPageCanvas.Point(x: px(end), y: py(endY)),
                PDFPageCanvas.Point(x: px(end - 8), y: py(endY + 4)),
            ]
            currentPage.drawPolygon(points: head, stroke: nil, fill: edgeColor)
        }
        for (index, node) in flow.nodes.enumerated() {
            let boxLeft = layout.x(ofLayer: layout.layers[index])
            let boxTop = layout.y(ofRow: layout.rows[index])
            let status = node.status
            let stroke = status.map { Self.tileInk($0) } ?? PDFColor(red: 0.62, green: 0.66, blue: 0.72)
            let fill = status.map { Self.tileFill($0) } ?? PDFColor(red: 0.98, green: 0.98, blue: 0.99)
            let boxHeight = Double(Units.nodeHeight) * scale
            currentPage.drawRoundedRectangle(
                x: px(boxLeft), y: py(boxTop) - boxHeight, width: Double(Units.nodeWidth) * scale, height: boxHeight,
                radius: Double(Units.radius) * scale, stroke: stroke, fill: fill, lineWidth: max(0.6, 1.2 * scale),
            )
            // the text is centred, as large as fits the box up to a limit
            let available = Double(Units.nodeWidth - 12) * scale
            let probe = tileRun(node.shown, bold: true, size: 10, color: .black)
            let natural = try inkWidth(ofLine: [probe])
            let textSize = max(5, min(10 * max(scale, 0.8), 10 * available / max(natural, 1)))
            let run = tileRun(node.shown, bold: true, size: textSize, color: status.map { Self.tileInk($0) } ?? .black)
            let textWidth = try inkWidth(ofLine: [run])
            let centerX = px(boxLeft) + Double(Units.nodeWidth) * scale / 2
            let centerY = py(boxTop) - boxHeight / 2
            try drawRuns([run], x: centerX - textWidth / 2, y: centerY - textSize * 0.3)
        }
        endMarkedContentIfNeeded(marked)
        endStructureElement(figure)
        y -= height + figureTrailingSpacing
    }

    // MARK: kpi

    private mutating func drawKPI(_ cards: [TileBlock.KPICard]) throws {
        let size = fontSize(for: .paragraph)
        let gap = 8.0
        let padding = 8.0
        let minimumWidth = 120.0
        let perRow = max(1, min(cards.count, Int((contentWidth + gap) / (minimumWidth + gap))))
        let cardWidth = (contentWidth - gap * Double(perRow - 1)) / Double(perRow)
        let cardHeight = padding * 2 + size * 0.9 + size * 2.0 + size * 1.2 + size * 1.0
        let rows = stride(from: 0, to: cards.count, by: perRow).map {
            Array(cards[$0 ..< min($0 + perRow, cards.count)])
        }
        for row in rows {
            ensureSpace(cardHeight)
            let figure = beginStructureElement(
                .figure, attributes: PDFTaggedContent.Attributes(alternateDescription: "Figures"),
            )
            let marked = beginMarkedContentForCurrentElement()
            markBlockQuoteContentDrawn()
            for (index, card) in row.enumerated() {
                try drawCard(
                    card, x: options.margins.left + Double(index) * (cardWidth + gap),
                    width: cardWidth, height: cardHeight, size: size, padding: padding,
                )
            }
            endMarkedContentIfNeeded(marked)
            endStructureElement(figure)
            y -= cardHeight + gap
        }
        // each row was followed by a gap; the last one is followed by the spacing of a figure instead
        y += gap - figureTrailingSpacing - 4
    }

    private mutating func drawCard(
        _ card: TileBlock.KPICard,
        x: Double,
        width: Double,
        height: Double,
        size: Double,
        padding: Double,
    ) throws {
        currentPage.drawRectangle(
            x: x, y: y - height, width: width, height: height,
            stroke: Self.tileRule, fill: PDFColor(red: 0.97, green: 0.98, blue: 0.99),
        )
        let inner = width - 2 * padding
        var baseline = y - padding - size * 0.75
        try drawRuns(
            [tileRun(card.label, size: size * 0.8, color: Self.tileMuted)], x: x + padding, y: baseline, maxWidth: inner,
        )
        baseline -= size * 1.8
        try drawRuns(
            [tileRun(card.value, bold: true, size: size * 1.6, color: .black)], x: x + padding, y: baseline, maxWidth: inner,
        )
        baseline -= size * 1.2
        if let change = card.change {
            let tone = Self.toneColor(change.tone)
            drawArrow(change.trend, x: x + padding, baseline: baseline, size: size * 0.8, color: tone)
            let text = "\(change.trend.rawValue) \(change.delta)"
            try drawRuns(
                [tileRun(text, size: size * 0.8, color: tone)],
                x: x + padding + size * 1.1, y: baseline, maxWidth: inner - size * 1.1,
            )
        }
        if let note = card.note {
            baseline -= size * 1.0
            try drawRuns(
                [tileRun(note, size: size * 0.7, color: Self.tileMuted)], x: x + padding, y: baseline, maxWidth: inner,
            )
        }
    }

    /// The arrow of a change, drawn as a small triangle (up, down) or a bar (flat), so it needs no glyph of any font.
    private func drawArrow(_ trend: TileBlock.Trend, x: Double, baseline: Double, size: Double, color: PDFColor) {
        let half = size * 0.45
        let midY = baseline + size * 0.3
        typealias Point = PDFPageCanvas.Point
        switch trend {
        case .up:
            let points = [
                Point(x: x, y: midY - half), Point(x: x + 2 * half, y: midY - half), Point(x: x + half, y: midY + half),
            ]
            currentPage.drawPolygon(points: points, stroke: nil, fill: color)
        case .down:
            let points = [
                Point(x: x, y: midY + half), Point(x: x + 2 * half, y: midY + half), Point(x: x + half, y: midY - half),
            ]
            currentPage.drawPolygon(points: points, stroke: nil, fill: color)
        case .flat:
            currentPage.drawRectangle(
                x: x, y: midY - half * 0.4, width: 2 * half, height: half * 0.8, stroke: nil, fill: color,
            )
        }
    }
}
