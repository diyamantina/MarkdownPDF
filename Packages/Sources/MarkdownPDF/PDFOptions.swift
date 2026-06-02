import Foundation

public struct PDFOptions: Equatable, Sendable {
    public var pageSize: PageSize
    public var margins: Margins
    public var baseFontSize: Double
    public var fontSet: FontSet
    public var embeddedFonts: EmbeddedFonts
    public var title: String?
    public var tableOfContents: TableOfContents
    public var codeSyntaxHighlighting: CodeSyntaxHighlighting
    public var streamCompression: StreamCompression
    public var taggedPDF: TaggedPDF

    public init(
        pageSize: PageSize = .a4,
        margins: Margins = .standard,
        baseFontSize: Double = 11,
        fontSet: FontSet = .pdfBase,
        embeddedFonts: EmbeddedFonts = .disabled,
        title: String? = nil,
        tableOfContents: TableOfContents = .disabled,
        codeSyntaxHighlighting: CodeSyntaxHighlighting = .disabled,
        streamCompression: StreamCompression = .disabled,
        taggedPDF: TaggedPDF = .disabled,
    ) {
        self.pageSize = pageSize
        self.margins = margins
        self.baseFontSize = baseFontSize
        self.fontSet = fontSet
        self.embeddedFonts = embeddedFonts
        self.title = title
        self.tableOfContents = tableOfContents
        self.codeSyntaxHighlighting = codeSyntaxHighlighting
        self.streamCompression = streamCompression
        self.taggedPDF = taggedPDF
    }

