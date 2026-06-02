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
    public var mathTypesetting: MathTypesetting
    public var theme: Theme
    public var streamCompression: StreamCompression
    public var taggedPDF: TaggedPDF
    public var conformance: Conformance

    public init(
        pageSize: PageSize = .a4,
        margins: Margins = .standard,
        baseFontSize: Double = 11,
        fontSet: FontSet = .pdfBase,
        embeddedFonts: EmbeddedFonts = .disabled,
        title: String? = nil,
        tableOfContents: TableOfContents = .disabled,
        codeSyntaxHighlighting: CodeSyntaxHighlighting = .disabled,
        mathTypesetting: MathTypesetting = .disabled,
        theme: Theme = .default,
        streamCompression: StreamCompression = .disabled,
        taggedPDF: TaggedPDF = .disabled,
        conformance: Conformance = .none,
    ) {
        self.pageSize = pageSize
        self.margins = margins
        self.baseFontSize = baseFontSize
        self.fontSet = fontSet
        self.embeddedFonts = embeddedFonts
        self.title = title
        self.tableOfContents = tableOfContents
        self.codeSyntaxHighlighting = codeSyntaxHighlighting
        self.mathTypesetting = mathTypesetting
        self.theme = theme
        self.streamCompression = streamCompression
        self.taggedPDF = taggedPDF
        self.conformance = conformance
    }

    public struct PageSize: Equatable, Sendable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }

        public static let a0 = PageSize(width: 2383.94, height: 3370.39)
        public static let a1 = PageSize(width: 1683.78, height: 2383.94)
        public static let a2 = PageSize(width: 1190.55, height: 1683.78)
        public static let a3 = PageSize(width: 841.89, height: 1190.55)
        public static let a4 = PageSize(width: 595.28, height: 841.89)
        public static let a5 = PageSize(width: 419.53, height: 595.28)
        public static let a6 = PageSize(width: 297.64, height: 419.53)
        public static let letter = PageSize(width: 612, height: 792)
        public static let legal = PageSize(width: 612, height: 1008)
        public static let tabloid = PageSize(width: 792, height: 1224)
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

        /// Apple system font *names* (SF Pro Text, SF Mono) written into the PDF
        /// font dictionaries.
        ///
        /// This is a names-only, best-effort, macOS-oriented convenience: it
        /// embeds no font data and commits no font binaries. The names resolve
        /// only where a reader can substitute the matching Apple fonts, so output
        /// is not portable to Linux readers and is not font embedding. Apple
        /// system fonts are license-restricted and intentionally never embedded.
        /// For portable, self-contained output use ``pdfBase`` or supply caller
        /// font data through ``PDFOptions/EmbeddedFonts``.
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

    /// Controls opt-in TeX-style math parsing and PDF drawing.
    ///
    /// The default value is ``disabled`` so CommonMark dollar-sign text remains
    /// literal. When enabled, `$...$` and `$$...$$` are parsed by a Pure Swift
    /// TeX-subset parser. Supported inline formulas render as positioned PDF
    /// text, supported display formulas add rule rectangles for fractions and
    /// radicals, and unsupported input renders its original source visibly.
    /// Use ``fontBacked`` to require the styled math role to use an embedded
    /// OpenType font with a `MATH` table instead of the base-font fallback.
    public struct MathTypesetting: Equatable, Sendable {
        public enum FontRequirement: Equatable, Sendable {
            case fallbackAllowed
            case embeddedMathFont
        }

        public var isEnabled: Bool
        public var fontRequirement: FontRequirement

        public init(isEnabled: Bool, fontRequirement: FontRequirement = .fallbackAllowed) {
            self.isEnabled = isEnabled
            self.fontRequirement = fontRequirement
        }

        public var requiresEmbeddedMathFont: Bool {
            isEnabled && fontRequirement == .embeddedMathFont
        }

        public static let disabled = MathTypesetting(isEnabled: false)
        public static let enabled = MathTypesetting(isEnabled: true)
        public static let fontBacked = MathTypesetting(isEnabled: true, fontRequirement: .embeddedMathFont)
    }

    /// A complete document theme resolved by the portable renderer.
    ///
    /// Sizes, line heights, and spacing are multipliers of ``baseFontSize``.
    /// Colors are emitted as PDF DeviceRGB values. The default theme preserves
    /// the renderer's historical output and does not draw an explicit page
    /// background, so default PDFs remain byte-stable.
    public struct Theme: Equatable, Sendable {
        public var palette: Palette
        public var pageBackground: PDFColor?
        public var elements: [ElementRole: ElementStyle]
        public var codeSyntax: CodeSyntaxTheme

        public init(
            palette: Palette,
            pageBackground: PDFColor? = nil,
            elements: [ElementRole: ElementStyle],
            codeSyntax: CodeSyntaxTheme,
        ) {
            self.palette = palette
            self.pageBackground = pageBackground
            self.elements = elements
            self.codeSyntax = codeSyntax
        }

        public func style(for role: ElementRole) -> ElementStyle {
            elements[role] ?? elements[.body] ?? ElementStyle(fontRole: .regular, color: palette.foreground)
        }

        public static let `default` = Theme(
            palette: .default,
            elements: Self.defaultElements(palette: .default),
            codeSyntax: .default,
        )

        public static let dark = Theme(
            palette: .dark,
            pageBackground: Palette.dark.background,
            elements: Self.darkElements(palette: .dark),
            codeSyntax: .dark,
        )

        public static let print = Theme(
            palette: .print,
            elements: Self.printElements(palette: .print),
            codeSyntax: .print,
        )

        public static var builtInThemes: [Theme] {
            [.default, .dark, .print]
        }
    }

    public struct Palette: Equatable, Sendable {
        public var base00: PDFColor
        public var base01: PDFColor
        public var base02: PDFColor
        public var base03: PDFColor
        public var base04: PDFColor
        public var base05: PDFColor
        public var base06: PDFColor
        public var base07: PDFColor
        public var base08: PDFColor
        public var base09: PDFColor
        public var base0A: PDFColor
        public var base0B: PDFColor
        public var base0C: PDFColor
        public var base0D: PDFColor
        public var base0E: PDFColor
        public var base0F: PDFColor

        public init(
            base00: PDFColor,
            base01: PDFColor,
            base02: PDFColor,
            base03: PDFColor,
            base04: PDFColor,
            base05: PDFColor,
            base06: PDFColor,
            base07: PDFColor,
            base08: PDFColor,
            base09: PDFColor,
            base0A: PDFColor,
            base0B: PDFColor,
            base0C: PDFColor,
            base0D: PDFColor,
            base0E: PDFColor,
            base0F: PDFColor,
        ) {
            self.base00 = base00
            self.base01 = base01
            self.base02 = base02
            self.base03 = base03
            self.base04 = base04
            self.base05 = base05
            self.base06 = base06
            self.base07 = base07
            self.base08 = base08
            self.base09 = base09
            self.base0A = base0A
            self.base0B = base0B
            self.base0C = base0C
            self.base0D = base0D
            self.base0E = base0E
            self.base0F = base0F
        }

        public var background: PDFColor {
            base00
        }

        public var foreground: PDFColor {
            base07
        }

        public var mutedForeground: PDFColor {
            base04
        }

        public var border: PDFColor {
            base03
        }

        public var surface: PDFColor {
            base01
        }

        public var raisedSurface: PDFColor {
            base02
        }

        public var link: PDFColor {
            base0D
        }

        public var accents: [PDFColor] {
            [base08, base09, base0A, base0B, base0C, base0D, base0E, base0F]
        }

        public static let `default` = Palette(
            base00: .white,
            base01: PDFColor(red: 0.98, green: 0.985, blue: 0.99),
            base02: PDFColor(red: 0.95, green: 0.95, blue: 0.95),
            base03: .gray,
            base04: .gray,
            base05: PDFColor(red: 0.2, green: 0.2, blue: 0.2),
            base06: PDFColor(red: 0.1, green: 0.1, blue: 0.1),
            base07: .black,
            base08: PDFColor(red: 0.89, green: 0.10, blue: 0.11),
            base09: PDFColor(red: 0.89, green: 0.47, blue: 0.20),
            base0A: PDFColor(red: 0.74, green: 0.74, blue: 0.13),
            base0B: PDFColor(red: 0.20, green: 0.63, blue: 0.17),
            base0C: PDFColor(red: 0.11, green: 0.47, blue: 0.71),
            base0D: .link,
            base0E: PDFColor(red: 0.58, green: 0.40, blue: 0.74),
            base0F: PDFColor(red: 0.55, green: 0.34, blue: 0.29),
        )

        public static let dark = Palette(
            base00: PDFColor(red: 0.08, green: 0.08, blue: 0.09),
            base01: PDFColor(red: 0.13, green: 0.14, blue: 0.16),
            base02: PDFColor(red: 0.18, green: 0.20, blue: 0.23),
            base03: PDFColor(red: 0.35, green: 0.39, blue: 0.44),
            base04: PDFColor(red: 0.72, green: 0.76, blue: 0.80),
            base05: PDFColor(red: 0.84, green: 0.87, blue: 0.90),
            base06: PDFColor(red: 0.90, green: 0.92, blue: 0.94),
            base07: PDFColor(red: 0.96, green: 0.97, blue: 0.98),
            base08: PDFColor(red: 1.00, green: 0.55, blue: 0.58),
            base09: PDFColor(red: 1.00, green: 0.68, blue: 0.38),
            base0A: PDFColor(red: 0.94, green: 0.82, blue: 0.42),
            base0B: PDFColor(red: 0.53, green: 0.82, blue: 0.56),
            base0C: PDFColor(red: 0.46, green: 0.82, blue: 0.86),
            base0D: PDFColor(red: 0.54, green: 0.72, blue: 1.00),
            base0E: PDFColor(red: 0.78, green: 0.64, blue: 1.00),
            base0F: PDFColor(red: 0.82, green: 0.64, blue: 0.50),
        )

        public static let print = Palette(
            base00: .white,
            base01: PDFColor(red: 0.98, green: 0.98, blue: 0.98),
            base02: PDFColor(red: 0.94, green: 0.94, blue: 0.94),
            base03: PDFColor(red: 0.42, green: 0.42, blue: 0.42),
            base04: PDFColor(red: 0.30, green: 0.30, blue: 0.30),
            base05: PDFColor(red: 0.18, green: 0.18, blue: 0.18),
            base06: PDFColor(red: 0.08, green: 0.08, blue: 0.08),
            base07: .black,
            base08: PDFColor(red: 0.12, green: 0.12, blue: 0.12),
            base09: PDFColor(red: 0.18, green: 0.18, blue: 0.18),
            base0A: PDFColor(red: 0.24, green: 0.24, blue: 0.24),
            base0B: PDFColor(red: 0.30, green: 0.30, blue: 0.30),
            base0C: PDFColor(red: 0.36, green: 0.36, blue: 0.36),
            base0D: PDFColor(red: 0.12, green: 0.12, blue: 0.12),
            base0E: PDFColor(red: 0.24, green: 0.24, blue: 0.24),
            base0F: PDFColor(red: 0.18, green: 0.18, blue: 0.18),
        )
    }

    public enum ElementRole: CaseIterable, Hashable, Sendable {
        case body
        case paragraph
        case heading1
        case heading2
        case heading3
        case heading4
        case heading5
        case heading6
        case blockQuote
        case list
        case listMarker
        case link
        case inlineCode
        case inlineMath
        case displayMath
        case codeBlock
        case tableHeader
        case tableCell
        case thematicBreak
        case footnote
        case html
        case imagePlaceholder

        public static func heading(level: Int) -> ElementRole {
            switch level {
            case 1:
                .heading1
            case 2:
                .heading2
            case 3:
                .heading3
            case 4:
                .heading4
            case 5:
                .heading5
            default:
                .heading6
            }
        }
    }

    public enum FontRole: Equatable, Sendable {
        case regular
        case bold
        case italic
        case monospaced
    }

    public struct ElementStyle: Equatable, Sendable {
        public var fontRole: FontRole
        public var sizeMultiplier: Double
        public var lineHeightMultiplier: Double
        public var color: PDFColor
        public var backgroundColor: PDFColor?
        public var borderColor: PDFColor?
        public var underline: Bool
        public var spacingBeforeMultiplier: Double
        public var spacingAfterMultiplier: Double

        public init(
            fontRole: FontRole,
            sizeMultiplier: Double = 1,
            lineHeightMultiplier: Double = 1.24,
            color: PDFColor,
            backgroundColor: PDFColor? = nil,
            borderColor: PDFColor? = nil,
            underline: Bool = false,
            spacingBeforeMultiplier: Double = 0,
            spacingAfterMultiplier: Double = 0,
        ) {
            self.fontRole = fontRole
            self.sizeMultiplier = sizeMultiplier
            self.lineHeightMultiplier = lineHeightMultiplier
            self.color = color
            self.backgroundColor = backgroundColor
            self.borderColor = borderColor
            self.underline = underline
            self.spacingBeforeMultiplier = spacingBeforeMultiplier
            self.spacingAfterMultiplier = spacingAfterMultiplier
        }
    }

    public struct CodeSyntaxTheme: Equatable, Sendable {
        public var text: PDFColor
        public var keyword: PDFColor
        public var identifier: PDFColor
        public var string: PDFColor
        public var number: PDFColor
        public var comment: PDFColor
        public var operatorToken: PDFColor
        public var punctuation: PDFColor
        public var error: PDFColor

        public init(
            text: PDFColor,
            keyword: PDFColor,
            identifier: PDFColor,
            string: PDFColor,
            number: PDFColor,
            comment: PDFColor,
            operatorToken: PDFColor,
            punctuation: PDFColor,
            error: PDFColor,
        ) {
            self.text = text
            self.keyword = keyword
            self.identifier = identifier
            self.string = string
            self.number = number
            self.comment = comment
            self.operatorToken = operatorToken
            self.punctuation = punctuation
            self.error = error
        }

        public static let `default` = CodeSyntaxTheme(
            text: .black,
            keyword: .sourceCodeKeyword,
            identifier: .black,
            string: .sourceCodeString,
            number: .sourceCodeNumber,
            comment: .sourceCodeComment,
            operatorToken: .sourceCodeOperator,
            punctuation: .sourceCodePunctuation,
            error: .black,
        )

        public static let dark = CodeSyntaxTheme(
            text: Palette.dark.foreground,
            keyword: Palette.dark.base0D,
            identifier: Palette.dark.foreground,
            string: Palette.dark.base0B,
            number: Palette.dark.base0E,
            comment: Palette.dark.base04,
            operatorToken: Palette.dark.base05,
            punctuation: Palette.dark.base05,
            error: Palette.dark.base08,
        )

        public static let print = CodeSyntaxTheme(
            text: Palette.print.foreground,
            keyword: Palette.print.base0D,
            identifier: Palette.print.foreground,
            string: Palette.print.base04,
            number: Palette.print.base05,
            comment: Palette.print.base03,
            operatorToken: Palette.print.base05,
            punctuation: Palette.print.base05,
            error: Palette.print.foreground,
        )

        func color(for tokenKind: SourceCodeTokenKind) -> PDFColor {
            switch tokenKind {
            case .text:
                text
            case .keyword:
                keyword
            case .identifier:
                identifier
            case .string:
                string
            case .number:
                number
            case .comment:
                comment
            case .operatorToken:
                operatorToken
            case .punctuation:
                punctuation
            case .error:
                error
            }
        }
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

    /// Controls opt-in standards identification for generated PDFs.
    ///
    /// The default value is ``none`` and claims no conformance profile. PDF/UA-1
    /// and PDF/A-2a profiles automatically enable tagged PDF structure and
    /// require a non-empty document title before rendering. PDF/A-2a also emits
    /// an sRGB output intent, `pdfaid` XMP, and a deterministic trailer `/ID`.
    public struct Conformance: Equatable, Sendable {
        public var isPDFUA1Enabled: Bool
        public var isPDFA2AEnabled: Bool

        public init(pdfUA1: Bool, pdfA2A: Bool = false) {
            isPDFUA1Enabled = pdfUA1
            isPDFA2AEnabled = pdfA2A
        }

        public static let none = Conformance(pdfUA1: false, pdfA2A: false)
        public static let pdfUA1 = Conformance(pdfUA1: true, pdfA2A: false)
        public static let pdfA2A = Conformance(pdfUA1: false, pdfA2A: true)
        public static let pdfUA1AndPDFA2A = Conformance(pdfUA1: true, pdfA2A: true)

        var isEnabled: Bool {
            isPDFUA1Enabled || isPDFA2AEnabled
        }

        var requiresTaggedPDF: Bool {
            isPDFUA1Enabled || isPDFA2AEnabled
        }

        var requiresDocumentTitle: Bool {
            isPDFUA1Enabled || isPDFA2AEnabled
        }

        var requiresOutputIntent: Bool {
            isPDFA2AEnabled
        }

        var requiresFileIdentifier: Bool {
            isPDFA2AEnabled
        }

        var displayName: String {
            switch (isPDFUA1Enabled, isPDFA2AEnabled) {
            case (true, true):
                "PDF/UA-1 + PDF/A-2a"
            case (true, false):
                "PDF/UA-1"
            case (false, true):
                "PDF/A-2a"
            case (false, false):
                "default PDF"
            }
        }
    }
}

