import Foundation

/// Reads a PDF back: its pages and their sizes, the text on each page, the document
/// title and author, the outline, and the links.
///
/// The reader exists so that what ``MarkdownPDFRenderer`` wrote can be checked from
/// Swift, on every platform the engine builds on, without another program. It reads
/// the files this engine writes: a classic cross-reference table, streams stored
/// plainly or with `FlateDecode`, text shown with `Tj` in the base fonts
/// (`WinAnsiEncoding`) or in embedded fonts with a `/ToUnicode` map, and
/// `/ActualText` spans. It is not a general PDF reader. A file that uses a feature
/// outside that set (a cross-reference stream, an encrypted file, another stream
/// filter) throws ``ReadError/unsupported(_:)`` and is never read wrongly.
///
/// ```swift
/// let pdf = try MarkdownPDFRenderer().render(markdown: "# Title\n\nBody text.")
/// let document = try PDFDocumentReader(data: pdf)
/// document.pageCount          // 1
/// document.pages[0].lines     // ["Title", "Body text."]
/// document.outline.map(\.title) // ["Title"]
/// ```
public struct PDFDocumentReader: Sendable {
    /// Why a file could not be read.
    public enum ReadError: Error, Equatable, CustomStringConvertible {
        /// The bytes are not the PDF syntax the reader expects at that place.
        case malformed(String)
        /// The file is a PDF, and uses something this reader does not read.
        case unsupported(String)

        public var description: String {
            switch self {
            case let .malformed(what): "the PDF is malformed: \(what)"
            case let .unsupported(what): "the PDF uses a feature this reader does not read: \(what)"
            }
        }
    }

    /// A piece of text shown by one operator, where it was drawn.
    public struct TextRun: Equatable, Sendable {
        /// The left end of the baseline, in points from the left edge of the page.
        public var x: Double
        /// The baseline, in points from the bottom edge of the page.
        public var y: Double
        /// The advance of the text, from the widths the font declares, in points. The
        /// spaces that end the text are part of it.
        public var width: Double
        public var fontSize: Double
        /// The base font name of the font, such as `Helvetica` or `ABCDEF+DejaVuSans`.
        public var fontName: String
        public var text: String
    }

    /// Where a link leads.
    public enum LinkTarget: Hashable, Sendable {
        /// A web address or another URI.
        case uri(String)
        /// A named destination inside the document.
        case destination(String)
    }

