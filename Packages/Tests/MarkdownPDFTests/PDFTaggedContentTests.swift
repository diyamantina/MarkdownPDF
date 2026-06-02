import Foundation
@testable import MarkdownPDF
import Testing

@Suite("PDF tagged content")
struct PDFTaggedContentTests {
    @Test("Serializes marked content and artifact operators")
    func serializesMarkedContentAndArtifactOperators() {
        var stream = PDFContentStream()

        stream.append(.beginMarkedContent(PDFSyntax.Name("P"), mcid: 3))
        stream.append([
            .beginText,
            .setFont(PDFSyntax.Name("F1"), size: 12),
            .moveText(x: 20, y: 30),
            .showText(PDFSyntax.LiteralString("Tagged")),
            .endText,
        ])
        stream.append(.endMarkedContent)
        stream.append(.beginArtifact)
        stream.append([
            .moveTo(x: 10, y: 10),
            .lineTo(x: 40, y: 10),
            .stroke,
        ])
        stream.append(.endMarkedContent)

        #expect(
            stream.serialized
                == """
                /P << /MCID 3 >> BDC
                BT /F1 12 Tf 20 30 Td (Tagged) Tj ET
                EMC
                /Artifact BMC
                10 10 m 40 10 l S
                EMC

                """,
        )
    }

    @Test("Serializes tagged catalog and page hooks")
    func serializesTaggedCatalogAndPageHooks() {
        let catalog = PDFDocumentCatalog(
            pages: PDFSyntax.Reference(objectNumber: 2),
            structTreeRoot: PDFSyntax.Reference(objectNumber: 8),
            language: "hr-HR",
            marked: true,
            displayDocumentTitle: true,
        )
        let page = PDFPageDictionary(
            parent: PDFSyntax.Reference(objectNumber: 2),
            mediaBox: PDFOptions.PageSize(width: 300, height: 400),
            resources: PDFSyntax.Dictionary(),
            contents: PDFSyntax.Reference(objectNumber: 4),
            annotations: [],
            structParents: 7,
        )

        #expect(
            catalog.pdfDictionary.serialized()
                == "<< /Type /Catalog /Pages 2 0 R /MarkInfo << /Marked true >> /StructTreeRoot 8 0 R /Lang (hr-HR) /ViewerPreferences << /DisplayDocTitle true >> >>",
        )
        #expect(page.pdfDictionary.serialized(style: .multiline).contains("/StructParents 7"))
    }

    @Test("Renderer writes a tagged structure spine when enabled")
    func rendererWritesTaggedStructureSpineWhenEnabled() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 300, height: 260),
                margins: PDFOptions.Margins(top: 24, right: 24, bottom: 24, left: 24),
                title: "Tagged Fixture",
                taggedPDF: .enabled,
            ),
        ).render(markdown: """
        # Tagged title

        A paragraph with **strong** text.
        """)
        let inspector = PDFInspector(data)
        let streamBodies = inspector.streams.map(\.body).joined(separator: "\n")

        #expect(inspector.canonicalStructureIssues().isEmpty)
        #expect(inspector.text.contains("/MarkInfo << /Marked true >>"))
        #expect(inspector.text.contains("/Lang (en-US)"))
        #expect(inspector.text.contains("/StructTreeRoot"))
        #expect(inspector.text.contains("/ParentTreeNextKey 1"))
        #expect(inspector.text.contains("/StructParents 0"))
        #expect(inspector.text.contains("/S /Document"))
        #expect(inspector.text.contains("/S /H1"))
        #expect(inspector.text.contains("/S /P"))
        #expect(inspector.text.contains("/Nums [0 ["))
        #expect(streamBodies.contains("/H1 << /MCID 0 >> BDC"))
        #expect(streamBodies.contains("/P << /MCID 1 >> BDC"))

        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "tagged-spine-qpdf")
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        let extractedText = try PDFValidation.pdftotext(data: data, name: "tagged-spine-text")
        try #require(extractedText.exitCode == 0, "pdftotext failed:\n\(extractedText.output)")
        #expect(extractedText.output.contains("Tagged title"))
        #expect(extractedText.output.contains("A paragraph with strong text."))
    }

    @Test("Renderer writes a PDF/UA-1 profile when requested")
    func rendererWritesPDFUA1ProfileWhenRequested() throws {
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "PDF UA Fixture")
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 300, height: 260),
                margins: PDFOptions.Margins(top: 24, right: 24, bottom: 24, left: 24),
                embeddedFonts: .allRoles(source),
                title: "PDF UA Fixture",
                conformance: .pdfUA1,
            ),
        ).render(markdown: """
        # WIDE

        WIDE WILLIAM
        """)
        let inspector = PDFInspector(data)
        let xmp = inspector.streams.map(\.body).joined(separator: "\n")

        try PDFValidation.writeArtifact(data, name: "pdfua-profile.pdf")
        #expect(inspector.canonicalStructureIssues().isEmpty)
        #expect(inspector.text.contains("/MarkInfo << /Marked true >>"))
        #expect(inspector.text.contains("/StructTreeRoot"))
        #expect(inspector.text.contains("/Lang (en-US)"))
        #expect(inspector.text.contains("/ViewerPreferences << /DisplayDocTitle true >>"))
        #expect(xmp.contains("xmlns:pdfuaid=\"http://www.aiim.org/pdfua/ns/id/\""))
        #expect(xmp.contains("<pdfuaid:part>1</pdfuaid:part>"))

        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "pdfua-profile-qpdf")
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        let veraPDF = try PDFValidation.veraPDF(data: data, name: "pdfua-profile-verapdf", flavour: "ua1")
        try #require(veraPDF.exitCode == 0, "veraPDF PDF/UA-1 failed:\n\(veraPDF.output)")
        #expect(veraPDF.output.contains("\"compliant\" : true"))
    }

    @Test("Renderer writes a PDF/A-2a profile when requested")
    func rendererWritesPDFA2AProfileWhenRequested() throws {
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "PDF A Fixture")
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 300, height: 260),
                margins: PDFOptions.Margins(top: 24, right: 24, bottom: 24, left: 24),
                embeddedFonts: .allRoles(source),
                title: "PDF A Fixture",
                conformance: .pdfUA1AndPDFA2A,
            ),
        ).render(markdown: """
        # WIDE

        WIDE WILLIAM
        """)
        let inspector = PDFInspector(data)
        let xmp = inspector.streams.map(\.body).joined(separator: "\n")

        try PDFValidation.writeArtifact(data, name: "pdfa-profile.pdf")
        #expect(inspector.canonicalStructureIssues().isEmpty)
        #expect(inspector.text.contains("/OutputIntents [<< /Type /OutputIntent /S /GTS_PDFA1"))
        #expect(inspector.text.contains("/DestOutputProfile"))
        #expect(inspector.text.contains("/N 3 /Alternate /DeviceRGB"))
        #expect(inspector.text.contains("/ID [<4D61726B646F776E5044462D50444641> <4D61726B646F776E5044462D50444641>]"))
        #expect(xmp.contains("xmlns:pdfaid=\"http://www.aiim.org/pdfa/ns/id/\""))
        #expect(xmp.contains("<pdfaid:part>2</pdfaid:part>"))
        #expect(xmp.contains("<pdfaid:conformance>A</pdfaid:conformance>"))

        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "pdfa-profile-qpdf")
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        let veraPDFA = try PDFValidation.veraPDF(data: data, name: "pdfa-profile-verapdf", flavour: "2a")
        try #require(veraPDFA.exitCode == 0, "veraPDF PDF/A-2a failed:\n\(veraPDFA.output)")
        #expect(veraPDFA.output.contains("\"compliant\" : true"))
        let veraPDFUA = try PDFValidation.veraPDF(data: data, name: "pdfa-profile-ua-verapdf", flavour: "ua1")
        try #require(veraPDFUA.exitCode == 0, "veraPDF PDF/UA-1 failed:\n\(veraPDFUA.output)")
        #expect(veraPDFUA.output.contains("\"compliant\" : true"))
    }

    @Test("Tagged RTL profile preserves logical reading order")
    func taggedRTLProfilePreservesLogicalReadingOrder() throws {
        let hebrewWord = "\u{05D0}\u{05D1}\u{05D2}\u{05D3}"
        let arabicWord = "\u{0633}\u{0644}\u{0627}\u{0645}"
        let arabicIndic12 = "\u{0661}\u{0662}"
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .rtlWitness, includeGlyphOutlines: true)
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "Tagged RTL Fixture")
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 320, height: 260),
                margins: PDFOptions.Margins(top: 24, right: 24, bottom: 24, left: 24),
                embeddedFonts: .allRoles(source),
                title: "Tagged RTL Logical Order",
                conformance: .pdfUA1,
            ),
        ).render(markdown: """
        # \(hebrewWord) RTL

        \(hebrewWord) (123) CODE \(arabicWord) \(arabicIndic12) RTLPARATOKENA.

        > \(arabicWord) (123) \(hebrewWord) QUOTETOKENA.
        """)
        let inspector = PDFInspector(data)
        let streamBodies = inspector.streams.map(\.body).joined(separator: "\n")

        try PDFValidation.writeArtifact(data, name: "tagged-rtl-logical-order.pdf")
        #expect(inspector.canonicalStructureIssues().isEmpty)
        #expect(inspector.text.contains("/MarkInfo << /Marked true >>"))
        #expect(inspector.text.contains("/StructTreeRoot"))
        #expect(inspector.text.contains("/S /BlockQuote"))
        #expect(streamBodies.contains("/H1 << /MCID 0 >> BDC"))
        #expect(streamBodies.contains("/P << /MCID 1 >> BDC"))
        #expect(streamBodies.contains("/P << /MCID 2 >> BDC"))

        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "tagged-rtl-logical-order-qpdf")
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        let veraPDF = try PDFValidation.veraPDF(data: data, name: "tagged-rtl-logical-order-verapdf", flavour: "ua1")
        try #require(veraPDF.exitCode == 0, "veraPDF PDF/UA-1 failed:\n\(veraPDF.output)")
        #expect(veraPDF.output.contains("\"compliant\" : true"))
        let extractedText = try PDFValidation.pdftotextRaw(url: PDFValidation.temporaryPDF(
            name: "tagged-rtl-logical-order-text",
            data: data,
        ))
        try #require(extractedText.exitCode == 0, "pdftotext -raw failed:\n\(extractedText.output)")
        try PDFValidation.writeTextArtifact(extractedText.output, name: "tagged-rtl-logical-order/raw-text.txt")
        let compactText = compactLogicalExtractedText(extractedText.output)

        #expect(compactText.contains("\(hebrewWord)(123)CODE\(arabicWord)\(arabicIndic12)RTLPARATOKENA."))
        #expect(compactText.contains("\(arabicWord)(123)\(hebrewWord)QUOTETOKENA."))
    }

    @Test("Tagged CJK profile preserves logical reading order")
    func taggedCJKProfilePreservesLogicalReadingOrder() throws {
        let fontData = SyntheticTrueTypeFont.data(
            cmapFormat: 12,
            glyphProfile: .cjkDiacriticWitness,
            includeGlyphOutlines: true,
        )
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "Tagged CJK Fixture")
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 280, height: 260),
                margins: PDFOptions.Margins(top: 24, right: 24, bottom: 24, left: 24),
                baseFontSize: 10,
                embeddedFonts: .allRoles(source),
                title: "Tagged CJK Logical Order",
                conformance: .pdfUA1AndPDFA2A,
            ),
        ).render(markdown: """
        # 漢字語

        漢字語 仮名。 Latin x 12.

        漢\u{0301}字語 仮名 漢字語。
        """)
        let inspector = PDFInspector(data)
        let streamBodies = inspector.streams.map(\.body).joined(separator: "\n")

        try PDFValidation.writeArtifact(data, name: "tagged-cjk-logical-order.pdf")
        #expect(inspector.canonicalStructureIssues().isEmpty)
        #expect(inspector.text.contains("/MarkInfo << /Marked true >>"))
        #expect(inspector.text.contains("/StructTreeRoot"))
        #expect(inspector.text.contains("/OutputIntents [<< /Type /OutputIntent /S /GTS_PDFA1"))
        #expect(streamBodies.contains("/H1 << /MCID 0 >> BDC"))
        #expect(streamBodies.contains("/P << /MCID 1 >> BDC"))
        #expect(streamBodies.contains("/P << /MCID 2 >> BDC"))

        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "tagged-cjk-logical-order-qpdf")
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        let veraPDFA = try PDFValidation.veraPDF(data: data, name: "tagged-cjk-logical-order-pdfa", flavour: "2a")
        try #require(veraPDFA.exitCode == 0, "veraPDF PDF/A-2a failed:\n\(veraPDFA.output)")
        #expect(veraPDFA.output.contains("\"compliant\" : true"))
        let veraPDFUA = try PDFValidation.veraPDF(data: data, name: "tagged-cjk-logical-order-pdfua", flavour: "ua1")
        try #require(veraPDFUA.exitCode == 0, "veraPDF PDF/UA-1 failed:\n\(veraPDFUA.output)")
        #expect(veraPDFUA.output.contains("\"compliant\" : true"))
        let extractedText = try PDFValidation.pdftotext(data: data, name: "tagged-cjk-logical-order-text")
        try #require(extractedText.exitCode == 0, "pdftotext failed:\n\(extractedText.output)")
        try PDFValidation.writeTextArtifact(extractedText.output, name: "tagged-cjk-logical-order/text.txt")
        let compactText = extractedText.output.filter { !$0.isWhitespace }

        #expect(compactText.contains("漢字語仮名。Latinx12."))
        #expect(compactText.contains("漢\u{0301}字語仮名漢字語。"))
    }

    @Test("PDF/UA-1 profile requires a document title")
    func pdfUA1ProfileRequiresDocumentTitle() throws {
        let renderer = MarkdownPDFRenderer(options: PDFOptions(conformance: .pdfUA1))

        #expect(throws: MarkdownPDFError.missingConformanceTitle(profile: "PDF/UA-1")) {
            try renderer.render(markdown: "# Missing title")
        }
    }

    @Test("PDF/UA-1 profile rejects base font fallback")
    func pdfUA1ProfileRejectsBaseFontFallback() throws {
        let renderer = MarkdownPDFRenderer(options: PDFOptions(title: "Missing Fonts", conformance: .pdfUA1))

        #expect(
            throws: MarkdownPDFError.unembeddedBaseFontsForConformance(profile: "PDF/UA-1", fonts: ["Helvetica"]),
        ) {
            try renderer.render(markdown: "Plain text")
        }
    }

    @Test("PDF/A-2a profile requires a document title")
    func pdfA2AProfileRequiresDocumentTitle() throws {
        let renderer = MarkdownPDFRenderer(options: PDFOptions(conformance: .pdfA2A))

        #expect(throws: MarkdownPDFError.missingConformanceTitle(profile: "PDF/A-2a")) {
            try renderer.render(markdown: "# Missing title")
        }
    }

    @Test("PDF/A-2a profile rejects base font fallback")
    func pdfA2AProfileRejectsBaseFontFallback() throws {
        let renderer = MarkdownPDFRenderer(options: PDFOptions(title: "Missing Fonts", conformance: .pdfA2A))

        #expect(
            throws: MarkdownPDFError.unembeddedBaseFontsForConformance(profile: "PDF/A-2a", fonts: ["Helvetica"]),
        ) {
            try renderer.render(markdown: "Plain text")
        }
    }

    @Test("Renderer tags lists tables figures and artifacts")
    func rendererTagsListsTablesFiguresAndArtifacts() throws {
        let directory = try TestImageAssets.directoryWithChartPNG(named: "chart.png")
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 340, height: 420),
                margins: PDFOptions.Margins(top: 28, right: 28, bottom: 28, left: 28),
                title: "Tagged Roles",
                taggedPDF: .enabled,
            ),
        ).render(markdown: """
        # Roles

        1. First item
        2. Second item

        | Term | Value |
        |---|---:|
        | Alpha | 1 |

        ![Chart pixels](chart.png)

        ---
        """, assetsBaseURL: directory)
        let inspector = PDFInspector(data)
        let streamBodies = inspector.streams.map(\.body).joined(separator: "\n")

        #expect(inspector.canonicalStructureIssues().isEmpty)
        #expect(inspector.text.contains("/S /L"))
        #expect(inspector.text.contains("/ListNumbering /Decimal"))
        #expect(inspector.text.contains("/S /LI"))
        #expect(inspector.text.contains("/S /Lbl"))
        #expect(inspector.text.contains("/S /LBody"))
        #expect(inspector.text.contains("/S /Table"))
        #expect(inspector.text.contains("/S /TR"))
        #expect(inspector.text.contains("/S /TH"))
        #expect(inspector.text.contains("/Scope /Column"))
        #expect(inspector.text.contains("/S /TD"))
        #expect(inspector.text.contains("/S /Figure"))
        #expect(inspector.text.contains("/Alt (Chart pixels)"))
        #expect(streamBodies.contains("/Artifact BMC"))

        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "tagged-roles-qpdf")
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
    }

    @Test("Renderer keeps tagged output disabled by default")
    func rendererKeepsTaggedOutputDisabledByDefault() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Plain output")
        let inspector = PDFInspector(data)

        #expect(!inspector.text.contains("/MarkInfo"))
        #expect(!inspector.text.contains("/StructTreeRoot"))
        #expect(!inspector.text.contains("/StructParents"))
        #expect(!inspector.streams.map(\.body).joined(separator: "\n").contains(" BDC"))
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
}