private extension PDFOptions.Theme {
    static func defaultElements(palette: PDFOptions.Palette) -> [PDFOptions.ElementRole: PDFOptions.ElementStyle] {
        baseElements(
            palette: palette,
            bodyColor: .black,
            mutedColor: .gray,
            linkColor: .link,
            codeBackground: PDFColor(red: 0.95, green: 0.95, blue: 0.95),
            tableHeaderBackground: PDFColor(red: 0.93, green: 0.93, blue: 0.93),
            tableBorder: .gray,
        )
    }

    static func darkElements(palette: PDFOptions.Palette) -> [PDFOptions.ElementRole: PDFOptions.ElementStyle] {
        baseElements(
            palette: palette,
            bodyColor: palette.foreground,
            mutedColor: palette.mutedForeground,
            linkColor: palette.link,
            codeBackground: palette.surface,
            tableHeaderBackground: palette.raisedSurface,
            tableBorder: palette.border,
        )
    }

    static func printElements(palette: PDFOptions.Palette) -> [PDFOptions.ElementRole: PDFOptions.ElementStyle] {
        baseElements(
            palette: palette,
            bodyColor: palette.foreground,
            mutedColor: palette.mutedForeground,
            linkColor: palette.link,
            codeBackground: palette.raisedSurface,
            tableHeaderBackground: palette.raisedSurface,
            tableBorder: palette.border,
        )
    }

