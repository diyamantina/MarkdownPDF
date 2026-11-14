import Foundation
@testable import MarkdownPDF
import Testing

@Suite("PDF visual layout validation")
struct PDFVisualLayoutValidationTests {
    @Test("Generated PDFs do not have overlapping word boxes")
    func generatedPDFsDoNotHaveOverlappingWordBoxes() throws {
        let data = try visualValidationPDF()
        let document = try PDFDocumentReader(data: data)
        let layout = ReaderTextLayout(document)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "visual-layout/words.tsv")
        try PDFValidation.writeTextArtifact(document.text, name: "visual-layout/text.txt")
        let sizes = document.pages.map { "\($0.size.width) x \($0.size.height) pts" }
        try PDFValidation.writeTextArtifact(
            (["Pages: \(document.pageCount)", "PDF version: \(document.version)", "Title: \(document.title ?? "")"] + sizes).joined(separator: "\n") + "\n",
            name: "visual-layout/document.txt",
        )

        let issues = layout.visualLayoutIssues()

        #expect(layout.pages.count >= 4)
        #expect(layout.words.count > 200)
        #expect(layout.words.contains { $0.text == "Table" })
        #expect(layout.words.contains { $0.text == "Contents" })
        #expect(
            issues.isEmpty,
            "The text layout has visual issues:\n\(issues.joined(separator: "\n"))",
        )
    }

    @Test("Generated code blocks wrap long lines inside page bounds")
    func generatedCodeBlocksWrapLongLinesInsidePageBounds() throws {
        let markdown = """
        # Code block wrapping

        ```text
        let clippedLine = "Author[Author input] --> Parser[Swift parser] --> Renderer[PDF renderer] --> Tools[Open tools]"
        ```
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 220, height: 220),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
            ),
        ).render(markdown: markdown)

        let layout = try ReaderTextLayout(data: data)
        #expect(layout.visualLayoutIssues().isEmpty)
        #expect(layout.words.contains { $0.text == "Renderer[PDF" })
        #expect(layout.words.contains { $0.text == "tools]\"" })
    }

    @Test("Syntax-colored manuscript passes visual witness stack")
    func syntaxColoredManuscriptPassesVisualWitnessStack() throws {
        let data = try syntaxColoringManuscriptPDF()
        try PDFValidation.requireSoundStructure(data, name: "syntax-coloring-manuscript")
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")

        #expect(pageCount >= 2)
        #expect(streamText.contains("0.050 0.200 0.550 rg"))
        #expect(streamText.contains("0.280 0.380 0.280 rg"))
        try PDFValidation.writeArtifact(data, name: "syntax-coloring-manuscript.pdf")

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "syntax-coloring-manuscript/text.txt")
        let normalizedText = normalizedExtractedText(extractedText)
        #expect(normalizedText.contains("Portable Syntax Coloring Manuscript"))
        #expect(normalizedText.contains("Source coloring must preserve extraction and spacing."))
        #expect(normalizedText.contains("TabbedSyntaxColoringWitnessLongIdent"))
        #expect(normalizedText.contains("plainUnsupported"))
        #expect(normalizedText.contains("Syntax Coloring Manuscript Exit Marker"))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "syntax-coloring-manuscript/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()

        #expect(layout.pages.count == pageCount)
        #expect(layout.words.count > 220)
        #expect(
            layoutIssues.isEmpty,
            "Syntax-colored manuscript word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )
        #expect(layout.visibleCharacterCount > 1200)
    }

    @Test("RTL manuscript passes visual witness stack")
    func rtlManuscriptPassesVisualWitnessStack() throws {
        let data = try rtlManuscriptPDF()
        try PDFValidation.requireSoundStructure(data, name: "rtl-manuscript")
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount
        let hebrewWord = "\u{05D0}\u{05D1}\u{05D2}\u{05D3}"
        let arabicWord = "\u{0633}\u{0644}\u{0627}\u{0645}"
        let arabicIndic12 = "\u{0661}\u{0662}"

        #expect(pageCount >= 2)
        #expect(inspector.hasValidXrefOffsets())
        #expect(inspector.streamLengthsMatch())
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "RTL manuscript PDF structure issues:\n\(inspector.canonicalStructureIssues().joined(separator: "\n"))",
        )
        #expect(inspector.text.contains("/Subtype /Type0"))
        #expect(inspector.text.contains("/Subtype /CIDFontType2"))
        #expect(inspector.text.contains("/FontFile2"))
        #expect(inspector.text.contains("/ToUnicode"))
        let mirrorCIDBase = try Int(TrueTypeFontParser()
            .parse(SyntheticTrueTypeFont.data(glyphProfile: .rtlWitness, includeGlyphOutlines: true))
            .maxp
            .numGlyphs)
        let mirroredCodes = (1 ... 8).map { mirrorCIDBase + $0 }
        for code in mirroredCodes {
            let codeHex = Self.pdfHex(code)
            #expect(
                inspector.streams.contains { $0.body.contains("\(codeHex) Tj") },
                "RTL manuscript did not emit mirrored CID \(codeHex)",
            )
        }
        #expect(inspector.text.contains("\(Self.pdfHex(mirrorCIDBase + 1)) \(Self.pdfHex(mirrorCIDBase + 2)) <0028>"))
        #expect(inspector.text.contains("\(Self.pdfHex(mirrorCIDBase + 3)) <003C>"))
        #expect(inspector.text.contains("\(Self.pdfHex(mirrorCIDBase + 4)) <003E>"))
        #expect(inspector.text.contains("\(Self.pdfHex(mirrorCIDBase + 5)) <005B>"))
        #expect(inspector.text.contains("\(Self.pdfHex(mirrorCIDBase + 6)) <005D>"))
        #expect(inspector.text.contains("\(Self.pdfHex(mirrorCIDBase + 7)) <007B>"))
        #expect(inspector.text.contains("\(Self.pdfHex(mirrorCIDBase + 8)) <007D>"))

        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        try PDFValidation.writeTextArtifact(Self.rtlManuscriptManifest, name: "rtl-manuscript/README.txt")
        try PDFValidation.writeArtifact(data, name: "rtl-manuscript.pdf")

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "rtl-manuscript/text.txt")
        let normalizedText = normalizedExtractedText(extractedText)
        #expect(normalizedText.contains("RTLPARATOKENA"))
        #expect(normalizedText.contains("ULISTTOKENA"))
        #expect(normalizedText.contains("OLISTTOKENA"))
        #expect(normalizedText.contains("QUOTETOKENA"))
        #expect(normalizedText.contains("ROWA"))

        // The reader gives text in the order of the content stream, which is the
        // logical order the writer emits: this is the logical-order witness.
        let compactRawText = compactLogicalExtractedText(extractedText)
        #expect(compactRawText.contains("\(hebrewWord)(123)CODE\(arabicWord)\(arabicIndic12)RTLPARATOKENA."))
        #expect(compactRawText.contains("\(arabicWord)[CODE]\(hebrewWord)ULISTTOKENA."))
        #expect(compactRawText.contains("\(hebrewWord)\"CODE\"\(arabicWord)OLISTTOKENA."))
        #expect(compactRawText.contains("\(arabicWord)(123)\(hebrewWord)QUOTETOKENA."))
        #expect(compactRawText.contains("\(hebrewWord)HEADER"))
        #expect(compactRawText.contains("\(arabicWord)\(arabicIndic12)ROWA"))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "rtl-manuscript/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()

        #expect(layout.pages.count == pageCount)
        #expect(layout.words.count > 90)
        #expect(
            layoutIssues.isEmpty,
            "RTL manuscript word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )
        #expect(layout.visibleCharacterCount > 500)
    }

    @Test("Generated PDFs keep every visible character in a word box on its page")
    func generatedPDFsKeepEveryVisibleCharacterInAWordBox() throws {
        let data = try visualValidationPDF()
        let document = try PDFDocumentReader(data: data)
        let layout = ReaderTextLayout(document)
        let issues = layout.visualLayoutIssues()

        #expect(layout.pages.count >= 4)
        #expect(layout.visibleCharacterCount > 1200)
        // Every character the pages show is in a word: nothing is drawn that the boxes do not cover.
        let shown = document.pages.flatMap(\.runs).reduce(0) { $0 + $1.text.count(where: { !$0.isWhitespace }) }
        #expect(layout.visibleCharacterCount == shown)
        #expect(
            issues.isEmpty,
            "The character layout has visual issues:\n\(issues.joined(separator: "\n"))",
        )
    }

    /// The raster step the witness stacks of this suite ended with: two outside
    /// rasterizers drew every page, each had to leave ink, and their ink bounds
    /// had to agree. One case for each PDF that went through it.
    @Test(
        "Every page of a witness PDF rasterizes to comparable ink",
        .disabled("not verified: needs a rasterizer inside MarkdownPDF, see Docs/NOT-VERIFIED.md"),
        arguments: PDFVisualLayoutValidationTests.rasterWitnessNames,
    )
    func rasterWitness(_ name: String) {
        PDFValidation.notVerified("the raster of \(name)")
    }

    static let rasterWitnessNames = [
        "visual-layout", "syntax-coloring-manuscript", "rtl-manuscript", "article-grade-stress", "hard-markdown-corpus",
        "crazy-markdown-torture", "a4-manuscript", "text-encoding-profile", "embedded-cid-text", "cjk-diacritics-manuscript",
        "embedded-font-public-api", "oversized-blocks", "measured-tables", "native-charts", "diagram-policy",
        "source-code-spacing", "screenshot-source-code-regressions",
    ]

    @Test("Article stress fixture passes visual witness stack")
    func articleStressFixturePassesVisualWitnessStack() throws {
        let data = try articleStressFixturePDF()
        try PDFValidation.requireSoundStructure(data, name: "article-grade-stress")
        let pageCount = PDFInspector(data).pageCount

        #expect(pageCount >= 6)
        try PDFValidation.writeArtifact(data, name: "article-grade-stress.pdf")

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "article-stress/text.txt")
        #expect(extractedText.contains("Portable Article Stress Corpus"))
        #expect(extractedText.contains("Table of Contents"))
        #expect(extractedText.contains("Local chart placeholder"))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "article-stress/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()

        #expect(layout.pages.count == pageCount)
        #expect(layout.words.count > 500)
        #expect(
            layoutIssues.isEmpty,
            "Article stress fixture word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )
        #expect(layout.visibleCharacterCount > 2500)
    }

    @Test("Hard Markdown fixture passes visual witness stack")
    func hardMarkdownFixturePassesVisualWitnessStack() throws {
        let data = try hardMarkdownFixturePDF()
        try PDFValidation.requireSoundStructure(data, name: "hard-markdown-corpus")
        let pageCount = PDFInspector(data).pageCount

        #expect(pageCount >= 8)
        try PDFValidation.writeArtifact(data, name: "hard-markdown-corpus.pdf")

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "hard-markdown-corpus/text.txt")
        let normalizedText = normalizedExtractedText(extractedText)
        #expect(normalizedText.contains("Portable Hard Markdown Corpus"))
        #expect(normalizedText.contains("Raw HTML fallback for the hard corpus"))
        #expect(normalizedText.contains("Hard Fixture Exit Marker"))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "hard-markdown-corpus/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()

        #expect(layout.pages.count == pageCount)
        #expect(layout.words.count > 850)
        #expect(
            layoutIssues.isEmpty,
            "Hard Markdown fixture word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )
        #expect(layout.visibleCharacterCount > 4500)
    }

    @Test("Crazy Markdown fixture passes visual witness stack")
    func crazyMarkdownFixturePassesVisualWitnessStack() throws {
        let data = try crazyMarkdownFixturePDF()
        try PDFValidation.requireSoundStructure(data, name: "crazy-markdown-torture")
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount

        #expect(pageCount >= 6)
        try PDFValidation.writeArtifact(data, name: "crazy-markdown-torture.pdf")

        let verticalRuleLines = inspector.streams.flatMap { stream in
            verticalRuleOperatorLines(in: stream.body)
        }
        #expect(
            verticalRuleLines.isEmpty,
            "Crazy Markdown fixture emitted unexpected vertical rule operators:\n\(verticalRuleLines.joined(separator: "\n"))",
        )

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "crazy-markdown-torture/text.txt")
        let normalizedText = normalizedExtractedText(extractedText)
        #expect(normalizedText.contains("Crazy Markdown Torture Manuscript"))
        #expect(normalizedText.contains("DeepListLevelThreeMarker"))
        #expect(normalizedText.contains("QuoteBulletTwoMarker"))
        #expect(normalizedText.contains("Crazy Torture Exit Marker"))
        // Accented Latin renders via WinAnsi; a decomposed combining-mark sample is
        // NFC-normalized to its precomposed WinAnsi byte, so it extracts as "café",
        // not "cafe?" (#37).
        #expect(normalizedText.contains("Café"))
        #expect(normalizedText.contains("café"))
        #expect(!normalizedText.contains("cafe?"))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "crazy-markdown-torture/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()

        #expect(layout.pages.count == pageCount)
        #expect(layout.words.count > 1000)
        #expect(
            layoutIssues.isEmpty,
            "Crazy Markdown fixture word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )
        #expect(layout.visibleCharacterCount > 6500)
    }

    @Test("A4 manuscript fixture passes visual witness stack")
    func a4ManuscriptFixturePassesVisualWitnessStack() throws {
        let data = try a4ManuscriptFixturePDF()
        try PDFValidation.requireSoundStructure(data, name: "a4-manuscript")
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount

        #expect(pageCount >= 5)
        try PDFValidation.writeArtifact(data, name: "a4-manuscript.pdf")

        let document = try PDFDocumentReader(data: data)
        #expect(document.pageCount == pageCount)
        // A4 is 595.28 x 841.89 points, to the two decimals the file gives.
        #expect(document.pages.allSatisfy { abs($0.size.width - 595.28) < 0.005 && abs($0.size.height - 841.89) < 0.005 })

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "a4-manuscript/text.txt")
        let normalizedText = normalizedExtractedText(extractedText)
        #expect(normalizedText.contains("Portable A4 Manuscript Fixture"))
        #expect(normalizedText.contains("Table of Contents"))
        #expect(normalizedText.contains("A4 Manuscript Exit Marker"))
        #expect(normalizedText.contains("A4 manuscript chart"))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "a4-manuscript/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()

        #expect(layout.pages.count == pageCount)
        #expect(layout.words.count > 1600)
        #expect(
            layoutIssues.isEmpty,
            "A4 manuscript fixture word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )
        #expect(layout.visibleCharacterCount > 9000)
    }

    @Test("Portable text encoding profile passes visual witness stack")
    func portableTextEncodingProfilePassesVisualWitnessStack() throws {
        let markdown = """
        # Portable Text Encoding

        ASCII: The quick brown fox stays portable.

        Latin: Caf\u{00E9} ni\u{00F1}o NBSP\u{00A0}done.

        WinAnsi: \u{201C}quoted\u{201D} \u{20AC}.

        Unicode: \u{010D} \u{03C0} \u{1F680}.
        """
        let data = try MarkdownPDFRenderer(options: PDFOptions(baseFontSize: 10)).render(markdown: markdown)
        try PDFValidation.requireSoundStructure(data, name: "portable-text-encoding")
        let inspector = PDFInspector(data)

        #expect(inspector.pageCount == 1)
        #expect(inspector.text.contains("/ToUnicode"))
        #expect(inspector.text.contains("/FontFile2"))
        try PDFValidation.writeArtifact(data, name: "text-encoding-profile.pdf")

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "text-encoding/text.txt")
        #expect(extractedText.contains("ASCII: The quick brown fox stays portable."))
        // Accented Latin, NBSP, curly quotes, and the euro sign now render
        // through the base-14 WinAnsi encoding with no embedded font.
        // The reader gives the no-break space as the character the file holds
        // (WinAnsi code 160), where an extractor that rebuilds spacing gave a plain space.
        #expect(extractedText.contains("Latin: Café niño NBSP\u{00A0}done."))
        #expect(extractedText.contains("WinAnsi: \u{201C}quoted\u{201D} \u{20AC}."))
        // Non-WinAnsi content selects the bundled font. Scalars it covers render
        // directly; an unsupported emoji draws .notdef but remains extractable
        // through the run's ActualText override.
        #expect(extractedText.contains("Unicode: č π 🚀."))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "text-encoding/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()
        #expect(
            layoutIssues.isEmpty,
            "Text encoding word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )
    }

    @Test("WinAnsi base-14 renders Western text without a question-mark fallback")
    func winAnsiBase14RendersWesternTextWithoutFallback() throws {
        // No embedded font: this is the default base-14 profile. Every character
        // here is WinAnsi-representable, so none may degrade to "?".
        let markdown = """
        Accents: Café résumé naïve Zürich señor garçon.
        Punctuation: \u{201C}smart\u{201D} \u{2018}quotes\u{2019} en\u{2013}dash em\u{2014}dash.
        Symbols: \u{20AC}5 \u{00A3}3 \u{00A2}50 \u{00A9} \u{00AE} \u{2122} \u{00B0}C \u{00B1}1.
        """
        let data = try MarkdownPDFRenderer().render(markdown: markdown)

        PDFValidation.expectSoundStructure(data, name: "winansi-western")
        let extracted = try PDFValidation.text(data)

        // The representable characters extract as themselves, not "?".
        for token in [
            "Café", "résumé", "naïve", "Zürich", "señor", "garçon",
            "\u{201C}smart\u{201D}", "\u{2018}quotes\u{2019}", "en\u{2013}dash", "em\u{2014}dash",
            "\u{20AC}5", "\u{00A3}3", "\u{00A2}50", "\u{00A9}", "\u{00AE}", "\u{2122}", "\u{00B0}C", "\u{00B1}1",
        ] {
            #expect(extracted.contains(token), "WinAnsi text degraded; missing \(token) in:\n\(extracted)")
        }
        // And none of those lines fell back to a question mark.
        for line in extracted.split(separator: "\n") where line.contains("Café") || line.contains("smart") || line.contains("\u{20AC}5") {
            #expect(!line.contains("?"), "Unexpected '?' fallback in WinAnsi line: \(line)")
        }
    }

    @Test("Embedded CID text profile passes visual witness stack")
    func embeddedCIDTextProfilePassesVisualWitnessStack() throws {
        let data = try embeddedCIDTextPDF()
        try PDFValidation.requireSoundStructure(data, name: "embedded-cid-text")
        let inspector = PDFInspector(data)

        #expect(inspector.pageCount == 1)
        #expect(inspector.text.contains("/Subtype /Type0"))
        #expect(inspector.text.contains("/Subtype /CIDFontType2"))
        #expect(inspector.text.contains("/FontFile2"))
        #expect(inspector.text.contains("/ToUnicode"))
        #expect(inspector.text.contains("/CIDToGIDMap "))
        #expect(!inspector.text.contains("/CIDToGIDMap /Identity"))
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        try PDFValidation.writeArtifact(data, name: "embedded-cid-text.pdf")

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "embedded-cid-text/text.txt")
        #expect(extractedText.contains("WIDE WILLIAM MINIMUM MARGIN"))
        #expect(extractedText.contains("LATIN CID TEXT STAYS ALIGNED"))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "embedded-cid-text/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()
        #expect(layout.words.count >= 18)
        #expect(
            layoutIssues.isEmpty,
            "Embedded CID text word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )
        #expect(layout.visibleCharacterCount >= 88)
    }

    @Test("CJK and diacritics manuscript passes visual witness stack")
    func cjkAndDiacriticsManuscriptPassesVisualWitnessStack() throws {
        let data = try cjkDiacriticsManuscriptPDF()
        try PDFValidation.requireSoundStructure(data, name: "cjk-diacritics-manuscript")
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount

        #expect(pageCount >= 2)
        #expect(inspector.hasValidXrefOffsets())
        #expect(inspector.streamLengthsMatch())
        #expect(inspector.text.contains("/Subtype /Type0"))
        #expect(inspector.text.contains("/Subtype /CIDFontType2"))
        #expect(inspector.text.contains("/FontFile2"))
        #expect(inspector.text.contains("/ToUnicode"))
        #expect(inspector.text.contains("/CIDToGIDMap "))
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "CJK and diacritics canonical PDF structure failed:\n\(inspector.canonicalStructureReport())",
        )
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        try PDFValidation.writeArtifact(data, name: "cjk-diacritics-manuscript.pdf")

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "cjk-diacritics-manuscript/text.txt")
        let normalizedText = normalizedExtractedText(extractedText)
        let compactText = extractedText.filter { !$0.isWhitespace }
        #expect(normalizedText.contains("Latin text"))
        #expect(normalizedText.contains("1."))
        #expect(compactText.contains("漢字語漢字語"))
        #expect(compactText.contains("e\u{0301}"))
        #expect(compactText.contains("漢\u{0301}字語"))
        #expect(try compactText.unicodeScalars.contains(#require(UnicodeScalar(0x0301))))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "cjk-diacritics-manuscript/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()

        #expect(layout.pages.count == pageCount)
        #expect(Set(layout.words.map(\.page)).count == pageCount)
        #expect(
            layoutIssues.isEmpty,
            "CJK and diacritics word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )
        #expect(layout.visibleCharacterCount > 500)
    }

    @Test("Embedded font public API profile passes visual witness stack")
    func embeddedFontPublicAPIProfilePassesVisualWitnessStack() throws {
        let data = try embeddedFontPublicAPIPDF()
        try PDFValidation.requireSoundStructure(data, name: "embedded-font-public-api")
        let inspector = PDFInspector(data)

        #expect(inspector.pageCount >= 2)
        #expect(inspector.text.contains("/Subtype /Type0"))
        #expect(inspector.text.contains("/Subtype /CIDFontType2"))
        #expect(inspector.text.contains("/FontFile2"))
        #expect(inspector.text.contains("/ToUnicode"))
        #expect(inspector.text.contains("/EF1"))
        #expect(inspector.text.contains("/EF2"))
        #expect(inspector.text.contains("/EF3"))
        #expect(inspector.text.contains("/EF4"))
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        try PDFValidation.writeArtifact(data, name: "embedded-font-public-api.pdf")

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "embedded-font-public-api/text.txt")
        let normalizedText = normalizedExtractedText(extractedText)
        #expect(normalizedText.contains("PUBLIC EMBEDDED FONT PROFILE"))
        #expect(normalizedText.contains("BOLD ROLE"))
        #expect(normalizedText.contains("ITALIC ROLE"))
        #expect(normalizedText.contains("CODE ROLE"))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "embedded-font-public-api/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()
        #expect(layout.pages.count == inspector.pageCount)
        #expect(layout.words.count > 120)
        #expect(
            layoutIssues.isEmpty,
            "Embedded font public API word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )
        #expect(layout.visibleCharacterCount > 700)
    }

    @Test("Oversized blocks split or scale inside page bounds")
    func oversizedBlocksSplitOrScaleInsidePageBounds() throws {
        let code = (1 ... 18)
            .map { "code_line_\($0) = \"portable overflow policy keeps this line on page\"" }
            .joined(separator: "\n")
        let tablePayload = (1 ... 54)
            .map { "cell\($0)" }
            .joined(separator: " ")
        let mermaidEdges = (1 ... 10)
            .map { "N\($0)[Node \($0)] --> N\($0 + 1)[Node \($0 + 1)]" }
            .joined(separator: "\n")
        let markdown = """
        ![Tall local chart](tall-chart.png)

        # Oversized Blocks

        | Kind | Payload |
        |---|---|
        | Tall row | \(tablePayload) |

        ```mermaid
        flowchart TD
        \(mermaidEdges)
        ```

        ```text
        \(code)
        ```
        """
        let assetsBaseURL = try TestImageAssets.directoryWithChartPNG(
            named: "tall-chart.png",
            width: 640,
            height: 1600,
        )
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 220),
                margins: PDFOptions.Margins(top: 70, right: 22, bottom: 70, left: 22),
                baseFontSize: 9,
            ),
        ).render(markdown: markdown, assetsBaseURL: assetsBaseURL)
        try PDFValidation.requireSoundStructure(data, name: "oversized-blocks")
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount

        #expect(pageCount >= 6)
        #expect(inspector.streams.contains { $0.body.contains("32 0 0 80 22 70 cm") })
        try PDFValidation.writeArtifact(data, name: "oversized-blocks.pdf")

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "oversized-blocks/text.txt")
        #expect(extractedText.contains("Tall row"))
        #expect(extractedText.contains("Unsupported Mermaid diagram"))
        #expect(extractedText.contains("code_line_18"))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "oversized-blocks/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()
        #expect(
            layoutIssues.isEmpty,
            "Oversized block word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )
    }

    @Test("Measured tables preserve alignment and repeat headers across pages")
    func measuredTablesPreserveAlignmentAndRepeatHeadersAcrossPages() throws {
        let longCell = (1 ... 56)
            .map { "span\($0)" }
            .joined(separator: " ")
        let rows = (1 ... 16)
            .map { row in
                let description = [
                    "Measured prose cell \(row) keeps words separated near borders",
                    "UltraPortableDeterministicTableTokenWithoutSpaces\(row)",
                    "and wraps dense article-style language across the measured column.",
                ].joined(separator: " ")
                return "| row-\(row) | \(description) | \(90 + row) |"
            }
            .joined(separator: "\n")
        let markdown = """
        # Measured Tables

        | ID | Description | Score |
        |:---|:---:|---:|
        | intro | \(longCell) | 100 |
        \(rows)
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 280, height: 250),
                margins: PDFOptions.Margins(top: 30, right: 24, bottom: 30, left: 24),
                baseFontSize: 9,
            ),
        ).render(markdown: markdown)
        try PDFValidation.requireSoundStructure(data, name: "measured-tables")
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount

        #expect(pageCount >= 4)
        #expect(tableRectangleWidths(in: inspector).contains { $0 < 60 })
        #expect(tableRectangleWidths(in: inspector).contains { $0 > 95 })
        try PDFValidation.writeArtifact(data, name: "measured-tables.pdf")

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "measured-tables/text.txt")
        #expect(extractedText.contains("row-16"))
        #expect(extractedText.components(separatedBy: "Description").count >= 3)

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "measured-tables/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()
        #expect(
            layoutIssues.isEmpty,
            "Measured table word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )
    }

    @Test("Native charts pass visual witness stack")
    func nativeChartsPassVisualWitnessStack() throws {
        let markdown = """
        # Native Chart Witness

        ```mermaid
        pie title Deployment Share
            "Stable" : 68
            "Canary" : 22
            "Experimental" : 10
        ```

        ```chart
        type: bar
        title: Quarterly Revenue
        categories: Q1, Q2, Q3, Q4
        y-label: USD
        series: Actual = 3, 5, 4, 7
        series: Forecast = 4, 6, 5, 8
        ```

        ```chart
        type: line
        title: Adoption Trend
        categories: Jan, Feb, Mar, Apr
        x-label: month
        y-label: users
        series: Accounts = 2, 4, 7, 9
        ```

        ```chart
        type: scatter
        title: Impact Map
        x-label: effort
        y-label: impact
        series: Trials = (1, 2), (2, 4), (4, 7), (5, 9)
        ```
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 320, height: 420),
                margins: PDFOptions.Margins(top: 30, right: 28, bottom: 30, left: 28),
                baseFontSize: 9,
            ),
        ).render(markdown: markdown)
        try PDFValidation.requireSoundStructure(data, name: "native-charts")
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")

        #expect(pageCount >= 2)
        #expect(streamText.contains(" c"))
        #expect(streamText.contains(" re f"))
        #expect(streamText.contains(" l"))
        try PDFValidation.writeArtifact(data, name: "native-charts.pdf")

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "native-charts/text.txt")
        #expect(extractedText.contains("Deployment Share"))
        #expect(extractedText.contains("Stable 68"))
        #expect(extractedText.contains("Quarterly Revenue"))
        #expect(extractedText.contains("Actual"))
        #expect(extractedText.contains("Adoption Trend"))
        #expect(extractedText.contains("Accounts"))
        #expect(extractedText.contains("Impact Map"))
        #expect(extractedText.contains("Trials"))
        #expect(!extractedText.contains("Unsupported chart"))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "native-charts/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()
        #expect(
            layoutIssues.isEmpty,
            "Native chart word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )
    }

    @Test("Diagram policy witness covers edge labels, native charts, and fallback")
    func diagramPolicyWitnessCoversEdgeLabelsNativeChartsAndFallback() throws {
        let markdown = """
        # Diagram Policy

        ```mermaid
        flowchart TD
            Source["Markdown input"] -->|parse| Parser["Flow parser"]
            Parser -->|draw| Renderer["PDF renderer"]
        ```

        ```mermaid
        pie title Native chart
            "Alpha" : 3
            "Beta" : 2
        ```

        ```mermaid
        sequenceDiagram
            Alice->>Bob: still unsupported
        ```
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 280, height: 300),
                margins: PDFOptions.Margins(top: 28, right: 24, bottom: 28, left: 24),
                baseFontSize: 10,
            ),
        ).render(markdown: markdown)
        try PDFValidation.requireSoundStructure(data, name: "diagram-policy")
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount

        #expect(pageCount >= 1)
        try PDFValidation.writeArtifact(data, name: "diagram-policy.pdf")

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "diagram-policy/text.txt")
        #expect(extractedText.contains("Markdown input"))
        #expect(extractedText.contains("parse"))
        #expect(extractedText.contains("draw"))
        #expect(!extractedText.contains("Source[\"Markdown input\"]"))
        #expect(!extractedText.contains("Parser[\"Flow parser\"]"))
        #expect(extractedText.contains("Native chart"))
        #expect(extractedText.contains("Alpha 3"))
        #expect(extractedText.contains("Beta 2"))
        #expect(extractedText.contains("Unsupported Mermaid diagram"))
        #expect(extractedText.contains("sequenceDiagram"))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "diagram-policy/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()
        #expect(
            layoutIssues.isEmpty,
            "Diagram policy word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )
    }

    @Test("Code and quote spacing keeps following text separated")
    func codeAndQuoteSpacingKeepsFollowingTextSeparated() throws {
        let markdown = """
        # Quote Spacing Witness

        The first struct tracks surface characteristics in a single block:

        ```metal
        struct Surface {
            float3 baseColor;
            float shininess;
            float roughness;
            float emissive;
            float3 transmission;
            float indexOfRefraction;
            float CodeBlockEndToken;
        };
        ```

        > QuoteStartToken surface measurements should stay clear of the preceding code background and finish with QuoteEndToken

        AfterQuoteParagraph begins below the quote, with enough spacing to avoid a crammed transition.

        ```metal
        struct SurfaceRefraction {
            half3 transmission;
            half indexOfRefraction;
            half SecondCodeBlockEndToken;
        };
        ```

        > SecondQuoteStartToken the second quote is directly followed by a heading and ends with SecondQuoteEndToken

        ## AfterQuoteHeading

        AfterHeadingParagraph keeps normal flow below the heading.
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 420, height: 720),
                margins: PDFOptions.Margins(top: 42, right: 42, bottom: 42, left: 42),
                baseFontSize: 12,
                title: "Quote Spacing Witness",
            ),
        ).render(markdown: markdown)
        try PDFValidation.writeArtifact(data, name: "quote-spacing.pdf")

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "quote-spacing/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()

        #expect(
            layoutIssues.isEmpty,
            "Quote spacing word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )

        let codeEnd = try word("CodeBlockEndToken;", in: layout)
        let quoteStart = try word("QuoteStartToken", in: layout)
        let quoteEnd = try word("QuoteEndToken", in: layout)
        let afterParagraph = try word("AfterQuoteParagraph", in: layout)
        let secondCodeEnd = try word("SecondCodeBlockEndToken;", in: layout)
        let secondQuoteStart = try word("SecondQuoteStartToken", in: layout)
        let secondQuoteEnd = try word("SecondQuoteEndToken", in: layout)
        let afterHeading = try word("AfterQuoteHeading", in: layout)

        #expect(quoteStart.page == codeEnd.page)
        #expect(afterParagraph.page == quoteEnd.page)
        #expect(secondQuoteStart.page == secondCodeEnd.page)
        #expect(quoteStart.top > codeEnd.bottom + 10)
        #expect(afterParagraph.top > quoteEnd.bottom + 4)
        #expect(secondQuoteStart.top > secondCodeEnd.bottom + 10)
        if afterHeading.page == secondQuoteEnd.page {
            #expect(afterHeading.top > secondQuoteEnd.bottom + 8)
        } else {
            #expect(afterHeading.page > secondQuoteEnd.page)
        }
    }

    @Test("Source code witness stack catches crammed flow and glyph overlap")
    func sourceCodeWitnessStackCatchesCrammedFlowAndGlyphOverlap() throws {
        let longIdentifier = "PortableSourceCodeWitnessLongIdentifier"
            + String(repeating: "Segment", count: 14)
        let denseMetalLines = (1 ... 14).map { index in
            [
                "if ((rayMask & (1 << \(index))) != 0) {",
                "\tlet sample_\(index) = trace(payload[\(index)], \(longIdentifier)\(index))",
                "\taccumulator += sample_\(index).radiance * half3(0.125, 0.250, 0.500)",
                "}",
            ].joined(separator: "\n")
        }.joined(separator: "\n")
        let markdown = """
        # Source Code Witness

        This witness reproduces the code, quote, paragraph, and heading sequence
        that looked crammed in manual PDF artifacts.

        ```metal
        struct SurfaceWitness {
            half3 baseColor;
            half roughness;
            half metallic;
        };
        \(denseMetalLines)
        let SourceCodeEndToken = "source-code-end"
        ```

        > QuoteStartToken quoted analysis begins after the source block and must
        > not overlap the background rectangle or any glyph from the code block.
        > Quoted analysis ends before normal paragraph flow resumes QuoteEndToken

        AfterQuoteParagraph resumes normal flow after the quote with a visible gap AfterQuoteParagraphEndToken

        ## AfterQuoteHeadingToken

        AfterHeadingParagraph keeps heading flow away from the quote body.

        ```swift
        let wrappedSymbols = "\(String(repeating: "[]{}()<>+-=*/", count: 10))"
        let wrappedIdentifier = "\(longIdentifier)"
        let SecondCodeEndToken = "second-code-end"
        ```

        AfterSecondCodeParagraph resumes below the second code block.
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 360, height: 460),
                margins: PDFOptions.Margins(top: 36, right: 34, bottom: 36, left: 34),
                baseFontSize: 10,
                title: "Source Code Witness",
            ),
        ).render(markdown: markdown)
        try PDFValidation.requireSoundStructure(data, name: "source-code-spacing")
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount

        #expect(pageCount >= 4)
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        try PDFValidation.writeTextArtifact(Self.sourceCodeSpacingManifest, name: "source-code-spacing/README.txt")
        try PDFValidation.writeArtifact(data, name: "source-code-spacing.pdf")

        let verticalRuleLines = inspector.streams.flatMap { stream in
            verticalRuleOperatorLines(in: stream.body)
        }
        #expect(
            verticalRuleLines.isEmpty,
            "Source code witness emitted unexpected vertical rule operators:\n\(verticalRuleLines.joined(separator: "\n"))",
        )

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "source-code-spacing/text.txt")
        let normalizedText = normalizedExtractedText(extractedText)
        #expect(normalizedText.contains("SourceCodeEndToken"))
        #expect(normalizedText.contains("QuoteStartToken"))
        #expect(normalizedText.contains("AfterQuoteHeadingToken"))
        #expect(normalizedText.contains("SecondCodeEndToken"))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "source-code-spacing/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()

        #expect(layout.pages.count == pageCount)
        #expect(layout.words.count > 260)
        #expect(
            layoutIssues.isEmpty,
            "Source code spacing word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )

        let codeEnd = try word("SourceCodeEndToken", in: layout)
        let quoteStart = try word("QuoteStartToken", in: layout)
        let quoteEnd = try word("QuoteEndToken", in: layout)
        let afterParagraph = try word("AfterQuoteParagraph", in: layout)
        let afterParagraphEnd = try word("AfterQuoteParagraphEndToken", in: layout)
        let afterHeading = try word("AfterQuoteHeadingToken", in: layout)
        let secondCodeEnd = try word("SecondCodeEndToken", in: layout)
        let afterSecondCode = try word("AfterSecondCodeParagraph", in: layout)

        expectVerticalGap(after: codeEnd, before: quoteStart, minimum: 10, context: "code block to quote")
        expectVerticalGap(after: quoteEnd, before: afterParagraph, minimum: 4, context: "quote to paragraph")
        expectVerticalGap(after: afterParagraphEnd, before: afterHeading, minimum: 8, context: "paragraph to heading")
        expectVerticalGap(after: secondCodeEnd, before: afterSecondCode, minimum: 8, context: "code block to paragraph")

        #expect(layout.visibleCharacterCount > 1800)
    }

    @Test("Screenshot source-code regression witness covers spacing, strokes, and images")
    func screenshotSourceCodeRegressionWitnessCoversSpacingStrokesAndImages() throws {
        let assetsBaseURL = try TestImageAssets.directoryWithChartPNG()
        let longIdentifier = "ScreenshotRegressionWitnessLongIdentifier"
            + String(repeating: "Segment", count: 12)
        let repeatedRuns = (1 ... 5).map { index in
            """
            ```swift
            struct ScreenshotRegressionSection\(index) {
                let identifier = "\(longIdentifier)\(index)"
                let width = max(columnWidth, measuredGlyphAdvance + \(index))
                let ScreenshotCodeEndToken\(index) = "code-end-\(index)"
            }
            ```

            > ScreenshotQuoteStartToken\(index) quoted source analysis starts after code
            > and must remain clear of the previous code background.
            > > NestedQuoteStartToken\(index) nested quote pressure also stays indented.
            > ScreenshotQuoteEndToken\(index)

            ScreenshotAfterQuoteParagraph\(index) resumes after the quote with readable spacing.

            ### ScreenshotAfterQuoteHeadingToken\(index)

            ScreenshotAfterHeadingParagraph\(index) follows the heading without crowding.
            """
        }.joined(separator: "\n\n")
        let markdown = """
        # Screenshot Source Code Regression Witness

        This witness reproduces the screenshot-reported source-code flow with
        dense code, block quotes, headings, local figures, remote image fallback,
        and hostile reference-style image syntax.

        ```metal
        struct DirectTransition {
            float4 payload;
            float3 measuredNormal;
            let DirectCodeEndToken = "direct-code-end";
        };
        ```

        > DirectQuoteStartToken source comments must start below the code block.
        > DirectNestedQuoteToken nested source notes keep indentation only.
        > DirectQuoteEndToken

        ## DirectAfterQuoteHeadingToken

        DirectAfterHeadingParagraph begins after the quote-to-heading transition.

        \(repeatedRuns)

        ## Local and Remote Image Pressure

        The same local chart is placed twice. The PDF should reuse one image
        resource and draw it twice in normal document flow.

        ![Screenshot local chart first](local-chart.png)

        AfterFirstLocalImageParagraph proves the first image consumed vertical space.

        ![Screenshot local chart second](local-chart.png)

        AfterSecondLocalImageParagraph proves repeated image placement consumes space.

        Remote image fetching is outside the portable profile and must remain
        visible fallback text.

        ![Remote regression figure](https://example.com/source-regression.png)

        AfterRemoteImageParagraph follows the remote fallback text.

        Reference-style image syntax is hostile input for the current parser and
        must stay visible as text instead of disappearing or becoming an image.

        ![Reference style regression chart][screenshot-chart]

        [screenshot-chart]: local-chart.png "Reference style regression fallback text"

        AfterUnsupportedImageSyntaxParagraph ends the manuscript pressure case.
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 360, height: 460),
                margins: PDFOptions.Margins(top: 36, right: 34, bottom: 36, left: 34),
                baseFontSize: 10,
                title: "Screenshot Source Code Regression Witness",
            ),
        ).render(markdown: markdown, assetsBaseURL: assetsBaseURL)
        try PDFValidation.requireSoundStructure(data, name: "screenshot-source-code-regressions")
        let inspector = PDFInspector(data)
        let pageCount = inspector.pageCount
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")

        #expect(pageCount >= 5)
        #expect(inspector.hasValidXrefOffsets())
        #expect(inspector.streamLengthsMatch())
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "Screenshot source-code witness PDF structure issues:\n\(inspector.canonicalStructureIssues().joined(separator: "\n"))",
        )
        #expect(imageXObjectCount(in: inspector.text) == 1)
        #expect(imageDrawOperatorCount(in: streamText) == 2)

        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        try PDFValidation.writeTextArtifact(Self.screenshotSourceCodeRegressionManifest, name: "screenshot-source-code-regressions/README.txt")
        try PDFValidation.writeArtifact(data, name: "screenshot-source-code-regressions.pdf")

        let verticalRuleLines = inspector.streams.flatMap { stream in
            verticalRuleOperatorLines(in: stream.body)
        }
        #expect(
            verticalRuleLines.isEmpty,
            "Screenshot source-code witness emitted unexpected vertical rule operators:\n\(verticalRuleLines.joined(separator: "\n"))",
        )

        let extractedText = try PDFValidation.text(data)
        try PDFValidation.writeTextArtifact(extractedText, name: "screenshot-source-code-regressions/text.txt")
        let normalizedText = normalizedExtractedText(extractedText)
        #expect(normalizedText.contains("DirectCodeEndToken"))
        #expect(normalizedText.contains("DirectQuoteStartToken"))
        #expect(normalizedText.contains("DirectAfterQuoteHeadingToken"))
        #expect(normalizedText.contains("ScreenshotCodeEndToken5"))
        #expect(normalizedText.contains("ScreenshotQuoteStartToken5"))
        #expect(normalizedText.contains("ScreenshotAfterQuoteHeadingToken5"))
        #expect(normalizedText.contains("[Remote image: Remote regression figure]"))
        #expect(normalizedText.contains("Reference style regression chart"))
        #expect(normalizedText.contains("Reference style regression fallback text"))
        #expect(normalizedText.contains("AfterUnsupportedImageSyntaxParagraph"))

        let layout = try ReaderTextLayout(data: data)
        try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "screenshot-source-code-regressions/words.tsv")
        let layoutIssues = layout.visualLayoutIssues()

        #expect(layout.pages.count == pageCount)
        #expect(layout.words.count > 420)
        #expect(
            layoutIssues.isEmpty,
            "Screenshot source-code word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        )

        let directCodeEnd = try word("DirectCodeEndToken", in: layout)
        let directQuoteStart = try word("DirectQuoteStartToken", in: layout)
        let directQuoteEnd = try word("DirectQuoteEndToken", in: layout)
        let directHeading = try word("DirectAfterQuoteHeadingToken", in: layout)
        let firstCodeEnd = try word("ScreenshotCodeEndToken1", in: layout)
        let firstQuoteStart = try word("ScreenshotQuoteStartToken1", in: layout)
        let firstQuoteEnd = try word("ScreenshotQuoteEndToken1", in: layout)
        let firstAfterParagraph = try word("ScreenshotAfterQuoteParagraph1", in: layout)
        let firstHeading = try word("ScreenshotAfterQuoteHeadingToken1", in: layout)
        let lastCodeEnd = try word("ScreenshotCodeEndToken5", in: layout)
        let lastQuoteStart = try word("ScreenshotQuoteStartToken5", in: layout)
        let afterRemoteImage = try word("AfterRemoteImageParagraph", in: layout)
        let afterUnsupportedImage = try word("AfterUnsupportedImageSyntaxParagraph", in: layout)

        expectVerticalGap(after: directCodeEnd, before: directQuoteStart, minimum: 10, context: "direct code block to quote")
        expectVerticalGap(after: directQuoteEnd, before: directHeading, minimum: 8, context: "direct quote to heading")
        expectVerticalGap(after: firstCodeEnd, before: firstQuoteStart, minimum: 10, context: "repeated code block to quote")
        expectVerticalGap(after: firstQuoteEnd, before: firstAfterParagraph, minimum: 4, context: "repeated quote to paragraph")
        expectVerticalGap(after: firstAfterParagraph, before: firstHeading, minimum: 8, context: "repeated paragraph to heading")
        expectVerticalGap(after: lastCodeEnd, before: lastQuoteStart, minimum: 10, context: "last code block to quote")
        expectVerticalGap(after: afterRemoteImage, before: afterUnsupportedImage, minimum: 10, context: "remote fallback to unsupported image text")

        #expect(layout.visibleCharacterCount > 2600)
    }

    @Test("Screenshot source-code regression witness rejects mutated failures")
    func screenshotSourceCodeRegressionWitnessRejectsMutatedFailures() throws {
        let strokeMutation = """
        52 720 m
        52 660 l
        S
        """
        #expect(!verticalRuleOperatorLines(in: strokeMutation).isEmpty)

        let mutatedLayout = ReaderTextLayout(pages: [PDFOptions.PageSize(width: 220, height: 220)], words: [
            Self.box(1, "DirectCodeEndToken", left: 10, top: 90, width: 80),
            Self.box(2, "DirectQuoteStartToken", left: 10, top: 94, width: 120),
            Self.box(3, "OverlapLeft", left: 10, top: 130, width: 60),
            Self.box(4, "OverlapRight", left: 50, top: 130, width: 60),
        ])
        let mutatedCodeEnd = try word("DirectCodeEndToken", in: mutatedLayout)
        let mutatedQuoteStart = try word("DirectQuoteStartToken", in: mutatedLayout)
        // The same failure read from a file: "B" is shown a point before "A" ends.
        let mutatedFile = try ReaderTextLayout(data: HandWrittenPDF.onePage(
            content: "BT /F1 12 Tf 10 80 Td (A) Tj ET\nBT /F1 12 Tf 17 80 Td (B) Tj ET",
        ))

        #expect(mutatedLayout.visualLayoutIssues().contains { $0.contains("'OverlapLeft' overlaps") })
        #expect(mutatedLayout.visualLayoutIssues().contains { $0.contains("'DirectCodeEndToken' collides vertically") })
        #expect(mutatedFile.visualLayoutIssues().contains { $0.contains("overlaps") })
        #expect(
            verticalGapIssue(
                after: mutatedCodeEnd,
                before: mutatedQuoteStart,
                minimum: 10,
                context: "mutated code block to quote",
            ) != nil,
        )
        #expect(imageXObjectCount(in: "") != 1)
        #expect(imageDrawOperatorCount(in: "/Im1 Do") != 2)

        let mutatedText = normalizedExtractedText("DirectCodeEndToken DirectQuoteStartToken")
        #expect(!mutatedText.contains("[Remote image: Remote regression figure]"))
        #expect(!mutatedText.contains("Reference style regression fallback text"))
    }

    @Test("Visual layout validator rejects overlapping words")
    func visualLayoutValidatorRejectsOverlappingWords() {
        let layout = ReaderTextLayout(pages: [PDFOptions.PageSize(width: 200, height: 200)], words: [
            Self.box(1, "First", left: 10, top: 20, width: 40),
            Self.box(2, "Second", left: 49, top: 20, width: 30),
        ])

        #expect(layout.visualLayoutIssues() == ["page 1 word 1 'First' overlaps page 1 word 2 'Second'"])
        // Words that only touch, within the half point tolerance, do not overlap.
        let touching = ReaderTextLayout(pages: layout.pages, words: [
            Self.box(1, "First", left: 10, top: 20, width: 40),
            Self.box(2, "Second", left: 49.6, top: 20, width: 30),
        ])
        #expect(touching.visualLayoutIssues().isEmpty)
    }

    @Test("Visual layout validator checks each word against the size of its own page")
    func visualLayoutValidatorChecksEachWordAgainstItsOwnPage() {
        let pages = [PDFOptions.PageSize(width: 100, height: 100), PDFOptions.PageSize(width: 260, height: 320)]
        let onLargePage = ReaderTextLayout(pages: pages, words: [
            Self.box(1, "Markdown", page: 2, left: 95.28, top: 41.48, width: 40.59, height: 8.14),
            Self.box(2, "source", page: 2, left: 138.31, top: 41.48, width: 26.41, height: 8.14),
        ])
        #expect(onLargePage.visualLayoutIssues().isEmpty)

        let onSmallPage = ReaderTextLayout(pages: pages, words: [
            Self.box(1, "source", page: 1, left: 138.31, top: 41.48, width: 26.41, height: 8.14),
        ])
        #expect(onSmallPage.visualLayoutIssues() == ["page 1 word 1 'source' is outside page bounds"])

        let onNoPage = ReaderTextLayout(pages: pages, words: [Self.box(1, "lost", page: 3, left: 10, top: 10, width: 20)])
        #expect(onNoPage.visualLayoutIssues() == ["page 3 word 1 'lost' references missing page 3"])
    }

    @Test("Visual layout validator allows table columns on the same row")
    func visualLayoutValidatorAllowsTableColumnsOnSameRow() {
        let layout = ReaderTextLayout(pages: [PDFOptions.PageSize(width: 220, height: 220)], words: [
            Self.box(1, "Left", left: 20, top: 60, width: 40),
            Self.box(2, "Right", left: 90, top: 60, width: 50),
        ])

        #expect(layout.visualLayoutIssues().isEmpty)
    }

    @Test("Visual layout validator rejects collisions hidden behind table columns")
    func visualLayoutValidatorRejectsCollisionsHiddenBehindTableColumns() {
        let layout = ReaderTextLayout(pages: [PDFOptions.PageSize(width: 220, height: 220)], words: [
            Self.box(1, "Top", left: 20, top: 60, width: 40, height: 20),
            Self.box(2, "Side", left: 90, top: 65, width: 50),
            Self.box(3, "Bottom", left: 22, top: 70, width: 40),
        ])

        #expect(layout.visualLayoutIssues() == ["page 1 word 1 'Top' collides vertically with page 1 word 3 'Bottom'"])
    }

    @Test("Visual layout validator rejects text a file draws over other text")
    func visualLayoutValidatorRejectsTextDrawnOverText() throws {
        // Helvetica "A" is 667 thousandths: at 12 points it ends at 18.004, and "B" starts at 17.
        let layout = try ReaderTextLayout(data: HandWrittenPDF.onePage(
            content: "BT /F1 12 Tf 10 80 Td (A) Tj ET\nBT /F1 12 Tf 17 80 Td (B) Tj ET",
        ))

        #expect(layout.words.map(\.text) == ["A", "B"])
        #expect(layout.visualLayoutIssues() == ["page 1 word 1 'A' overlaps page 1 word 2 'B'"])
    }

    @Test("Visual layout validator allows a glyph that stands for several characters")
    func visualLayoutValidatorAllowsLigatureGlyphs() throws {
        // Code 1 is one glyph that the ToUnicode map reads as "fi": two characters, one advance.
        let layout = try ReaderTextLayout(data: HandWrittenPDF.onePage(
            content: "BT /F1 12 Tf 10 80 Td <000100020003> Tj ET",
            fontObjects: Self.compositeFontObjects(widths: "1 [600 300 500]"),
        ))

        #expect(layout.words.map(\.text) == ["file"])
        #expect(layout.visibleCharacterCount == 4)
        #expect(abs((layout.words.first?.width ?? 0) - 16.8) < 1e-9)
        #expect(layout.visualLayoutIssues().isEmpty)
    }

    @Test("Visual layout validator rejects a glyph the font gives no width")
    func visualLayoutValidatorRejectsZeroWidthGlyphs() throws {
        let layout = try ReaderTextLayout(data: HandWrittenPDF.onePage(
            content: "BT /F1 12 Tf 15 80 Td <0001> Tj ET",
            fontObjects: Self.compositeFontObjects(widths: "1 [0 300 500]"),
        ))

        #expect(layout.visualLayoutIssues() == ["page 1 word 1 'fi' has non-positive size"])
    }

    /// A composite font written by hand: codes 1, 2 and 3 read as "fi", "l" and "e".
    private static func compositeFontObjects(widths: String) -> [String] {
        [
            "<< /Type /Font /Subtype /Type0 /BaseFont /Ligature /Encoding /Identity-H /DescendantFonts [6 0 R] /ToUnicode 7 0 R >>",
            "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Ligature /DW 500 /W [\(widths)] >>",
            HandWrittenPDF.stream("3 beginbfchar\n<0001> <00660069>\n<0002> <006C>\n<0003> <0065>\nendbfchar"),
        ]
    }

    private static func box(
        _ word: Int,
        _ text: String,
        page: Int = 1,
        left: Double,
        top: Double,
        width: Double,
        height: Double = 10,
    ) -> ReaderTextLayout.Box {
        ReaderTextLayout.Box(page: page, word: word, left: left, top: top, width: width, height: height, text: text)
    }

    @Test("Source code witness rule detector rejects stroked and filled vertical rules")
    func sourceCodeWitnessRuleDetectorRejectsStrokedAndFilledVerticalRules() {
        let stream = """
        q
        54 700 m
        54 620 l
        S
        54 620 1.5 80 re
        f
        Q
        """

        #expect(verticalRuleOperatorLines(in: stream) == ["S", "54 620 1.5 80 re"])
    }

    private func visualValidationPDF() throws -> Data {
        let markdown = """
        # Visual validation

        This fixture checks proportional spacing, **bold spacing**, *italic spacing*,
        `monospaced spacing`, URI text, table cells, list indentation, and diagram
        labels on narrow pages. The point is to give the reader's word boxes enough
        material to collide if the renderer starts placing glyphs badly.

        ## Inline stress

        A narrow paragraph mixes words with very different shapes: WWWWWW, iiiiii,
        minimum, maximum, allocation, fulfillment, and reproducibility. The line
        wrapper must keep each word separated even when punctuation, commas, and
        periods appear at the edge of the available measure.

        The same paragraph family also checks **bold words near normal words**,
        *italic words near normal words*, and `code tokens beside prose`. A later
        regression in font metrics should appear as either overlapping word boxes
        on a line or words that leave the page.

        - First bullet item has enough text to wrap onto a second line while the
          marker remains separate from the body text.
        - Second bullet item includes `code`, **bold emphasis**, and iiiiii WWWWWW
          patterns to stress mixed-font cursor movement.
        - Third bullet item is deliberately ordinary so vertical spacing issues
          show up between adjacent list rows.

        | Column | Description |
        |---|---|
        | Alpha | Several words should remain separated across wrapped cell lines. |
        | Beta | Wide letters like WWWWWW and narrow letters like iiiiii both render. |
        | Gamma | Inline code, bold text, and italic text are checked beside table borders. |
        | Delta | A final row gives the table enough height to reveal cell spacing drift. |

        ## Diagram pipeline

        ```mermaid
        flowchart TD
            Source[Markdown source] -->|parse| Blocks[Block tree]
            Blocks --> Layout[PDF layout]
            Layout --> Bytes[PDF bytes]
        ```

        After the first diagram, prose resumes immediately. This catches cases
        where a diagram consumes the wrong amount of vertical space and lets the
        next paragraph collide with the diagram background or node labels.

        ## Dense article section

        The dense section repeats realistic article prose instead of isolated
        tokens. Rendering should remain stable while headings, paragraphs, tables,
        lists, and diagrams cross page boundaries. The sentences use plain ASCII
        because the public package currently targets PDF base fonts by default.

        A second paragraph adds link-shaped text without depending on network
        access: https://example.com/articles/portable-layout. The text should
        remain extractable as words and should not compress into neighboring runs.

        | Phase | Check | Expected signal |
        |---|---|---|
        | Parse | Headings, lists, tables, and Mermaid fences | Extractable labels |
        | Layout | Page breaks and table rows | Non-overlapping boxes |
        | Serialize | Streams, resources, and xref entries | Valid PDF bytes |
        | Inspect | Structure, text, and word box witnesses | Actionable failures |

        More prose follows the second table so the document spans more than a
        token amount of content. The renderer should keep line spacing consistent
        after tables, before diagrams, and across new pages. If line height is too
        small, independent text extraction will flag collisions.

        ```mermaid
        graph LR
            Author[Author input] --> Parser[Swift parser]
            Parser --> Renderer[PDF renderer]
            Renderer --> Tools[Open tools]
        ```

        ## UltraPortableDeterministicHeadingAnchorWithoutSpaces

        This heading deliberately has one long token so the generated table of
        contents has to wrap it before the page number column.

        ## Closing checks

        The final section is intentionally not empty. It validates that the last
        page still has enough ink for raster comparison and that tail content is
        not clipped. Several short sentences follow. First, text extraction must
        include the closing words. Second, word boxes must move monotonically in
        each visible line. Third, every word must stay inside the page it is
        drawn on, with a width and a height.

        A compact summary ends the fixture with known labels: Markdown source,
        Block tree, PDF layout, PDF bytes, Author input, Swift parser, PDF renderer,
        and Open tools.
        """

        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                tableOfContents: .enabled,
            ),
        ).render(markdown: markdown)
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        try PDFValidation.writeArtifact(data, name: "visual-layout-stress.pdf")
        return data
    }

    private func articleStressFixturePDF() throws -> Data {
        let assetsBaseURL = try TestImageAssets.directoryWithChartPNG()
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                title: "Portable Article Stress Corpus",
                tableOfContents: .enabled,
            ),
        ).render(
            markdown: fixture(named: "article-grade-stress.md"),
            assetsBaseURL: assetsBaseURL,
        )
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        return data
    }

    private func hardMarkdownFixturePDF() throws -> Data {
        let assetsBaseURL = try TestImageAssets.directoryWithChartPNG()
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                title: "Portable Hard Markdown Corpus",
                tableOfContents: .enabled,
            ),
        ).render(
            markdown: fixture(named: "hard-markdown-corpus.md"),
            assetsBaseURL: assetsBaseURL,
        )
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        return data
    }

    private func crazyMarkdownFixturePDF() throws -> Data {
        let assetsBaseURL = try TestImageAssets.directoryWithChartPNG()
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                title: "Crazy Markdown Torture Manuscript",
                tableOfContents: .enabled,
            ),
        ).render(
            markdown: fixture(named: "crazy-markdown-torture.md"),
            assetsBaseURL: assetsBaseURL,
        )
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        return data
    }

    private func syntaxColoringManuscriptPDF() throws -> Data {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                title: "Portable Syntax Coloring Manuscript",
                codeSyntaxHighlighting: .enabled,
            ),
        ).render(markdown: fixture(named: "syntax-coloring-manuscript.md"))
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        return data
    }

    private func rtlManuscriptPDF() throws -> Data {
        let hebrewWord = "\u{05D0}\u{05D1}\u{05D2}\u{05D3}"
        let hebrewPair = "\u{05D0}\u{05D1}"
        let arabicWord = "\u{0633}\u{0644}\u{0627}\u{0645}"
        let arabicIndic12 = "\u{0661}\u{0662}"
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .rtlWitness, includeGlyphOutlines: true)
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "MarkdownPDF RTL Witness")
        let repeatedParagraphs = ["A", "B", "C", "D", "E", "F", "G", "H"].map { suffix in
            "\(hebrewWord) (123) CODE \(arabicWord) \(arabicIndic12) RTLPARATOKEN\(suffix)."
        }.joined(separator: "\n\n")
        let markdown = """
        # \(hebrewWord) RTL MANUSCRIPT

        ## \(arabicWord) CODE 123 \(hebrewWord)

        \(repeatedParagraphs)

        - \(arabicWord) [CODE] \(hebrewWord) ULISTTOKENA.
        - \(hebrewWord) {CODE} \(arabicWord) ULISTTOKENB.

        1. \(hebrewWord) "CODE" \(arabicWord) OLISTTOKENA.
        2. \(arabicWord) <CODE> \(hebrewPair) OLISTTOKENB.

        > \(arabicWord) (123) \(hebrewWord) QUOTETOKENA.
        > \(hebrewWord) '\(arabicWord)' QUOTETOKENB.

        | \(hebrewWord) HEADER | \(arabicWord) HEADER |
        |---|---|
        | \(hebrewWord) (123) CODE | \(arabicWord) \(arabicIndic12) ROWA |
        | \(arabicWord) [CODE] | \(hebrewWord) 123 ROWB |
        | \(hebrewPair) {CODE} | \(arabicWord) 123 ROWC |

        \(arabicWord) (123) \(hebrewWord) RTLMIRRORTOKEN.
        """

        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 300, height: 360),
                margins: PDFOptions.Margins(top: 28, right: 28, bottom: 28, left: 28),
                baseFontSize: 10,
                embeddedFonts: .allRoles(source),
                title: "RTL Manuscript Witness",
            ),
        ).render(markdown: markdown)
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        return data
    }

    private func a4ManuscriptFixturePDF() throws -> Data {
        let assetsBaseURL = try TestImageAssets.directoryWithChartPNG()
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: .a4,
                margins: PDFOptions.Margins(top: 56, right: 54, bottom: 56, left: 54),
                baseFontSize: 11,
                title: "Portable A4 Manuscript Fixture",
                tableOfContents: .enabled,
            ),
        ).render(
            markdown: fixture(named: "a4-manuscript.md"),
            assetsBaseURL: assetsBaseURL,
        )
        try PDFValidation.writeTextArtifact(Self.artifactManifest, name: "README.txt")
        return data
    }

    private func embeddedCIDTextPDF() throws -> Data {
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let metadata = try TrueTypeFontParser().parse(fontData)
        let mapper = TrueTypeGlyphMapper(
            data: fontData,
            metadata: metadata,
            missingGlyphPolicy: .useNotdef,
        )
        let resource = PDFEmbeddedFontResource(
            resourceName: "EF1",
            fontProgram: fontData,
            metadata: metadata,
        )
        let canvas = PDFPageCanvas()
        let lines = [
            "WIDE WILLIAM MINIMUM MARGIN",
            "NARROW INK MEETS WIDE WORDS",
            "LATIN CID TEXT STAYS ALIGNED",
            "WIDE LETTERS AND THIN INK",
        ]

        for (index, line) in lines.enumerated() {
            try canvas.drawCIDText(
                mapping: mapper.map(text: line, fontSize: 18),
                fontResource: resource,
                fontSize: 18,
                x: 42,
                y: 300 - Double(index) * 30,
            )
        }

        return try PDFDocumentWriter(
            pageSize: PDFOptions.PageSize(width: 440, height: 360),
            fontSet: .pdfBase,
            pages: [canvas],
            images: [],
            title: "Embedded CID Text Witness",
        ).data()
    }

    private func embeddedFontPublicAPIPDF() throws -> Data {
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "MarkdownPDF Public Fixture")
        let denseParagraphs = Array(
            repeating: "WIDE WILLIAM MINIMUM MARGIN ALPHA BETA GAMMA DELTA VECTOR SPACE CID TEXT STAYS ALIGNED",
            count: 18,
        ).joined(separator: "\n\n")
        let markdown = """
        # PUBLIC EMBEDDED FONT PROFILE

        \(denseParagraphs)

        ## STYLE ROLES

        PLAIN ROLE **BOLD ROLE** *ITALIC ROLE* `CODE ROLE`

        [OPEN FONT](https://example.com/fonts) LINK TEXT STAYS ALIGNED

        | AREA | VALUE |
        |---|---|
        | WIDTH | WIDE WILLIAM MINIMUM MARGIN |
        | CID | TEXT STAYS ALIGNED |
        | RASTER | WITNESS STACK |

        ```text
        CODE ROLE WIDE WILLIAM
        MONO SPACE TEST
        ```

        ```mermaid
        flowchart TD
        A[PUBLIC FONT] --> B[CID TEXT]
        B --> C[RASTER WITNESS]
        ```
        """

        return try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                embeddedFonts: .allRoles(source),
                title: "Embedded Font Public API Witness",
            ),
        ).render(markdown: markdown)
    }

    private func cjkDiacriticsManuscriptPDF() throws -> Data {
        let fontData = SyntheticTrueTypeFont.data(
            cmapFormat: 12,
            glyphProfile: .cjkDiacriticWitness,
            includeGlyphOutlines: true,
        )
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "MarkdownPDF CJK Diacritic Fixture")

        return try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                embeddedFonts: .allRoles(source),
                title: "CJK Diacritics Manuscript Witness",
            ),
        ).render(markdown: fixture(named: "cjk-diacritics-manuscript.md"))
    }

    private func fixture(named name: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }

    private func word(_ text: String, in layout: ReaderTextLayout) throws -> ReaderTextLayout.Box {
        try #require(layout.words.first { $0.text == text }, "Missing extracted word \(text)")
    }

    private func expectVerticalGap(
        after upper: ReaderTextLayout.Box,
        before lower: ReaderTextLayout.Box,
        minimum: Double,
        context: String,
    ) {
        let issue = verticalGapIssue(after: upper, before: lower, minimum: minimum, context: context)
        #expect(issue == nil, "\(issue ?? "")")
    }

    private func verticalGapIssue(
        after upper: ReaderTextLayout.Box,
        before lower: ReaderTextLayout.Box,
        minimum: Double,
        context: String,
    ) -> String? {
        if lower.page == upper.page {
            return lower.top > upper.bottom + minimum
                ? nil
                : "\(context) gap was too small: \(lower.top - upper.bottom)"
        }

        return lower.page > upper.page ? nil : "\(context) moved backward across pages"
    }

    private func imageXObjectCount(in pdfText: String) -> Int {
        pdfText.components(separatedBy: "/Subtype /Image").count - 1
    }

    private func imageDrawOperatorCount(in streamText: String) -> Int {
        streamText.components(separatedBy: " Do").count - 1
    }

    private func verticalRuleOperatorLines(in stream: String) -> [String] {
        let lines = stream
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var matches: [String] = []
        var pendingMove: (x: Double, y: Double)?
        var pendingLine: (x1: Double, y1: Double, x2: Double, y2: Double)?

        for line in lines {
            if isSkinnyVerticalRectangleOperator(line) {
                matches.append(line)
                continue
            }

            if isInlineSkinnyVerticalPathStroke(line) {
                matches.append(line)
                continue
            }

            if let move = moveOperatorPoint(line) {
                pendingMove = move
                pendingLine = nil
                continue
            }

            if let linePoint = lineOperatorPoint(line),
               let move = pendingMove
            {
                pendingLine = (move.x, move.y, linePoint.x, linePoint.y)
                continue
            }

            if isStrokeOperator(line) {
                if let pendingLine, isSkinnyVerticalPath(pendingLine) {
                    matches.append(line)
                }
                pendingMove = nil
                pendingLine = nil
                continue
            }

            pendingMove = nil
            pendingLine = nil
        }

        return matches
    }

    private func isSkinnyVerticalRectangleOperator(_ line: String) -> Bool {
        let parts = line.split(separator: " ")
        guard parts.count >= 5,
              parts.last == "re",
              let width = Double(parts[parts.count - 3]),
              let height = Double(parts[parts.count - 2])
        else {
            return false
        }

        return abs(width) <= 3 && abs(height) >= 16
    }

    private func isInlineSkinnyVerticalPathStroke(_ line: String) -> Bool {
        let parts = line.split(separator: " ").map(String.init)
        guard let moveIndex = parts.firstIndex(of: "m"),
              let lineIndex = parts.firstIndex(of: "l"),
              parts.suffix(2).contains(where: { $0 == "S" || $0 == "s" }),
              moveIndex >= 2,
              lineIndex >= moveIndex + 3,
              let x1 = Double(parts[moveIndex - 2]),
              let y1 = Double(parts[moveIndex - 1]),
              let x2 = Double(parts[lineIndex - 2]),
              let y2 = Double(parts[lineIndex - 1])
        else {
            return false
        }

        return isSkinnyVerticalPath((x1, y1, x2, y2))
    }

    private func moveOperatorPoint(_ line: String) -> (x: Double, y: Double)? {
        let parts = line.split(separator: " ")
        guard parts.count == 3,
              parts[2] == "m",
              let x = Double(parts[0]),
              let y = Double(parts[1])
        else {
            return nil
        }

        return (x, y)
    }

    private func lineOperatorPoint(_ line: String) -> (x: Double, y: Double)? {
        let parts = line.split(separator: " ")
        guard parts.count == 3,
              parts[2] == "l",
              let x = Double(parts[0]),
              let y = Double(parts[1])
        else {
            return nil
        }

        return (x, y)
    }

    private func isStrokeOperator(_ line: String) -> Bool {
        line == "S" || line == "s"
    }

    private func isSkinnyVerticalPath(_ path: (x1: Double, y1: Double, x2: Double, y2: Double)) -> Bool {
        let width = abs(path.x2 - path.x1)
        let height = abs(path.y2 - path.y1)
        return width <= 3 && height >= 16
    }

    private static let artifactManifest = """
    MarkdownPDF PDF witness artifacts

    Every artifact is written by the test target from what the package's own
    reader, PDFDocumentReader, finds in the rendered file. No outside program
    takes part.

    <name>.pdf
    The rendered PDF of a witness test, such as a4-manuscript.pdf or rtl-manuscript.pdf.

    <name>/text.txt
    The text of the document as the reader extracts it, in the order of the
    content stream, pages separated by a form feed.

    <name>/words.tsv
    One line for each word: the page, the position of the word among the words of
    its page, then left, top, width and height in points from the top left corner
    of the page, and the text. The boxes come from the position of each text
    operator and the widths the fonts declare in the file.

    <name>/README.txt
    For the witnesses that have one: the tokens the test requires and what it expects.

    visual-layout/document.txt
    The page count, PDF version, title and page sizes of the visual layout fixture.

    Page rasters are not written. Whether a rasterizer paints comparable ink on
    every page is not verified until MarkdownPDF has a rasterizer of its own:
    see Docs/NOT-VERIFIED.md.
    """

    private static let sourceCodeSpacingManifest = """
    Source code spacing witness

    Expected image references: 0.
    Expected portable block quote strokes: 0.

    Required extracted tokens:
    - SourceCodeEndToken
    - QuoteStartToken
    - QuoteEndToken
    - AfterQuoteParagraph
    - AfterQuoteParagraphEndToken
    - AfterQuoteHeadingToken
    - SecondCodeEndToken
    - AfterSecondCodeParagraph

    Required artifacts:
    - source-code-spacing.pdf
    - source-code-spacing/text.txt
    - source-code-spacing/words.tsv
    """

    private static let screenshotSourceCodeRegressionManifest = """
    Screenshot source-code regression witness

    Expected image XObjects: 1.
    Expected image draw operators: 2.
    Expected remote image fallback text: [Remote image: Remote regression figure].
    Expected unsupported reference-style image behavior: visible text, no image XObject.
    Expected portable block quote strokes: 0.

    Required extracted tokens:
    - DirectCodeEndToken
    - DirectQuoteStartToken
    - DirectQuoteEndToken
    - DirectAfterQuoteHeadingToken
    - ScreenshotCodeEndToken1
    - ScreenshotQuoteStartToken1
    - ScreenshotQuoteEndToken1
    - ScreenshotAfterQuoteParagraph1
    - ScreenshotAfterQuoteHeadingToken1
    - ScreenshotCodeEndToken5
    - ScreenshotQuoteStartToken5
    - AfterRemoteImageParagraph
    - Reference style regression chart
    - Reference style regression fallback text
    - AfterUnsupportedImageSyntaxParagraph

    Required artifacts:
    - screenshot-source-code-regressions.pdf
    - screenshot-source-code-regressions/text.txt
    - screenshot-source-code-regressions/words.tsv
    """

    private static let rtlManuscriptManifest = """
    RTL manuscript witness

    Expected embedded font resources: Type0, CIDFontType2, FontFile2, ToUnicode.
    Expected extraction policy: content is emitted in logical source order with ToUnicode mappings while glyphs are positioned in visual order.
    Expected visual policy: RTL visual runs are reordered and paired punctuation is mirrored before drawing.

    Required extracted tokens:
    - RTLPARATOKENA
    - ULISTTOKENA
    - OLISTTOKENA
    - QUOTETOKENA
    - HEADER
    - ROWA
    - RTLMIRRORTOKEN

    Required artifacts:
    - rtl-manuscript.pdf
    - rtl-manuscript/text.txt
    - rtl-manuscript/words.tsv
    """

    private func tableRectangleWidths(in inspector: PDFInspector) -> [Double] {
        inspector.streams
            .flatMap { stream in
                stream.body
                    .split(separator: "\n")
                    .compactMap { line -> Double? in
                        let parts = line.split(separator: " ")
                        guard let rectangleIndex = parts.firstIndex(of: "re"),
                              rectangleIndex >= 2
                        else {
                            return nil
                        }
                        return Double(parts[rectangleIndex - 2])
                    }
            }
    }

    private func normalizedExtractedText(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func compactLogicalExtractedText(_ text: String) -> String {
        text.unicodeScalars
            .filter { scalar in
                !CharacterSet.whitespacesAndNewlines.contains(scalar)
                    && !isBidiFormattingScalar(scalar)
            }
            .map(String.init)
            .joined()
    }

    private func isBidiFormattingScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x061C,
             0x200E ... 0x200F,
             0x202A ... 0x202E,
             0x2066 ... 0x2069:
            true
        default:
            false
        }
    }

    private static func pdfHex(_ value: Int) -> String {
        String(format: "<%04X>", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
