import Dispatch
import Foundation
@testable import MarkdownPDF
import MarkdownPDFLinux
import Testing

#if canImport(MarkdownPDFMac)
    import MarkdownPDFMac
#endif

@Suite("PDF renderer")
struct MarkdownPDFRendererTests {
    @Test("Renders a compact PDF with base fonts and no embedded fonts")
    func rendersPDF() throws {
        let markdown = """
        # Jane Doe

        Swift engineer.

        | Skill | Level |
        |---|---:|
        | Swift | 10 |

        Use `markdownpdf`.

        - Linux
        - PDF
        """

        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.hasPrefix("%PDF-1.4"))
        #expect(text.contains("/BaseFont /Helvetica"))
        #expect(text.contains("/BaseFont /Courier"))
        #expect(!text.contains("/FontFile"))
        #expect(text.contains("xref"))
    }

    @Test("Writes xref entries that point at PDF objects")
    func writesValidXrefOffsets() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "# Title\n\nBody text.")
        let inspector = PDFInspector(data)

        #expect(inspector.hasValidXrefOffsets())
    }

    @Test("Renders on a non-main dispatch queue")
    func rendersOnNonMainDispatchQueue() throws {
        let result = try DispatchQueue.global(qos: .userInitiated).sync {
            let data = try MarkdownPDFRenderer(
                options: PDFOptions(
                    pageSize: .a4,
                    margins: PDFOptions.Margins(top: 56, right: 54, bottom: 56, left: 54),
                    baseFontSize: 10,
                    title: "Detached Render",
                    tableOfContents: .enabled,
                ),
            ).render(markdown: """
            # Detached Render

            This render must not depend on the UI thread.

            | Runtime | Requirement |
            |---|---|
            | CLI | Worker thread is acceptable |
            | App UI | Caller must schedule rendering away from the main actor |

            ```text
            Detached rendering keeps large PDF creation out of the interface loop.
            ```
            """)

            return (ranOnMainThread: Thread.isMainThread, data: data)
        }
        let inspector = PDFInspector(result.data)

        #expect(!result.ranOnMainThread)
        #expect(inspector.text.hasPrefix("%PDF-1.4"))
        #expect(inspector.pageCount >= 1)
        #expect(inspector.hasValidXrefOffsets())
        #expect(inspector.streamLengthsMatch())
    }

    @Test("Linux product renders with portable renderer")
    func linuxProductRendersPDF() throws {
        let data = try MarkdownPDFLinuxRenderer().render(markdown: "# Linux\n\nPortable output.")
        let inspector = PDFInspector(data)

        #expect(inspector.text.hasPrefix("%PDF-1.4"))
        #expect(inspector.hasValidXrefOffsets())
    }

    #if canImport(MarkdownPDFMac)
        @Test("Mac product renders through macOS entry point")
        func macProductRendersPDF() throws {
            let data = try MarkdownPDFMacRenderer().render(markdown: "# Mac\n\nPlatform output.")
            let inspector = PDFInspector(data)

            #expect(inspector.text.hasPrefix("%PDF-1.4"))
            #expect(!inspector.text.contains("/FontFile"))
            #expect(inspector.hasValidXrefOffsets())
        }
    #endif

    @Test("Writes stream lengths that match emitted bytes")
    func writesMatchingStreamLengths() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        # Title

        Body text with [a link](https://example.com/docs).
        """)
        let inspector = PDFInspector(data)

        #expect(inspector.streamLengthsMatch())
    }

    @Test("Block quotes indent without vertical border strokes")
    func blockQuotesDoNotEmitVerticalBorderStrokes() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        Intro paragraph.

        > Quoted text stays readable through indentation.

        Follow-up paragraph.
        """)
        let streamBodies = PDFInspector(data).streams.map(\.body).joined(separator: "\n")

        #expect(streamBodies.contains("(Quoted "))
        #expect(!streamBodies.contains(" l S"))
        #expect(!streamBodies.contains("2 w"))
    }

    @Test("Writes minimal canonical PDF for one text page")
    func writesMinimalCanonicalPDFForOneTextPage() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Hello from MarkdownPDF.")
        let inspector = PDFInspector(data)

        #expect(inspector.text.hasPrefix("%PDF-1.4"))
        #expect(inspector.text.hasSuffix("%%EOF"))
        #expect(inspector.pageCount == 1)
        #expect(inspector.indirectObjectCount == 5)
        #expect(inspector.streams.count == 1)
        #expect(inspector.hasValidXrefOffsets())
        #expect(inspector.streamLengthsMatch())
        #expect(inspector.text.contains("<< /Type /Catalog /Pages 2 0 R >>"))
        #expect(inspector.text.contains("<< /Type /Pages /Kids [5 0 R] /Count 1 >>"))
        #expect(inspector.text.contains("/Resources << /Font << /F1 3 0 R >> >>"))
        #expect(inspector.text.contains("trailer\n<< /Size 6 /Root 1 0 R >>"))
        #expect(!inspector.text.contains("/BaseFont /Helvetica-Bold"))
        #expect(!inspector.text.contains("/BaseFont /Helvetica-Oblique"))
        #expect(!inspector.text.contains("/BaseFont /Courier"))
        #expect(!inspector.text.contains("/XObject"))
        #expect(!inspector.text.contains("/Annots"))
        #expect(!inspector.text.contains("/ViewerPreferences"))
        #expect(!inspector.text.contains("/FontFile"))
    }

    @Test("Writes deterministic page resource dictionaries")
    func writesDeterministicPageResourceDictionaries() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownPDFTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageURL = directory.appendingPathComponent("image.jpg")
        try minimalJPEG().write(to: imageURL)

        let data = try MarkdownPDFRenderer().render(
            markdown: "# Image\n\n![pixel](image.jpg)",
            assetsBaseURL: directory,
        )
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("/Resources << /Font << /F2 3 0 R >> /XObject << /Im1 4 0 R >> >>"))
    }

    @Test("Reports page count and link annotations in generated PDF")
    func reportsPagesAndLinkAnnotations() throws {
        let longBody = Array(
            repeating: "This paragraph forces the renderer to continue onto another page.",
            count: 24,
        ).joined(separator: "\n\n")
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 220, height: 180),
                margins: PDFOptions.Margins(top: 20, right: 20, bottom: 20, left: 20),
                baseFontSize: 10,
            ),
        ).render(markdown: "[Docs](https://example.com/docs)\n\n\(longBody)")
        let inspector = PDFInspector(data)

        #expect(inspector.pageCount > 1)
        #expect(inspector.linkAnnotationCount == 1)
    }

    @Test("Escapes literal strings in content streams")
    func escapesLiteralStrings() throws {
        let data = try MarkdownPDFRenderer().render(
            markdown: #"Text (with parens) and slash \ here."#,
        )
        let streamBodies = PDFInspector(data).streams.map(\.body).joined(separator: "\n")

        #expect(streamBodies.contains(#"(\(with "#))
        #expect(streamBodies.contains(#"parens\) "#))
        #expect(streamBodies.contains(#"(\\ )"#))
    }

    @Test("Supports monospaced PDF base font set")
    func supportsMonospacedPDFBaseFontSet() throws {
        let markdown = """
        # Jane Doe

        Swift engineer.
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(fontSet: .pdfBaseMonospaced),
        ).render(markdown: markdown)
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("/BaseFont /Courier"))
        #expect(!text.contains("/FontFile"))
    }

    @Test("Uses proportional metrics for PDF base fonts")
    func usesProportionalMetricsForPDFBaseFonts() throws {
        let options = PDFOptions(
            pageSize: PDFOptions.PageSize(width: 140, height: 220),
            margins: PDFOptions.Margins(top: 20, right: 20, bottom: 20, left: 20),
            baseFontSize: 10,
            fontSet: .pdfBase,
        )

        let narrowData = try MarkdownPDFRenderer(options: options).render(markdown: "iiiiiiiiii iiiiiiiiii iiiiiiiiii")
        let wideData = try MarkdownPDFRenderer(options: options).render(markdown: "WWWWWWWWWW WWWWWWWWWW WWWWWWWWWW")

        let narrowLineCount = textLineYCoordinates(in: String(decoding: narrowData, as: UTF8.self)).count
        let wideLineCount = textLineYCoordinates(in: String(decoding: wideData, as: UTF8.self)).count

        #expect(narrowLineCount == 1)
        #expect(wideLineCount > narrowLineCount)
    }

    @Test("Writes proportional widths for Apple system TrueType font dictionaries")
    func writesProportionalWidthsForAppleSystemTrueTypeFontDictionaries() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(fontSet: .appleSystem),
        ).render(markdown: "# WWW\n\nRegular\n\n**Bold**\n\n`code`")
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("/BaseFont /SFProText-Regular"))
        #expect(text.contains("/BaseFont /SFProText-Bold"))
        #expect(text.contains("/BaseFont /SFMono-Regular"))
        #expect(text.contains("/Widths [278 278 355 556"))
        #expect(text.contains("/Widths [278 333 474 556"))
        #expect(text.contains("/Widths [600 600 600 600"))
        #expect(!text.contains("/FontFile"))
    }

    @Test("Embedded font public API writes CID fonts for supplied roles")
    func embeddedFontPublicAPIWritesCIDFontsForSuppliedRoles() throws {
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "Public Regular")
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 280, height: 240),
                margins: PDFOptions.Margins(top: 24, right: 24, bottom: 24, left: 24),
                baseFontSize: 12,
                embeddedFonts: PDFOptions.EmbeddedFonts(regular: source),
            ),
        ).render(markdown: "WIDE WILLIAM\n\n**BOLD TEXT**\n\n`CODE TEXT`")
        let inspector = PDFInspector(data)

        #expect(inspector.text.contains("/Font << /F2"))
        #expect(inspector.text.contains("/EF1"))
        #expect(inspector.text.contains("/Subtype /Type0"))
        #expect(inspector.text.contains("/Subtype /CIDFontType2"))
        #expect(inspector.text.contains("/FontFile2"))
        #expect(inspector.text.contains("/ToUnicode"))
        #expect(inspector.streams.contains { $0.body.contains("/EF1 12 Tf") })
        #expect(inspector.streams.contains { $0.body.contains("/F2 12 Tf") })
        #expect(inspector.streams.contains { $0.body.contains("/F4 11.400 Tf") })
    }

    @Test("Embedded font renderer emits shaped ligature ToUnicode witnesses")
    func embeddedFontRendererEmitsShapedLigatureToUnicodeWitnesses() throws {
        let fontData = SyntheticTrueTypeFont.data(
            glyphProfile: .latinLigature,
            includeGlyphOutlines: true,
            includeGSUBLigatures: true,
        )
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "Public Ligature")
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 220, height: 160),
                margins: PDFOptions.Margins(top: 24, right: 24, bottom: 24, left: 24),
                baseFontSize: 14,
                embeddedFonts: PDFOptions.EmbeddedFonts(regular: source),
                title: "Shaped Ligature Renderer",
            ),
        ).render(markdown: "file")
        let inspector = PDFInspector(data)
        let streams = inspector.streams.map(\.body).joined(separator: "\n")

        #expect(streams.contains("<000600030004> Tj"))
        #expect(inspector.text.contains("<0006> <00660069>"))
        try PDFValidation.writeArtifact(data, name: "shaped-ligature-renderer-witness.pdf")

        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "shaped-ligature-renderer-qpdf")
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        let textResult = try PDFValidation.pdftotext(data: data, name: "shaped-ligature-renderer-text")
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        #expect(textResult.output.contains("file"))
        let mupdfText = try PDFValidation.mutoolStructuredText(data: data, name: "shaped-ligature-renderer-mupdf")
        try #require(mupdfText.exitCode == 0, "mutool structured text failed:\n\(mupdfText.output)")
        let layout = try MuPDFStructuredText(xml: mupdfText.output)
        #expect(layout.characterQuadIssues().isEmpty)
    }

    @Test("Embedded font renderer rejects unsupported complex-script shaping")
    func embeddedFontRendererRejectsUnsupportedComplexScriptShaping() throws {
        let fontData = SyntheticTrueTypeFont.data(includeGlyphOutlines: true)
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "Unsupported Script")

        do {
            _ = try MarkdownPDFRenderer(
                options: PDFOptions(embeddedFonts: PDFOptions.EmbeddedFonts(regular: source)),
            ).render(markdown: "\u{0633}\u{0644}\u{0627}\u{0645}")
            Issue.record("Expected unsupported complex-script shaping error")
        } catch let error as PDFEmbeddedFontError {
            #expect(error == .unsupportedComplexScriptScalar(scalar: "\u{0633}"))
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
        } catch {
            Issue.record("Expected PDFEmbeddedFontError, got \(error)")
        }
    }

    @Test("Embedded font allRoles maps markdown style roles")
    func embeddedFontAllRolesMapsMarkdownStyleRoles() throws {
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "Public All Roles")
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                baseFontSize: 12,
                embeddedFonts: .allRoles(source),
            ),
        ).render(markdown: "# WIDE\n\nPLAIN **BOLD** *ITALIC* `CODE`")
        let streamBodies = PDFInspector(data).streams.map(\.body).joined(separator: "\n")
        let text = String(decoding: data, as: UTF8.self)

        #expect(streamBodies.contains("/EF2 24 Tf"))
        #expect(streamBodies.contains("/EF1 12 Tf"))
        #expect(streamBodies.contains("/EF2 12 Tf"))
        #expect(streamBodies.contains("/EF3 12 Tf"))
        #expect(streamBodies.contains("/EF4 11.400 Tf"))
        #expect(!streamBodies.contains("/F1 12 Tf"))
        #expect(!streamBodies.contains("/F2 12 Tf"))
        #expect(text.contains("/EF1"))
        #expect(text.contains("/EF2"))
        #expect(text.contains("/EF3"))
        #expect(text.contains("/EF4"))
    }

    @Test("Embedded font API rejects fonts that forbid embedding")
    func embeddedFontAPIRejectsFontsThatForbidEmbedding() throws {
        let fontData = SyntheticTrueTypeFont.data(fsType: 0x0002)
        let source = PDFOptions.EmbeddedFontSource(data: fontData)

        do {
            _ = try MarkdownPDFRenderer(
                options: PDFOptions(embeddedFonts: PDFOptions.EmbeddedFonts(regular: source)),
            ).render(markdown: "ABBA")
            Issue.record("Expected restricted embedding error")
        } catch let error as TrueTypeFontError {
            #expect(error == .restrictedEmbedding(fsType: 0x0002))
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
        } catch {
            Issue.record("Expected TrueTypeFontError, got \(error)")
        }
    }

    @Test(
        .enabled(
            if: OpenTrueTypeFontFixture.isAvailable,
            OpenTrueTypeFontFixture.skipReason,
        ),
    )
    func embeddedFontPublicAPIRendersOpenFontFixture() throws {
        let fontURL = try #require(OpenTrueTypeFontFixture.url)
        let source = try PDFOptions.EmbeddedFontSource(data: Data(contentsOf: fontURL))
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                embeddedFonts: .allRoles(source),
                title: "Open Font Fixture",
                tableOfContents: .enabled,
            ),
        ).render(markdown: "# Open Font\n\n## Café\n\nCafé résumé text uses embedded glyphs.")
        let inspector = PDFInspector(data)

        #expect(inspector.text.contains("/Subtype /Type0"))
        #expect(inspector.text.contains("/Subtype /CIDFontType2"))
        #expect(inspector.text.contains("/FontFile2"))
        #expect(inspector.text.contains("/ToUnicode"))
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "open-font-fixture")
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        let textResult = try PDFValidation.pdftotext(data: data, name: "open-font-fixture-text")
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        let extractedText = normalizedExtractedText(textResult.output)
        #expect(extractedText.contains("Table of Contents"))
        #expect(extractedText.contains("Café résumé text uses embedded glyphs."))
    }

    @Test("Renders Markdown links as PDF URI annotations")
    func rendersLinkAnnotations() throws {
        let markdown = """
        [Example](https://example.com/docs) and <person@example.com>
        """

        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("/Annots ["))
        #expect(text.contains("/Subtype /Link"))
        #expect(text.contains("/S /URI"))
        #expect(text.contains("/URI (https://example.com/docs)"))
        #expect(text.contains("/URI (mailto:person@example.com)"))
    }

    @Test("Writes heading destinations, outlines, internal links, and metadata")
    func writesHeadingDestinationsOutlinesInternalLinksAndMetadata() throws {
        let markdown = """
        # Intro

        [Jump to details](#details) and [External](https://example.com).

        ## Details

        Body text.

        # Intro

        Duplicate heading.
        """
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(title: "Navigation Article"),
        ).render(markdown: markdown)
        let inspector = PDFInspector(data)

        #expect(inspector.hasDocumentMetadata)
        #expect(inspector.outlineItemCount == 3)
        #expect(Set(inspector.namedDestinationNames) == ["intro", "details", "intro-2"])
        #expect(inspector.text.contains("/Outlines "))
        #expect(inspector.text.contains("/Names << /Dests"))
        #expect(inspector.text.contains("/Dest (details)"))
        #expect(inspector.text.contains("/URI (https://example.com)"))
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "Canonical PDF structure failed:\n\(inspector.canonicalStructureReport())",
        )
    }

    @Test("Generates table of contents with final page numbers and internal links")
    func generatesTableOfContentsWithFinalPageNumbersAndInternalLinks() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
                tableOfContents: .enabled,
            ),
        ).render(markdown: generatedTableOfContentsMarkdown())
        let inspector = PDFInspector(data)
        let pages = inspector.namedDestinationPages
        let methodsPage = try #require(pages["methods"])
        let resultsPage = try #require(pages["results"])
        let tocStream = try #require(inspector.streams.first { $0.body.contains("(Table of Contents)") }?.body)
        let textResult = try PDFValidation.pdftotext(data: data, name: "generated-toc")
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "generated-toc")
        let pdfinfo = try PDFValidation.pdfinfo(data: data, name: "generated-toc")
        let info = PDFValidation.parsedInfo(from: pdfinfo)

        #expect(methodsPage > 1)
        #expect(resultsPage >= methodsPage)
        #expect(tocStream.contains("(Methods)"))
        #expect(tocStream.contains("(Results)"))
        #expect(tocStream.contains("(\(methodsPage))"))
        #expect(tocStream.contains("(\(resultsPage))"))
        #expect(inspector.internalLinkDestinationNames.contains("methods"))
        #expect(inspector.internalLinkDestinationNames.contains("results"))
        #expect(inspector.linkAnnotationCount >= inspector.namedDestinationNames.count)
        #expect(qpdf.exitCode == 0, "qpdf --check failed for generated ToC PDF:\n\(qpdf.output)")
        #expect(pdfinfo.exitCode == 0, "pdfinfo failed for generated ToC PDF:\n\(pdfinfo.output)")
        #expect(info["Pages"] == "\(inspector.pageCount)")
        #expect(textResult.exitCode == 0, "pdftotext failed for generated ToC PDF:\n\(textResult.output)")
        #expect(textResult.output.contains("Table of Contents"))
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "Canonical PDF structure failed:\n\(inspector.canonicalStructureReport())",
        )
    }

    @Test("Renders supported Mermaid flowcharts through PDF drawing operators")
    func rendersSupportedMermaidFlowchartsThroughPDFDrawingOperators() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        ```mermaid
        flowchart TD
            Input[Markdown source] --> Parse[Block parser]
            Parse --> Layout[Article layout]
            Layout --> PDF[PDF bytes]
        ```
        """)
        let inspector = PDFInspector(data)
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")
        let textResult = try PDFValidation.pdftotext(data: data, name: "mermaid-flowchart")

        #expect(streamText.contains("(Markdown )"))
        #expect(streamText.contains("(source)"))
        #expect(streamText.contains("(Block )"))
        #expect(streamText.contains("(parser)"))
        #expect(streamText.contains(" re f"))
        #expect(!streamText.contains("(flowchart TD)"))
        #expect(textResult.exitCode == 0, "pdftotext failed for Mermaid PDF:\n\(textResult.output)")
        #expect(textResult.output.contains("Markdown source"))
        #expect(textResult.output.contains("PDF bytes"))
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "Canonical PDF structure failed:\n\(inspector.canonicalStructureReport())",
        )
    }

    @Test("Falls back visibly for unsupported Mermaid syntax")
    func fallsBackVisiblyForUnsupportedMermaidSyntax() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        ```mermaid
        sequenceDiagram
            Alice->>Bob: Hello
        ```
        """)
        let textResult = try PDFValidation.pdftotext(data: data, name: "unsupported-mermaid")

        #expect(textResult.exitCode == 0, "pdftotext failed for unsupported Mermaid fallback:\n\(textResult.output)")
        #expect(textResult.output.contains("Unsupported Mermaid diagram"))
        #expect(textResult.output.contains("sequenceDiagram"))
    }

    @Test("Renders Mermaid edge labels into extractable PDF text")
    func rendersMermaidEdgeLabelsIntoExtractablePDFText() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        ```mermaid
        graph LR
            A["Markdown"] -->|parse| B["PDF"]
        ```
        """)
        let textResult = try PDFValidation.pdftotext(data: data, name: "mermaid-edge-label")

        #expect(textResult.exitCode == 0, "pdftotext failed for Mermaid edge label PDF:\n\(textResult.output)")
        #expect(textResult.output.contains("Markdown"))
        #expect(textResult.output.contains("parse"))
        #expect(textResult.output.contains("PDF"))
        #expect(!textResult.output.contains("graph LR"))
    }

    @Test("Falls back visibly when Mermaid edge labels collide with nodes")
    func fallsBackVisiblyWhenMermaidEdgeLabelsCollideWithNodes() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        ```mermaid
        graph LR
            A["Markdown"] -->|this label is intentionally too long to fit in the edge gap| B["PDF"]
        ```
        """)
        let textResult = try PDFValidation.pdftotext(data: data, name: "mermaid-edge-label-collision")

        #expect(textResult.exitCode == 0, "pdftotext failed for Mermaid edge label fallback:\n\(textResult.output)")
        #expect(textResult.output.contains("Unsupported Mermaid diagram"))
        #expect(textResult.output.contains("collides with a diagram node"))
        #expect(textResult.output.contains("this label is intentionally too long"))
        #expect(textResult.output.contains("graph LR"))
    }

    @Test("Falls back visibly when Mermaid edge labels collide with intermediate nodes")
    func fallsBackVisiblyWhenMermaidEdgeLabelsCollideWithIntermediateNodes() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        ```mermaid
        flowchart TD
            Start["Start"] -->|crosses the middle node| End["End"]
            Start --> Middle["Middle"]
            Middle --> End
        ```
        """)
        let textResult = try PDFValidation.pdftotext(data: data, name: "mermaid-edge-label-intermediate-collision")
        let normalizedOutput = textResult.output.replacingOccurrences(of: "\n", with: " ")

        #expect(textResult.exitCode == 0, "pdftotext failed for Mermaid intermediate label fallback:\n\(textResult.output)")
        #expect(textResult.output.contains("Unsupported Mermaid diagram"))
        #expect(normalizedOutput.contains("collides with a diagram node"))
        #expect(textResult.output.contains("crosses the middle node"))
        #expect(textResult.output.contains("flowchart TD"))
    }

    @Test("Keeps unknown fragment links as URI annotations")
    func keepsUnknownFragmentLinksAsURIAnnotations() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "[Missing](#Missing%20Section)")
        let inspector = PDFInspector(data)

        #expect(inspector.namedDestinationNames.isEmpty)
        #expect(inspector.text.contains("/URI (#Missing%20Section)"))
        #expect(!inspector.text.contains("/Dest (missing-section)"))
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "Canonical PDF structure failed:\n\(inspector.canonicalStructureReport())",
        )
    }

    @Test("Normalizes internal fragment links to heading destination names")
    func normalizesInternalFragmentLinksToHeadingDestinationNames() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        # Report Section

        [Jump](#Report%20Section)
        """)
        let inspector = PDFInspector(data)

        #expect(inspector.namedDestinationNames == ["report-section"])
        #expect(inspector.text.contains("/Dest (report-section)"))
        #expect(!inspector.text.contains("/URI (#Report%20Section)"))
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "Canonical PDF structure failed:\n\(inspector.canonicalStructureReport())",
        )
    }

    @Test("Keeps section headings with first child content")
    func keepsSectionHeadingsWithFirstChildContent() throws {
        let markdown = """
        # Intro

        Line one

        ## Projects

        ### DocHarbor

        Summary line
        """
        let options = PDFOptions(
            pageSize: PDFOptions.PageSize(width: 300, height: 220),
            margins: PDFOptions.Margins(top: 20, right: 20, bottom: 20, left: 20),
            baseFontSize: 10,
        )
        let data = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
        let text = String(decoding: data, as: UTF8.self)
        let streams = contentStreams(in: text)
        let projectsStream = streams.first { $0.contains("(Projects)") }

        #expect(streams.count >= 2)
        #expect(projectsStream?.contains("(DocHarbor)") == true)
        #expect(projectsStream?.contains("(Summary )") == true)
        #expect(projectsStream?.contains("(line)") == true)
    }

    @Test("Embeds local JPEG images")
    func embedsJPEGImages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownPDFTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageURL = directory.appendingPathComponent("image.jpg")
        try minimalJPEG().write(to: imageURL)

        let data = try MarkdownPDFRenderer().render(
            markdown: "![pixel](image.jpg)",
            assetsBaseURL: directory,
        )
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("/Subtype /Image"))
        #expect(text.contains("/DCTDecode"))
    }

    @Test("Embeds local PNG images")
    func embedsPNGImages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownPDFTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageURL = directory.appendingPathComponent("image.png")
        try minimalPNG().write(to: imageURL)

        let data = try MarkdownPDFRenderer().render(
            markdown: "![pixel](image.png)",
            assetsBaseURL: directory,
        )
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("/Subtype /Image"))
        #expect(text.contains("/FlateDecode"))
        #expect(text.contains("/DecodeParms << /Predictor 15 /Colors 3 /BitsPerComponent 8 /Columns 1 >>"))

        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "png-image")
        #expect(qpdf.exitCode == 0, "qpdf --check failed for PNG image PDF:\n\(qpdf.output)")

        let render = try PDFValidation.pdftoppmPNG(data: data, name: "png-image")
        let pngData = try? Data(contentsOf: render.pngURL)
        let dimensions = PDFValidation.pngDimensions(in: pngData)
        #expect(render.result.exitCode == 0, "pdftoppm failed for PNG image PDF:\n\(render.result.output)")
        #expect((dimensions?.width ?? 0) > 0)
        #expect((dimensions?.height ?? 0) > 0)
    }

    @Test("Reuses local image XObjects by source")
    func reusesLocalImageXObjectsBySource() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownPDFTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageURL = directory.appendingPathComponent("image.png")
        try minimalPNG().write(to: imageURL)

        let data = try MarkdownPDFRenderer().render(
            markdown: """
            ![first](image.png)

            ![second](image.png)
            """,
            assetsBaseURL: directory,
        )
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.components(separatedBy: "/Subtype /Image").count - 1 == 1)
        #expect(text.components(separatedBy: "/Im1 Do").count - 1 == 2)
        #expect(!text.contains("/Im2"))
    }

    private func minimalJPEG() -> Data {
        Data([
            0xFF, 0xD8,
            0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
            0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x01, 0x00, 0x01, 0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00,
            0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00,
            0x00,
            0xFF, 0xD9,
        ])
    }

    private func minimalPNG() -> Data {
        Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D,
            0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00,
            0x90, 0x77, 0x53, 0xDE,
            0x00, 0x00, 0x00, 0x0F,
            0x49, 0x44, 0x41, 0x54,
            0x78, 0x01, 0x01, 0x04, 0x00, 0xFB, 0xFF,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x04, 0x00, 0x01,
            0x65, 0x49, 0xC3, 0x60,
            0x00, 0x00, 0x00, 0x00,
            0x49, 0x45, 0x4E, 0x44,
            0xAE, 0x42, 0x60, 0x82,
        ])
    }

    private func generatedTableOfContentsMarkdown() -> String {
        let denseParagraphs = Array(
            repeating: """
            Portable PDF generation needs deterministic page structure, stable
            heading anchors, extractable text, and independent tool witnesses for
            every page that layout creates.
            """,
            count: 8,
        ).joined(separator: "\n\n")

        return """
        # Portable Report

        \(denseParagraphs)

        ## Methods

        \(denseParagraphs)

        ## Results

        \(denseParagraphs)

        ## Appendix

        \(denseParagraphs)
        """
    }

    private func contentStreams(in text: String) -> [String] {
        text.components(separatedBy: "stream\n")
            .dropFirst()
            .compactMap { component in
                component.components(separatedBy: "\nendstream").first
            }
    }

    private func textLineYCoordinates(in text: String) -> Set<String> {
        Set(
            text.components(separatedBy: "\n").compactMap { line in
                guard line.hasPrefix("BT "),
                      let tfRange = line.range(of: " Tf "),
                      let tdRange = line.range(of: " Td", range: tfRange.upperBound ..< line.endIndex)
                else {
                    return nil
                }

                let coordinates = line[tfRange.upperBound ..< tdRange.lowerBound].split(separator: " ")
                return coordinates.last.map(String.init)
            },
        )
    }

    private func normalizedExtractedText(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

private enum OpenTrueTypeFontFixture {
    static var isAvailable: Bool {
        configuredPath != nil || installedURL != nil
    }

    static let skipReason: Comment = """
    requires MARKDOWNPDF_OPEN_FONT_PATH or DejaVuSans.ttf at /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf, ~/Library/Fonts/DejaVuSans.ttf, or /Library/Fonts/DejaVuSans.ttf
    """

    static var url: URL? {
        if let configuredPath {
            return URL(fileURLWithPath: configuredPath)
        }

        return installedURL
    }

    private static var installedURL: URL? {
        installedCandidatePaths
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static var configuredPath: String? {
        let rawPath = ProcessInfo.processInfo.environment["MARKDOWNPDF_OPEN_FONT_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawPath, !rawPath.isEmpty else {
            return nil
        }
        return rawPath
    }

    private static var installedCandidatePaths: [String] {
        [
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "\(NSHomeDirectory())/Library/Fonts/DejaVuSans.ttf",
            "/Library/Fonts/DejaVuSans.ttf",
        ]
    }
}
