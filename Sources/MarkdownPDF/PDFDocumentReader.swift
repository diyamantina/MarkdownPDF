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

    public let pages: [Page]
    /// The Info dictionary `/Title`, or nil when there is none.
    public let title: String?
    /// The Info dictionary `/Author`, or nil when there is none.
    public let author: String?
    public let outline: [OutlineItem]

    public var pageCount: Int {
        pages.count
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
        try Self.collectPages(catalog["Pages"], inherited: [:], store: store, visited: &visited, objects: &pageObjects, into: &pages)
        self.pages = pages

        let info = try store.resolve(store.trailer["Info"]).dictionary ?? [:]
        title = try store.resolve(info["Title"]).bytes.map(Self.textString)
        author = try store.resolve(info["Author"]).bytes.map(Self.textString)

        var outline: [OutlineItem] = []
        if let root = try store.resolve(catalog["Outlines"]).dictionary {
            var seen = Set<Int>()
            try Self.collectOutline(first: root["First"], level: 1, store: store, pageObjects: pageObjects, visited: &seen, into: &outline)
        }
        self.outline = outline
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
                try collectPages(kid, inherited: inherited, store: store, visited: &visited, objects: &objects, into: &pages)
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
        var content: [UInt8] = []
        let contents = try store.resolve(dictionary["Contents"])
        for part in contents.array ?? [contents] {
            guard case .stream = try store.resolve(part) else {
                continue
            }
            content += try store.streamData(part)
            content.append(0x0A)
        }
        try pages.append(Page(
            size: PDFOptions.PageSize(width: box[2] - box[0], height: box[3] - box[1]),
            runs: PDFReadContent.runs(in: content, fonts: fonts),
            links: links(of: dictionary, store: store),
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