    public struct PageSize: Equatable, Sendable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }

        public static let a4 = PageSize(width: 595.28, height: 841.89)
        public static let letter = PageSize(width: 612, height: 792)
    }

    public struct Margins: Equatable, Sendable {
        public var top: Double
        public var right: Double
        public var bottom: Double
        public var left: Double

        public init(
            top: Double,
            right: Double,
            bottom: Double,
            left: Double,
        ) {
            self.top = top
            self.right = right
            self.bottom = bottom
            self.left = left
        }

        public static let standard = Margins(top: 54, right: 54, bottom: 54, left: 54)
    }

    public struct FontSet: Equatable, Sendable {
        public var regular: String
        public var bold: String
        public var italic: String
        public var monospaced: String
        public var subtype: String

        public init(
            regular: String,
            bold: String,
            italic: String,
            monospaced: String,
            subtype: String,
        ) {
            self.regular = regular
            self.bold = bold
            self.italic = italic
            self.monospaced = monospaced
            self.subtype = subtype
        }

        public static let appleSystem = FontSet(
            regular: "SFProText-Regular",
            bold: "SFProText-Bold",
            italic: "SFProText-RegularItalic",
            monospaced: "SFMono-Regular",
            subtype: "TrueType",
        )

        public static let pdfBase = FontSet(
            regular: "Helvetica",
            bold: "Helvetica-Bold",
            italic: "Helvetica-Oblique",
            monospaced: "Courier",
            subtype: "Type1",
        )

        public static let pdfBaseMonospaced = FontSet(
            regular: "Courier",
            bold: "Courier-Bold",
            italic: "Courier-Oblique",
            monospaced: "Courier",
            subtype: "Type1",
        )
    }

    /// Caller-provided TrueType font data for one Markdown text role.
    ///
    /// MarkdownPDF never discovers system fonts in the portable renderer and
    /// never bundles font binaries in the public repository. Pass complete
    /// TrueType font data here when the document should embed that role as a
    /// subsetted Type 0 / CIDFontType2 font. The caller remains responsible for
    /// the font license, and rendering rejects fonts whose OS/2 embedding bits
    /// forbid the subset profile.
    public struct EmbeddedFontSource: Equatable, Sendable {
        public var data: Data
        public var baseName: String?

        public init(data: Data, baseName: String? = nil) {
            self.data = data
            self.baseName = baseName
        }
    }

    /// Opt-in embedded-font role mapping for the portable renderer.
    ///
    /// The default value is ``disabled``, so MarkdownPDF continues to use PDF
    /// base fonts and emits no font files unless the caller supplies font data.
    /// Each non-nil role is parsed, validated, subsetted, and written directly
    /// in Swift on macOS and Linux. Roles left nil fall back to the matching
    /// standard PDF base-font role. This API does not perform macOS font
    /// discovery and does not imply iOS support.
    public struct EmbeddedFonts: Equatable, Sendable {
        public var regular: EmbeddedFontSource?
        public var bold: EmbeddedFontSource?
        public var italic: EmbeddedFontSource?
        public var monospaced: EmbeddedFontSource?

        public init(
            regular: EmbeddedFontSource? = nil,
            bold: EmbeddedFontSource? = nil,
            italic: EmbeddedFontSource? = nil,
            monospaced: EmbeddedFontSource? = nil,
        ) {
            self.regular = regular
            self.bold = bold
            self.italic = italic
            self.monospaced = monospaced
        }

        public static let disabled = EmbeddedFonts()

        public static func allRoles(_ source: EmbeddedFontSource) -> EmbeddedFonts {
            EmbeddedFonts(
                regular: source,
                bold: source,
                italic: source,
                monospaced: source,
            )
        }
    }

    /// Controls whether the portable renderer inserts a generated table of contents.
    public struct TableOfContents: Equatable, Sendable {
        public var isEnabled: Bool
        public var title: String
        public var maximumDepth: Int

        public init(
            isEnabled: Bool,
            title: String = "Table of Contents",
            maximumDepth: Int = 6,
        ) {
            self.isEnabled = isEnabled
            self.title = title
            self.maximumDepth = max(1, min(6, maximumDepth))
        }

        public static let disabled = TableOfContents(isEnabled: false)
        public static let enabled = TableOfContents(isEnabled: true)
    }

    /// Controls portable syntax coloring for fenced code blocks.
    ///
    /// The default value is ``disabled``. When enabled, the renderer applies a
    /// narrow Pure Swift tokenizer to supported language hints and emits
    /// DeviceRGB text colors directly in the PDF content stream. Unsupported or
    /// missing language hints keep the existing plain monospaced rendering.
    /// Mermaid fences keep their separate diagram-rendering path.
    public struct CodeSyntaxHighlighting: Equatable, Sendable {
        public var isEnabled: Bool

        public init(isEnabled: Bool) {
            self.isEnabled = isEnabled
        }

        public static let disabled = CodeSyntaxHighlighting(isEnabled: false)
        public static let enabled = CodeSyntaxHighlighting(isEnabled: true)
    }

    /// Controls opt-in FlateDecode compression for PDF streams written by the
    /// portable renderer.
    ///
    /// The default value is ``disabled``. When enabled, page content streams and
    /// embedded FontFile2 streams are encoded with a Pure Swift zlib-wrapped
    /// DEFLATE profile only when the encoded bytes are smaller than the raw
    /// stream. Image streams keep their source filter and are not recompressed.
    public struct StreamCompression: Equatable, Sendable {
        public var isEnabled: Bool

        public init(isEnabled: Bool) {
            self.isEnabled = isEnabled
        }

        public static let disabled = StreamCompression(isEnabled: false)
        public static let enabled = StreamCompression(isEnabled: true)
    }

    /// Controls opt-in tagged PDF structure output.
    ///
    /// The default value is ``disabled``. When enabled, MarkdownPDF writes the
    /// PDF logical structure spine directly in Swift: `/MarkInfo`, `/Lang`,
    /// `/StructTreeRoot`, page `/StructParents`, marked-content IDs, and a
    /// `/ParentTree`. This first portable profile does not claim PDF/UA or
    /// PDF/A conformance.
    public struct TaggedPDF: Equatable, Sendable {
        public var isEnabled: Bool
        public var language: String

        public init(isEnabled: Bool, language: String = "en-US") {
            self.isEnabled = isEnabled
            self.language = language.isEmpty ? "en-US" : language
        }

        public static let disabled = TaggedPDF(isEnabled: false)
        public static let enabled = TaggedPDF(isEnabled: true)
    }
}