    static func baseElements(
        palette _: PDFOptions.Palette,
        bodyColor: PDFColor,
        mutedColor: PDFColor,
        linkColor: PDFColor,
        codeBackground: PDFColor,
        tableHeaderBackground: PDFColor,
        tableBorder: PDFColor,
    ) -> [PDFOptions.ElementRole: PDFOptions.ElementStyle] {
        [
            .body: PDFOptions.ElementStyle(
                fontRole: .regular,
                color: bodyColor,
            ),
            .paragraph: PDFOptions.ElementStyle(
                fontRole: .regular,
                lineHeightMultiplier: 1.24,
                color: bodyColor,
                spacingAfterMultiplier: 6.0 / 11.0,
            ),
            .heading1: PDFOptions.ElementStyle(
                fontRole: .bold,
                sizeMultiplier: 2.0,
                lineHeightMultiplier: 1.25,
                color: bodyColor,
                spacingBeforeMultiplier: 1.4,
                spacingAfterMultiplier: 0.5,
            ),
            .heading2: PDFOptions.ElementStyle(
                fontRole: .bold,
                sizeMultiplier: 1.55,
                lineHeightMultiplier: 1.25,
                color: bodyColor,
                spacingBeforeMultiplier: 1.8,
                spacingAfterMultiplier: 0.5,
            ),
            .heading3: PDFOptions.ElementStyle(
                fontRole: .bold,
                sizeMultiplier: 1.3,
                lineHeightMultiplier: 1.25,
                color: bodyColor,
                spacingBeforeMultiplier: 1.45,
                spacingAfterMultiplier: 0.5,
            ),
            .heading4: PDFOptions.ElementStyle(
                fontRole: .bold,
                sizeMultiplier: 1.1,
                lineHeightMultiplier: 1.25,
                color: bodyColor,
                spacingBeforeMultiplier: 0.95,
                spacingAfterMultiplier: 0.5,
            ),
            .heading5: PDFOptions.ElementStyle(
                fontRole: .bold,
                sizeMultiplier: 1.1,
                lineHeightMultiplier: 1.25,
                color: bodyColor,
                spacingBeforeMultiplier: 0.5,
                spacingAfterMultiplier: 0.5,
            ),
            .heading6: PDFOptions.ElementStyle(
                fontRole: .bold,
                sizeMultiplier: 1.1,
                lineHeightMultiplier: 1.25,
                color: bodyColor,
                spacingBeforeMultiplier: 0.5,
                spacingAfterMultiplier: 0.5,
            ),
            .blockQuote: PDFOptions.ElementStyle(
                fontRole: .regular,
                color: bodyColor,
                spacingBeforeMultiplier: 0.45,
                spacingAfterMultiplier: 0.55,
            ),
            .list: PDFOptions.ElementStyle(
                fontRole: .regular,
                lineHeightMultiplier: 1.15,
                color: bodyColor,
                spacingAfterMultiplier: 3.0 / 11.0,
            ),
            .listMarker: PDFOptions.ElementStyle(
                fontRole: .regular,
                color: bodyColor,
            ),
            .link: PDFOptions.ElementStyle(
                fontRole: .regular,
                color: linkColor,
                underline: true,
            ),
            .inlineCode: PDFOptions.ElementStyle(
                fontRole: .monospaced,
                sizeMultiplier: 0.95,
                color: bodyColor,
            ),
            .inlineMath: PDFOptions.ElementStyle(
                fontRole: .regular,
                color: bodyColor,
            ),
            .displayMath: PDFOptions.ElementStyle(
                fontRole: .regular,
                sizeMultiplier: 1.08,
                lineHeightMultiplier: 1.35,
                color: bodyColor,
                spacingBeforeMultiplier: 0.45,
                spacingAfterMultiplier: 0.55,
            ),
            .codeBlock: PDFOptions.ElementStyle(
                fontRole: .monospaced,
                sizeMultiplier: 0.9,
                lineHeightMultiplier: 1.4,
                color: bodyColor,
                backgroundColor: codeBackground,
                spacingAfterMultiplier: 0.75,
            ),
            .tableHeader: PDFOptions.ElementStyle(
                fontRole: .bold,
                sizeMultiplier: 0.9,
                lineHeightMultiplier: 1.35,
                color: bodyColor,
                backgroundColor: tableHeaderBackground,
                borderColor: tableBorder,
            ),
            .tableCell: PDFOptions.ElementStyle(
                fontRole: .regular,
                sizeMultiplier: 0.9,
                lineHeightMultiplier: 1.35,
                color: bodyColor,
                borderColor: tableBorder,
            ),
            .thematicBreak: PDFOptions.ElementStyle(
                fontRole: .regular,
                color: mutedColor,
                borderColor: tableBorder,
            ),
            .footnote: PDFOptions.ElementStyle(
                fontRole: .regular,
                sizeMultiplier: 0.86,
                lineHeightMultiplier: 1.32,
                color: bodyColor,
                borderColor: mutedColor,
                spacingAfterMultiplier: 0.35,
            ),
            .html: PDFOptions.ElementStyle(
                fontRole: .monospaced,
                sizeMultiplier: 0.9,
                lineHeightMultiplier: 1.35,
                color: mutedColor,
                spacingAfterMultiplier: 9.0 / 11.0,
            ),
            .imagePlaceholder: PDFOptions.ElementStyle(
                fontRole: .italic,
                color: mutedColor,
            ),
        ]
    }
}