    /// A link annotation: the rectangle that responds, and where it leads.
    public struct Link: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public var target: LinkTarget
    }

    /// One page, in reading order of the content stream.
    public struct Page: Equatable, Sendable {
        /// The media box size, in points.
        public var size: PDFOptions.PageSize
        /// Every piece of text, in the order it was drawn.
        public var runs: [TextRun]
        public var links: [Link]
        /// The text as words, each with its box, in the order they were drawn.
        public var words: [Word]

        /// The text as lines: runs drawn one after another on one baseline are joined,
        /// with a space where a run starts clear of the end of the one before it (a
        /// list marker and its item, two cells of a table row), and each line is
        /// trimmed of the spaces at its ends.
        public var lines: [String] {
            var lines: [String] = []
            var current = ""
            var baseline: Double?
            var size = 0.0
            var end = 0.0
            for run in runs {
                defer { end = run.x + run.width }
                if let line = baseline, abs(run.y - line) <= max(size, run.fontSize) * 0.5 {
                    let apart = run.x - end > run.fontSize * 0.2 || run.x < end - run.fontSize * 0.2
                    if apart, current.last != " ", run.text.first != " " {
                        current += " "
                    }
                    current += run.text
                } else {
                    if baseline != nil {
                        lines.append(current)
                    }
                    current = run.text
                    baseline = run.y
                }
                size = run.fontSize
            }
            if baseline != nil {
                lines.append(current)
            }
            return lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        /// The lines joined by line feeds.
        public var text: String {
            lines.joined(separator: "\n")
        }
    }

    /// An entry of the outline (the bookmarks), in the order a reader lists them.
    public struct OutlineItem: Equatable, Sendable {
        public var title: String
        /// 1 for a top entry, 2 for an entry under it, and so on.
        public var level: Int
        /// The named destination the entry leads to, when it names one.
        public var destination: String?
        /// The page the entry leads to, counted from 0, when it gives a page directly.
        public var pageIndex: Int?
    }

    /// A word: text with no space in it, and the box its characters advance through.
    ///
    /// The widths are the ones the fonts declare in the file, which is what a viewer
    /// advances by, so a word box that leaves the page or runs into its neighbor
    /// shows a layout or a width table that is wrong. The text of an `/ActualText`
    /// span is one word, spaces included, over the box of what the span draws.
    public struct Word: Equatable, Sendable {
        /// The left end of the baseline, in points from the left edge of the page.
        public var x: Double
        /// The baseline, in points from the bottom edge of the page.
        public var y: Double
        /// The advance of the word, in points.
        public var width: Double
        /// The largest font size in the word.
        public var fontSize: Double
        public var text: String
    }

    /// An output intent of the catalog: the color space the document is meant for.
    public struct OutputIntent: Equatable, Sendable {
        /// The `/S` subtype, such as `GTS_PDFA1`.
        public var subtype: String
        /// The `/OutputConditionIdentifier`, such as `sRGB IEC61966-2.1`.
        public var outputConditionIdentifier: String?
        /// The number of color components of the embedded ICC profile (`/N`), or nil
        /// when the intent holds no profile stream.
        public var profileComponents: Int?
    }

    /// An element of the structure tree of a tagged document.
    public struct StructureElement: Equatable, Sendable {
        /// The structure type (`/S`), such as `Document`, `H1`, `P` or `Figure`.
        public var type: String
        /// The alternate description (`/Alt`), when the element has one.
        public var alternateText: String?
        /// How many pieces of marked page content the element holds directly.
        public var markedContentCount: Int
        public var children: [StructureElement]

        /// The element and everything under it, parents before children.
        public var flattened: [StructureElement] {
            [self] + children.flatMap(\.flattened)
        }
    }

    /// Something wrong with the structure of a file, found by ``structureIssues(in:)``.
    public struct StructureIssue: Equatable, Sendable, CustomStringConvertible {
        /// The number of the object the issue is in, or nil when it is about the file as a whole.
        public var object: Int?
        public var message: String

        public var description: String {
            object.map { "object \($0): \(message)" } ?? message
        }
    }

    /// A font the pages use.
    public struct Font: Hashable, Sendable {
        /// The base font name, such as `Helvetica` or `ABCDEF+DejaVuSans`.
        public var name: String
        /// Whether the font program is in the file. A standard font is not embedded.
        public var isEmbedded: Bool
    }

    public let pages: [Page]
    /// The fonts the pages use, each once, sorted by name.
    public let fonts: [Font]
    /// Whether the catalog marks the document as tagged and holds a structure tree.
    public let isTagged: Bool
    /// The Info dictionary `/Title`, or nil when there is none.
    public let title: String?
    /// The Info dictionary `/Author`, or nil when there is none.
    public let author: String?
    public let outline: [OutlineItem]
    /// The version the header names, such as `1.4` for `%PDF-1.4`.
    public let version: String
    /// The Info dictionary `/Producer`, or nil when there is none.
    public let producer: String?
    /// The natural language of the document (the catalog `/Lang`), such as `en-US`.
    public let language: String?
    /// Whether the catalog asks a viewer to show the document title in its window
    /// (`/ViewerPreferences /DisplayDocTitle true`), as PDF/UA requires.
    public let displaysDocumentTitle: Bool
    /// The XMP packet of the catalog `/Metadata` stream as text, or nil when there is none.
    public let xmpMetadata: String?
    /// The output intents of the catalog, in order.
    public let outputIntents: [OutputIntent]
    /// The elements directly under the root of the structure tree, each with its
    /// own children. Empty when the document has no structure tree.
    public let structure: [StructureElement]

    public var pageCount: Int {
        pages.count
    }

    /// The PDF/A part and level the XMP metadata declares, such as `2A`, or nil
    /// when it declares none. A declaration is a claim, not a proof of conformance.
    public var pdfAConformance: String? {
        guard let part = xmpProperty("pdfaid:part") else {
            return nil
        }
        return part + (xmpProperty("pdfaid:conformance") ?? "")
    }

    /// The PDF/UA part the XMP metadata declares, such as 1, or nil when it
    /// declares none. A declaration is a claim, not a proof of conformance.
    public var pdfUAPart: Int? {
        xmpProperty("pdfuaid:part").flatMap { Int($0) }
    }

    /// The value of a simple XMP property, written as an element or as an attribute.
    func xmpProperty(_ name: String) -> String? {
        guard let xmp = xmpMetadata else {
            return nil
        }
        if let open = xmp.range(of: "<\(name)>"), let close = xmp.range(of: "</\(name)>", range: open.upperBound ..< xmp.endIndex) {
            return xmp[open.upperBound ..< close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let open = xmp.range(of: "\(name)=\""), let close = xmp.range(of: "\"", range: open.upperBound ..< xmp.endIndex) {
            return String(xmp[open.upperBound ..< close.lowerBound])
        }
        return nil
    }

    /// Checks the structure of a file this engine wrote and returns what is wrong
    /// with it, or nothing when it is sound.
    ///
    /// Every object the cross-reference table lists is read where the table says it
    /// is: it carries its own number, it parses, it ends with `endobj`, and a stream
    /// ends exactly where its `/Length` says. Every reference names an object the
    /// file holds. Every stream the reader can decode decodes. The page tree is
    /// walked: each node counts the pages under it and each child names its parent.
    /// The trailer `/Size` covers every object, the file ends with `%%EOF`, and the
    /// whole document reads with ``init(data:)``.
    public static func structureIssues(in data: Data) -> [StructureIssue] {
        PDFReadStructure.issues(in: Array(data))
    }

    /// The text of every page, pages separated by a form feed.
    public var text: String {
        pages.map(\.text).joined(separator: "\u{0C}")
    }

    /// Every link of the document, page after page.
    public var links: [Link] {
        pages.flatMap(\.links)
    }

    /// Reads `data`. Throws a ``ReadError`` when the file is not a PDF this reader reads.
    public init(data: Data) throws {
        let store = try PDFReadObjects(bytes: Array(data))
        let catalog = try store.dictionary(store.trailer["Root"], what: "the catalog")
        var pages: [Page] = []
        var visited = Set<Int>()
        var pageObjects: [Int] = []
        var fonts = Set<Font>()
        try Self.collectPages(catalog["Pages"], inherited: [:], store: store, visited: &visited, objects: &pageObjects, fonts: &fonts, into: &pages)
        self.pages = pages
        self.fonts = fonts.sorted { ($0.name, $0.isEmbedded ? 1 : 0) < ($1.name, $1.isEmbedded ? 1 : 0) }
        let marked = try store.resolve(store.resolve(catalog["MarkInfo"]).dictionary?["Marked"]) == .boolean(true)
        isTagged = try marked && store.resolve(catalog["StructTreeRoot"]).dictionary != nil

        let info = try store.resolve(store.trailer["Info"]).dictionary ?? [:]
        title = try store.resolve(info["Title"]).bytes.map(Self.textString)
        author = try store.resolve(info["Author"]).bytes.map(Self.textString)

        var outline: [OutlineItem] = []
        if let root = try store.resolve(catalog["Outlines"]).dictionary {
            var seen = Set<Int>()
            try Self.collectOutline(first: root["First"], level: 1, store: store, pageObjects: pageObjects, visited: &seen, into: &outline)
        }
        self.outline = outline

        version = PDFReadStructure.version(of: store.bytes)
        producer = try store.resolve(info["Producer"]).bytes.map(Self.textString)
        language = try store.resolve(catalog["Lang"]).bytes.map(Self.textString)
        let preferences = try store.resolve(catalog["ViewerPreferences"]).dictionary ?? [:]
        displaysDocumentTitle = try store.resolve(preferences["DisplayDocTitle"]) == .boolean(true)
        if case .stream = try store.resolve(catalog["Metadata"]) {
            xmpMetadata = try String(decoding: store.streamData(catalog["Metadata"]), as: UTF8.self)
        } else {
            xmpMetadata = nil
        }
        outputIntents = try PDFReadStructure.outputIntents(of: catalog, store: store)
        structure = try PDFReadStructure.elements(of: catalog, store: store)
    }

    // MARK: Strings

    /// A text string (ISO 32000-1, 7.9.2.2): UTF-16BE after a byte order mark, else
    /// one byte for each character, read as WinAnsi, which is how this engine writes it.
    static func textString(_ bytes: [UInt8]) -> String {
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
            return utf16BigEndian(Array(bytes.dropFirst(2)))
        }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: bytes.map(PDFTextEncoding.winAnsiScalar))
        return String(scalars)
    }

    static func utf16BigEndian(_ bytes: [UInt8]) -> String {
        let units = stride(from: 0, to: bytes.count - 1, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
        return String(decoding: units, as: UTF16.self)
    }

    // MARK: Pages

    private static func collectPages(
        _ node: PDFReadValue?,
        inherited: [String: PDFReadValue],
        store: PDFReadObjects,
        visited: inout Set<Int>,
        objects: inout [Int],
        fonts used: inout Set<Font>,
        into pages: inout [Page],
    ) throws {
        var objectNumber = 0
        if case let .reference(number)? = node {
            guard visited.insert(number).inserted else {
                throw ReadError.malformed("the page tree loops")
            }
            objectNumber = number
        }
        let dictionary = try store.dictionary(node, what: "a page tree node")
        var inherited = inherited
        for key in ["MediaBox", "Resources"] {
            if let value = dictionary[key] {
                inherited[key] = value
            }
        }
        if dictionary["Type"]?.name == "Pages" {
            for kid in try store.resolve(dictionary["Kids"]).array ?? [] {
                try collectPages(kid, inherited: inherited, store: store, visited: &visited, objects: &objects, fonts: &used, into: &pages)
            }
            return
        }
        objects.append(objectNumber)

        let box = try (store.resolve(inherited["MediaBox"]).array ?? []).map { try store.resolve($0).number ?? 0 }
        guard box.count == 4 else {
            throw ReadError.malformed("a page has no media box")
        }
        let resources = try store.resolve(inherited["Resources"]).dictionary ?? [:]
        let fonts = try PDFReadContent.fonts(in: store.resolve(resources["Font"]).dictionary ?? [:], store: store)
        for font in fonts.values {
            used.insert(Font(name: font.name, isEmbedded: font.isEmbedded))
        }
        var content: [UInt8] = []
        let contents = try store.resolve(dictionary["Contents"])
        for part in contents.array ?? [contents] {
            guard case .stream = try store.resolve(part) else {
                continue
            }
            content += try store.streamData(part)
            content.append(0x0A)
        }
        let text = try PDFReadContent.text(in: content, fonts: fonts)
        try pages.append(Page(
            size: PDFOptions.PageSize(width: box[2] - box[0], height: box[3] - box[1]),
            runs: text.runs,
            links: links(of: dictionary, store: store),
            words: text.words,
        ))
    }

    private static func links(of page: [String: PDFReadValue], store: PDFReadObjects) throws -> [Link] {
        var links: [Link] = []
        for annotation in try store.resolve(page["Annots"]).array ?? [] {
            guard let dictionary = try store.resolve(annotation).dictionary, dictionary["Subtype"]?.name == "Link" else {
                continue
            }
            let rect = try (store.resolve(dictionary["Rect"]).array ?? []).map { try store.resolve($0).number ?? 0 }
            guard rect.count == 4 else {
                continue
            }
            let action = try store.resolve(dictionary["A"]).dictionary ?? [:]
            let target: LinkTarget
            if let uri = try store.resolve(action["URI"]).bytes {
                target = .uri(textString(uri))
            } else if let name = try destinationName(dictionary["Dest"] ?? action["D"], store: store) {
                target = .destination(name)
            } else {
                continue
            }
            links.append(Link(
                x: min(rect[0], rect[2]),
                y: min(rect[1], rect[3]),
                width: abs(rect[2] - rect[0]),
                height: abs(rect[3] - rect[1]),
                target: target,
            ))
        }
        return links
    }

    private static func destinationName(_ value: PDFReadValue?, store: PDFReadObjects) throws -> String? {
        switch try store.resolve(value) {
        case let .string(bytes): textString(bytes)
        case let .name(name): name
        default: nil
        }
    }

    // MARK: Outline

    private static func collectOutline(
        first: PDFReadValue?,
        level: Int,
        store: PDFReadObjects,
        pageObjects: [Int],
        visited: inout Set<Int>,
        into outline: inout [OutlineItem],
    ) throws {
        var next = first
        while case let .reference(number)? = next {
            guard visited.insert(number).inserted else {
                throw ReadError.malformed("the outline loops")
            }
            let item = try store.dictionary(next, what: "an outline entry")
            let action = try store.resolve(item["A"]).dictionary ?? [:]
            let destination = item["Dest"] ?? action["D"]
            // An explicit destination is an array that starts with its page.
            var pageIndex: Int?
            if case let .reference(page)? = try store.resolve(destination).array?.first {
                pageIndex = pageObjects.firstIndex(of: page)
            }
            try outline.append(OutlineItem(
                title: store.resolve(item["Title"]).bytes.map(textString) ?? "",
                level: level,
                destination: destinationName(destination, store: store),
                pageIndex: pageIndex,
            ))
            try collectOutline(first: item["First"], level: level + 1, store: store, pageObjects: pageObjects, visited: &visited, into: &outline)
            next = item["Next"]
        }
    }
}
