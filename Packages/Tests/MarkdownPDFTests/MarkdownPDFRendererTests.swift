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
    @Test("Named page sizes set the page MediaBox")
    func namedPageSizesSetTheMediaBox() throws {
        #expect(PDFOptions.PageSize.a0 == PDFOptions.PageSize(width: 2383.94, height: 3370.39))
        #expect(PDFOptions.PageSize.a1 == PDFOptions.PageSize(width: 1683.78, height: 2383.94))
        #expect(PDFOptions.PageSize.a3 == PDFOptions.PageSize(width: 841.89, height: 1190.55))
        #expect(PDFOptions.PageSize.a5 == PDFOptions.PageSize(width: 419.53, height: 595.28))
        #expect(PDFOptions.PageSize.a6 == PDFOptions.PageSize(width: 297.64, height: 419.53))
        #expect(PDFOptions.PageSize.legal == PDFOptions.PageSize(width: 612, height: 1008))
        #expect(PDFOptions.PageSize.tabloid == PDFOptions.PageSize(width: 792, height: 1224))

        let data = try MarkdownPDFRenderer(options: PDFOptions(pageSize: .a3)).render(markdown: "# A3 page")
        let inspector = PDFInspector(data)
        #expect(inspector.text.contains("841.89"))
        #expect(inspector.text.contains("1190.55"))
        #expect(inspector.hasValidXrefOffsets())
        #expect(inspector.streamLengthsMatch())
    }

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

    @Test("Renders GFM footnotes and task-list checkboxes")
    func rendersGFMFootnotesAndTaskListCheckboxes() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        Alpha footnote[^beta] repeats[^beta] and dangling [^missing].

        [^unused]: Hidden note.
        > [^beta]: Beta **note** body.

        - [ ] Open task
        - [x] Done task
        - [ ]not a task
        """)
        let inspector = PDFInspector(data)
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "gfm-footnotes-tasklists")
        let textResult = try PDFValidation.pdftotext(data: data, name: "gfm-footnotes-tasklists-text")
        let extractedText = normalizedExtractedText(textResult.output)
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")

        #expect(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        #expect(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        #expect(Set(inspector.namedDestinationNames).isSuperset(of: ["fn-1", "fnref-1"]))
        #expect(inspector.outlineItemCount == 0)
        #expect(inspector.internalLinkDestinationNames.count(where: { $0 == "fn-1" }) == 2)
        #expect(inspector.internalLinkDestinationNames.contains("fnref-1"))
        #expect(!inspector.namedDestinationNames.contains("fn-2"))
        #expect(extractedText.contains("dangling [^missing]"))
        #expect(extractedText.contains("Footnotes"))
        #expect(extractedText.contains("1. Beta note body."))
        #expect(!extractedText.contains("Hidden note"))
        #expect(extractedText.contains("Open task"))
        #expect(extractedText.contains("Done task"))
        #expect(extractedText.contains("[ ]not a task"))
        #expect(streamText.components(separatedBy: " re S").count - 1 >= 2)
        #expect(streamText.components(separatedBy: " l ").count - 1 >= 2)
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "Canonical PDF structure failed:\n\(inspector.canonicalStructureReport())",
        )
    }

    @Test("Renders opt-in TeX math subset with extraction and rule witnesses")
    func rendersOptInTeXMathSubset() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(mathTypesetting: .enabled),
        ).render(markdown: """
        Inline $x^2 + \\alpha_i$ remains in the paragraph.

        $$
        \\frac{x^2}{\\sqrt{y+1}}
        $$

        $$
        \\sum_{i=1}^n i
        $$
        """)
        try PDFValidation.writeArtifact(data, name: "math-typesetting-subset.pdf")
        let inspector = PDFInspector(data)
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "math-typesetting-subset")
        let textResult = try PDFValidation.pdftotext(data: data, name: "math-typesetting-subset-text")
        let mupdf = try PDFValidation.mutoolStructuredText(data: data, name: "math-typesetting-subset-mupdf")
        let extractedText = normalizedExtractedText(textResult.output)
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")

        #expect(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        #expect(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try #require(mupdf.exitCode == 0, "mutool structured text failed:\n\(mupdf.output)")
        let structuredText = try MuPDFStructuredText(xml: mupdf.output)
        let visibleGlyphCount = structuredText.glyphs.count(where: { !$0.isWhitespace })
        let geometryIssues = structuredText.characterQuadIssues()

        #expect(extractedText.contains("Inline"))
        #expect(extractedText.contains("frac(x^{2}, sqrt(y+1))"), "Unexpected extracted text:\n\(textResult.output)")
        #expect(extractedText.contains("sum_{i=1}^{n} i"), "Unexpected extracted text:\n\(textResult.output)")
        #expect(streamText.contains("/ActualText (frac\\(x^{2}, sqrt\\(y+1\\)\\))"))
        #expect(streamText.components(separatedBy: " re f").count - 1 >= 2)
        #expect(visibleGlyphCount >= 20)
        #expect(
            geometryIssues.isEmpty,
            "MuPDF character layout has visual issues:\n\(geometryIssues.joined(separator: "\n"))",
        )
        #expect(inspector.hasValidXrefOffsets())
        #expect(inspector.streamLengthsMatch())
    }

    @Test("Inline fractions and radicals typeset as 2D boxes in the text flow")
    func inlineFractionsTypesetAsBoxes() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(mathTypesetting: .enabled),
        ).render(markdown: "Pressure is $\\frac{a}{b}$ and the bound is $\\sqrt{x}$ inline.")
        let inspector = PDFInspector(data)
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "inline-math-box")
        let textResult = try PDFValidation.pdftotext(data: data, name: "inline-math-box-text")
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        let extracted = normalizedExtractedText(textResult.output)

        #expect(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        // The inline fraction bar and radical overbar emit rule rectangles in the
        // text flow rather than the parenthesized prose fallback.
        #expect(streamText.components(separatedBy: " re f").count - 1 >= 2)
        // ActualText preserves a readable linearization for extraction.
        #expect(extracted.contains("frac(a, b)"), "Unexpected extraction:\n\(textResult.output)")
        #expect(extracted.contains("sqrt(x)"), "Unexpected extraction:\n\(textResult.output)")
        #expect(extracted.contains("Pressure is"))
        #expect(extracted.contains("inline"))
        #expect(inspector.hasValidXrefOffsets())
        #expect(inspector.streamLengthsMatch())
    }

    @Test("Unsupported math renders visible source fallback")
    func unsupportedMathRendersVisibleSourceFallback() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(mathTypesetting: .enabled),
        ).render(markdown: #"Unsupported $\unknown{x}$ stays visible."#)
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "unsupported-math-fallback")
        let textResult = try PDFValidation.pdftotext(data: data, name: "unsupported-math-fallback-text")
        let extractedText = normalizedExtractedText(textResult.output)

        #expect(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        #expect(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        #expect(extractedText.contains(#"$\unknown{x}$"#), "Unexpected extracted text:\n\(textResult.output)")
    }

    @Test("Renders fixed left right math delimiters")
    func rendersFixedLeftRightMathDelimiters() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(mathTypesetting: .enabled),
        ).render(markdown: """
        $$
        \\left(\\frac{x}{y}\\right)
        $$

        $$
        \\left\\langle{x}\\right\\rangle
        $$

        $$
        \\left.\\frac{x}{y}\\right\\}
        $$

        $$
        \\left/x\\right\\backslash
        $$
        """)
        let inspector = PDFInspector(data)
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "math-fixed-delimiters")
        let textResult = try PDFValidation.pdftotext(data: data, name: "math-fixed-delimiters-text")
        let extractedText = normalizedExtractedText(textResult.output)
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")

        #expect(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        #expect(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        #expect(extractedText.contains("(frac(x, y))"), "Unexpected extracted text:\n\(textResult.output)")
        #expect(extractedText.contains("<x>"), "Unexpected extracted text:\n\(textResult.output)")
        #expect(extractedText.contains("frac(x, y)}"), "Unexpected extracted text:\n\(textResult.output)")
        #expect(extractedText.contains(#"/x\"#), "Unexpected extracted text:\n\(textResult.output)")
        #expect(streamText.contains("/ActualText (\\(frac\\(x, y\\)\\))"))
        #expect(streamText.components(separatedBy: " re f").count - 1 >= 2)
    }

    @Test("Malformed left delimiter renders visible source fallback")
    func malformedLeftDelimiterRendersVisibleSourceFallback() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(mathTypesetting: .enabled),
        ).render(markdown: #"Malformed $\left(x$ stays visible."#)
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "math-malformed-left-fallback")
        let textResult = try PDFValidation.pdftotext(data: data, name: "math-malformed-left-fallback-text")
        let extractedText = normalizedExtractedText(textResult.output)

        #expect(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        #expect(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        #expect(extractedText.contains(#"$\left(x$"#), "Unexpected extracted text:\n\(textResult.output)")
    }

    @Test("Block quotes indent without vertical border strokes")
    func blockQuotesDoNotEmitVerticalBorderStrokes() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        Intro paragraph.

        ```swift
        struct Surface {
            let roughness: Double
            let transmission: Double
        }
        ```

        > QuoteStartToken quoted text stays readable through indentation.
        > > NestedQuoteToken nested quoted text keeps another indentation level.
        > QuoteEndToken quoted text ends before the next heading.

        ## AfterQuoteHeading

        Follow-up paragraph.
        """)
        let streamBodies = PDFInspector(data).streams.map(\.body).joined(separator: "\n")
        let strokeLines = streamBodies
            .split(separator: "\n")
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

                return trimmed.hasSuffix(" S") || trimmed.contains(" RG ")
            }

        #expect(streamBodies.contains("(QuoteStartToken"))
        #expect(streamBodies.contains("(NestedQuoteToken"))
        #expect(streamBodies.contains("(AfterQuoteHeading"))
        #expect(strokeLines.isEmpty, "Unexpected stroke operators:\n\(strokeLines.joined(separator: "\n"))")
    }

    @Test("Code blocks expand tabs into spaces")
    func codeBlocksExpandTabsIntoSpaces() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        ```swift
        \tlet value = 1
        ```
        """)
        let streamBodies = PDFInspector(data).streams.map(\.body).joined(separator: "\n")
        let singleSpaceTokenCount = streamBodies.components(separatedBy: "( ) Tj").count - 1

        #expect(!streamBodies.contains("\t"))
        #expect(!streamBodies.contains("(?"))
        #expect(singleSpaceTokenCount >= 4)
        #expect(streamBodies.contains("(let "))
    }

    @Test("Code syntax coloring is opt in and preserves extracted text")
    func codeSyntaxColoringIsOptInAndPreservesExtractedText() throws {
        let markdown = """
        ```swift
        // extractable comment
        let value = "record" + 42
        ```
        """
        let plainData = try MarkdownPDFRenderer().render(markdown: markdown)
        let coloredData = try MarkdownPDFRenderer(
            options: PDFOptions(codeSyntaxHighlighting: .enabled),
        ).render(markdown: markdown)
        let plainText = try PDFValidation.pdftotext(data: plainData, name: "plain-code-extraction")
        let coloredText = try PDFValidation.pdftotext(data: coloredData, name: "colored-code-extraction")
        let coloredStream = PDFInspector(coloredData).streams.map(\.body).joined(separator: "\n")
        let plainStream = PDFInspector(plainData).streams.map(\.body).joined(separator: "\n")

        try #require(plainText.exitCode == 0, "pdftotext failed for plain code:\n\(plainText.output)")
        try #require(coloredText.exitCode == 0, "pdftotext failed for colored code:\n\(coloredText.output)")
        #expect(normalizedExtractedText(plainText.output) == normalizedExtractedText(coloredText.output))
        #expect(!plainStream.contains(sourceCodeKeywordOperator))
        #expect(coloredStream.contains(sourceCodeKeywordOperator))
        #expect(coloredStream.contains(sourceCodeCommentOperator))
        #expect(coloredStream.contains(sourceCodeStringOperator))
        #expect(coloredStream.contains(sourceCodeNumberOperator))
        #expect(coloredStream.contains(sourceCodeOperatorOperator))
        #expect(coloredStream.contains("(let)"))
        #expect(coloredStream.contains(#"("record")"#))
        #expect(coloredStream.contains("(42)"))
    }

    @Test("Default theme preserves generated PDF bytes")
    func defaultThemePreservesGeneratedPDFBytes() throws {
        let markdown = """
        # Theme Baseline

        Body text with [a link](https://example.com) and `inline code`.

        > Quoted text.

        - [ ] Open task
        - [x] Done task

        | Name | Value |
        |---|---:|
        | Alpha | 42 |

        ```swift
        let value = "record" + 42
        ```

        [^n]: Footnote body.

        Footnote ref[^n].
        """

        let implicitDefault = try MarkdownPDFRenderer(
            options: PDFOptions(codeSyntaxHighlighting: .enabled),
        ).render(markdown: markdown)
        let explicitDefault = try MarkdownPDFRenderer(
            options: PDFOptions(codeSyntaxHighlighting: .enabled, theme: .default),
        ).render(markdown: markdown)

        #expect(implicitDefault == explicitDefault)
    }

    @Test("Built-in themes render valid PDFs and preserve extraction")
    func builtInThemesRenderValidPDFsAndPreserveExtraction() throws {
        let markdown = """
        # Themed Document

        Body text with [a link](https://example.com) and `inline code`.

        > A quote keeps contrast and spacing.

        - [ ] Review open task
        - [x] Review done task

        | Name | Value |
        |---|---:|
        | Alpha | 42 |

        ```swift
        // theme comment
        let value = "record" + 42
        ```
        """
        let defaultData = try MarkdownPDFRenderer(
            options: PDFOptions(codeSyntaxHighlighting: .enabled),
        ).render(markdown: markdown)
        let defaultText = try PDFValidation.pdftotext(data: defaultData, name: "theme-default-text")
        try #require(defaultText.exitCode == 0, "pdftotext failed for default theme:\n\(defaultText.output)")

        for (name, theme) in [("dark", PDFOptions.Theme.dark), ("print", PDFOptions.Theme.print)] {
            let data = try MarkdownPDFRenderer(
                options: PDFOptions(codeSyntaxHighlighting: .enabled, theme: theme),
            ).render(markdown: markdown)
            let inspector = PDFInspector(data)
            let qpdf = try PDFValidation.qpdfCheck(data: data, name: "theme-\(name)")
            let text = try PDFValidation.pdftotext(data: data, name: "theme-\(name)-text")

            #expect(qpdf.exitCode == 0, "qpdf --check failed for \(name):\n\(qpdf.output)")
            try #require(text.exitCode == 0, "pdftotext failed for \(name):\n\(text.output)")
            #expect(normalizedExtractedText(text.output) == normalizedExtractedText(defaultText.output))
            #expect(data != defaultData)
            #expect(inspector.streams.contains { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

            if name == "dark" {
                #expect(inspector.streams.map(\.body).joined(separator: "\n").contains("0.080 0.080 0.090 rg"))
            }
        }
    }

    @Test("Built-in themes keep text contrast above WCAG minimum")
    func builtInThemesKeepTextContrastAboveWCAGMinimum() {
        for theme in PDFOptions.Theme.builtInThemes {
            for role in PDFOptions.ElementRole.allCases {
                let style = theme.style(for: role)
                let background = style.backgroundColor ?? theme.pageBackground ?? theme.palette.background
                #expect(
                    contrastRatio(style.color, background) >= 4.5,
                    "Low contrast for \(role): \(style.color) on \(background)",
                )
            }

            let codeBackground = theme.style(for: .codeBlock).backgroundColor ?? theme.pageBackground ?? theme.palette.background
            for color in codeSyntaxColors(theme.codeSyntax) {
                #expect(contrastRatio(color, codeBackground) >= 4.5, "Low code contrast for \(color) on \(codeBackground)")
            }
        }
    }

    @Test("Custom code syntax theme controls token colors")
    func customCodeSyntaxThemeControlsTokenColors() throws {
        var theme = PDFOptions.Theme.default
        theme.codeSyntax.keyword = PDFColor(red: 0.7, green: 0.1, blue: 0.2)

        let data = try MarkdownPDFRenderer(
            options: PDFOptions(codeSyntaxHighlighting: .enabled, theme: theme),
        ).render(markdown: """
        ```swift
        let value = 1
        ```
        """)
        let stream = PDFInspector(data).streams.map(\.body).joined(separator: "\n")

        #expect(stream.contains("0.700 0.100 0.200 rg"))
        #expect(!stream.contains(sourceCodeKeywordOperator))
    }

    @Test("Unsupported code syntax coloring hints render plain")
    func unsupportedCodeSyntaxColoringHintsRenderPlain() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(codeSyntaxHighlighting: .enabled),
        ).render(markdown: """
        ```unknown-language
        plainBlock = "this block must remain uncolored"
        ```
        """)
        let stream = PDFInspector(data).streams.map(\.body).joined(separator: "\n")
        let textResult = try PDFValidation.pdftotext(data: data, name: "unsupported-code-coloring")

        try #require(textResult.exitCode == 0, "pdftotext failed for unsupported code coloring:\n\(textResult.output)")
        #expect(textResult.output.contains("plainBlock"))
        #expect(!textResult.output.contains("Unsupported"))
        #expect(!stream.contains(sourceCodeKeywordOperator))
        #expect(!stream.contains(sourceCodeCommentOperator))
        #expect(!stream.contains(sourceCodeStringOperator))
        #expect(!stream.contains(sourceCodeNumberOperator))
        #expect(!stream.contains(sourceCodeOperatorOperator))
    }

    @Test("Additional syntax coloring hints render colored tokens")
    func additionalSyntaxColoringHintsRenderColoredTokens() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(codeSyntaxHighlighting: .enabled),
        ).render(markdown: """
        ```bash
        if [ "$name" = "Ada" ]; then # shell
        fi
        ```

        ```yaml
        enabled: true # yaml
        ```

        ```xml
        <note id="a"><!-- xml --></note>
        ```

        ```pascal
        begin (* pascal *) value := 1; end
        ```

        ```lisp
        (defun value () ; lisp
          42)
        ```

        ```sql
        SELECT name FROM records -- sql
        ```
        """)
        let textResult = try PDFValidation.pdftotext(data: data, name: "additional-code-coloring")
        let stream = PDFInspector(data).streams.map(\.body).joined(separator: "\n")

        try #require(textResult.exitCode == 0, "pdftotext failed for additional code coloring:\n\(textResult.output)")
        #expect(textResult.output.contains("shell"))
        #expect(textResult.output.contains("pascal"))
        #expect(textResult.output.contains("SELECT"))
        #expect(stream.contains(sourceCodeKeywordOperator))
        #expect(stream.contains(sourceCodeCommentOperator))
        #expect(stream.contains(sourceCodeStringOperator))
        #expect(stream.contains(sourceCodeNumberOperator))
        #expect(stream.contains(sourceCodeOperatorOperator))
    }

    @Test("Mermaid keeps diagram path when syntax coloring is enabled")
    func mermaidKeepsDiagramPathWhenSyntaxColoringIsEnabled() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(codeSyntaxHighlighting: .enabled),
        ).render(markdown: """
        ```mermaid
        graph LR
            A["Input"] --> B["PDF"]
        ```
        """)
        let textResult = try PDFValidation.pdftotext(data: data, name: "syntax-coloring-mermaid")

        try #require(textResult.exitCode == 0, "pdftotext failed for Mermaid with syntax coloring:\n\(textResult.output)")
        #expect(textResult.output.contains("Input"))
        #expect(textResult.output.contains("PDF"))
        #expect(!textResult.output.contains("graph LR"))
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

    @Test("Embedded font renderer uses CJK format 12 advances for wrapping")
    func embeddedFontRendererUsesCJKFormat12AdvancesForWrapping() throws {
        let fontData = SyntheticTrueTypeFont.data(
            cmapFormat: 12,
            glyphProfile: .cjkWitness,
            includeGlyphOutlines: true,
        )
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "Public CJK")
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 90, height: 160),
                margins: PDFOptions.Margins(top: 20, right: 20, bottom: 20, left: 20),
                baseFontSize: 10,
                embeddedFonts: PDFOptions.EmbeddedFonts(regular: source),
                title: "CJK Format 12 Widths",
            ),
        ).render(markdown: "漢字語漢字語")
        let inspector = PDFInspector(data)
        let lineYCoordinates = textLineYCoordinates(in: inspector.text)

        #expect(inspector.text.contains("/Subtype /CIDFontType2"))
        #expect(inspector.text.contains("/W [1 [1000] 2 [1000] 3 [1000]]"))
        #expect(inspector.text.contains("<0001> <6F22>"))
        #expect(inspector.text.contains("<0002> <5B57>"))
        #expect(inspector.text.contains("<0003> <8A9E>"))
        #expect(lineYCoordinates.count == 2)

        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "cjk-format12-widths")
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        let textResult = try PDFValidation.pdftotext(data: data, name: "cjk-format12-widths-text")
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        #expect(textResult.output.filter { !$0.isWhitespace }.contains("漢字語漢字語"))
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
            ).render(markdown: "\u{0905}\u{0906}")
            Issue.record("Expected unsupported complex-script shaping error")
        } catch let error as PDFEmbeddedFontError {
            #expect(error == .unsupportedComplexScriptScalar(scalar: "\u{0905}"))
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

    @Test("Embedded font catalog parses MATH tables only when requested")
    func embeddedFontCatalogParsesMathTablesOnlyWhenRequested() throws {
        let fontData = SyntheticTrueTypeFont.data(
            glyphProfile: .latinWitness,
            includeGlyphOutlines: true,
            includeMATHTable: true,
        )
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "Public Math")
        let fonts = PDFOptions.EmbeddedFonts(regular: source)

        let defaultCatalog = try PDFEmbeddedFontCatalog(fonts: fonts)
        let mathCatalog = try PDFEmbeddedFontCatalog(fonts: fonts, parseMathTables: true)

        #expect(defaultCatalog.entry(for: .helvetica)?.resource.metadata.math == nil)
        #expect(defaultCatalog.entry(for: .helvetica)?.mathMetrics == nil)
        #expect(mathCatalog.entry(for: .helvetica)?.resource.metadata.math != nil)
        #expect(mathCatalog.entry(for: .helvetica)?.mathMetrics != nil)
    }

    @Test("Embedded font catalog does not eagerly parse malformed MATH tables")
    func embeddedFontCatalogDoesNotEagerlyParseMalformedMathTables() throws {
        let fontData = SyntheticTrueTypeFont.data(
            glyphProfile: .latinWitness,
            includeGlyphOutlines: true,
            includeMATHTable: true,
            invalidMATHConstantsOffset: true,
        )
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "Malformed Math")
        let fonts = PDFOptions.EmbeddedFonts(regular: source)

        _ = try PDFEmbeddedFontCatalog(fonts: fonts)
        #expect(throws: TrueTypeFontError.self) {
            _ = try PDFEmbeddedFontCatalog(fonts: fonts, parseMathTables: true)
        }
    }

    @Test("Display math uses embedded OpenType MATH metrics when available")
    func displayMathUsesEmbeddedOpenTypeMathMetricsWhenAvailable() throws {
        let defaultRule = try displayMathFractionRule(includeMATHTable: false)
        let mathRule = try displayMathFractionRule(includeMATHTable: true)

        #expect(mathRule.height > defaultRule.height + 0.5)
        #expect(mathRule.y != defaultRule.y)
    }

    @Test("Font-backed math profile requires an embedded MATH table")
    func fontBackedMathProfileRequiresEmbeddedMathTable() throws {
        #expect(throws: MarkdownPDFError.missingEmbeddedMathFont(font: "Helvetica")) {
            _ = try MarkdownPDFRenderer(
                options: PDFOptions(mathTypesetting: .fontBacked),
            ).render(markdown: "Inline $x^2$ must not silently use base fonts.")
        }

        let fontData = SyntheticTrueTypeFont.data(
            glyphProfile: .latinWitness,
            includeGlyphOutlines: true,
        )
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "Public Regular")

        #expect(throws: MarkdownPDFError.missingEmbeddedMathFont(font: "Public-Regular")) {
            _ = try MarkdownPDFRenderer(
                options: PDFOptions(
                    embeddedFonts: .allRoles(source),
                    mathTypesetting: .fontBacked,
                ),
            ).render(markdown: """
            $$
            \\frac{A}{B}
            $$
            """)
        }
    }

    @Test("Font-backed math profile renders with embedded MATH table")
    func fontBackedMathProfileRendersWithEmbeddedMathTable() throws {
        let fontData = SyntheticTrueTypeFont.data(
            glyphProfile: .latinWitness,
            includeGlyphOutlines: true,
            includeMATHTable: true,
        )
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "Public Math")
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 180),
                margins: PDFOptions.Margins(top: 24, right: 24, bottom: 24, left: 24),
                embeddedFonts: .allRoles(source),
                mathTypesetting: .fontBacked,
            ),
        ).render(markdown: """
        INLINE $X^A$ MATH

        $$
        \\frac{A}{B}
        $$
        """)
        let inspector = PDFInspector(data)
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "font-backed-math-profile")

        #expect(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        #expect(inspector.text.contains("/EF1"))
        #expect(inspector.text.contains("/FontFile2"))
        #expect(inspector.text.contains("/ActualText (frac\\(A, B\\))"))
        #expect(inspector.streams.map(\.body).joined(separator: "\n").contains("/EF1"))
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

    @Test(
        .enabled(
            if: OpenTrueTypeFontFixture.isAvailable,
            OpenTrueTypeFontFixture.skipReason,
        ),
    )
    func rendersMultilingualCorpusWithEmbeddedFont() throws {
        let fontURL = try #require(OpenTrueTypeFontFixture.url)
        let source = try PDFOptions.EmbeddedFontSource(data: Data(contentsOf: fontURL))
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/multilingual-corpus.md")
        let markdown = try String(contentsOf: fixtureURL, encoding: .utf8)
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(embeddedFonts: .allRoles(source), title: "Multilingual corpus"),
        ).render(markdown: markdown)
        let inspector = PDFInspector(data)

        #expect(inspector.text.contains("/Subtype /Type0"))
        #expect(inspector.text.contains("/FontFile2"))
        #expect(inspector.text.contains("/ToUnicode"))
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "multilingual-corpus")
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        let textResult = try PDFValidation.pdftotext(data: data, name: "multilingual-corpus-text")
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        let extracted = normalizedExtractedText(textResult.output)

        // Diacritic Latin, Cyrillic, and Greek are covered by the open CI fonts
        // (DejaVu Sans on Linux, Liberation Sans on macOS) and round-trip through
        // the subset and ToUnicode map.
        #expect(extracted.contains("café"), "Unexpected extraction:\n\(textResult.output)")
        #expect(extracted.contains("résumé"))
        #expect(extracted.contains("Привет"))
        #expect(extracted.contains("Καλημέρα"))
        // Complex tables keep their headers and mixed-script cells.
        #expect(extracted.contains("Script"))
        #expect(extracted.contains("Sample"))
        #expect(extracted.contains("Привет мир"))
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

    @Test("Renders Mermaid pie charts through native PDF path operators")
    func rendersMermaidPieChartsThroughNativePDFPathOperators() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        ```mermaid
        pie title Browser Share
            "Desktop" : 62
            "Mobile" : 31
            "Tablet" : 7
        ```
        """)
        let inspector = PDFInspector(data)
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")
        let textResult = try PDFValidation.pdftotext(data: data, name: "mermaid-pie-chart")

        #expect(streamText.contains(" c"))
        #expect(streamText.contains(" f"))
        #expect(!streamText.contains("(pie title Browser Share)"))
        #expect(textResult.exitCode == 0, "pdftotext failed for Mermaid pie chart:\n\(textResult.output)")
        #expect(textResult.output.contains("Browser Share"))
        #expect(textResult.output.contains("Desktop 62"))
        #expect(textResult.output.contains("Mobile 31"))
        #expect(!textResult.output.contains("Unsupported Mermaid diagram"))
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "Canonical PDF structure failed:\n\(inspector.canonicalStructureReport())",
        )
    }

    @Test("Renders native chart blocks and preserves labels")
    func rendersNativeChartBlocksAndPreservesLabels() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        ```chart
        type: bar
        title: Quarterly Revenue
        categories: Q1, Q2, Q3
        y-label: USD
        series: Actual = 3, 5, 4
        series: Forecast = 4, 6, 5
        ```

        ```chart
        type: line
        title: Adoption Trend
        categories: Jan, Feb, Mar
        x-label: month
        y-label: users
        series: Accounts = 2, 4, 7
        ```

        ```chart
        type: scatter
        title: Impact Map
        x-label: effort
        y-label: impact
        series: Trials = (1, 2), (2, 4), (4, 7)
        ```
        """)
        let inspector = PDFInspector(data)
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")
        let textResult = try PDFValidation.pdftotext(data: data, name: "native-chart-blocks")

        #expect(streamText.contains(" re f"))
        #expect(streamText.contains(" l"))
        #expect(streamText.contains(" c"))
        #expect(textResult.exitCode == 0, "pdftotext failed for native charts:\n\(textResult.output)")
        #expect(textResult.output.contains("Quarterly Revenue"))
        #expect(textResult.output.contains("Actual"))
        #expect(textResult.output.contains("Forecast"))
        #expect(textResult.output.contains("Adoption Trend"))
        #expect(textResult.output.contains("Accounts"))
        #expect(textResult.output.contains("Impact Map"))
        #expect(textResult.output.contains("Trials"))
        #expect(!textResult.output.contains("Unsupported chart"))
        #expect(
            inspector.canonicalStructureIssues().isEmpty,
            "Canonical PDF structure failed:\n\(inspector.canonicalStructureReport())",
        )
    }

    @Test("Falls back visibly for invalid native chart blocks")
    func fallsBackVisiblyForInvalidNativeChartBlocks() throws {
        let data = try MarkdownPDFRenderer().render(markdown: """
        ```chart
        type: heatmap
        title: Unsupported Density
        series: Values = 1, 2, 3
        ```
        """)
        let textResult = try PDFValidation.pdftotext(data: data, name: "unsupported-chart-block")

        #expect(textResult.exitCode == 0, "pdftotext failed for unsupported chart fallback:\n\(textResult.output)")
        #expect(textResult.output.contains("Unsupported chart"))
        #expect(textResult.output.contains("heatmap"))
        #expect(textResult.output.contains("Unsupported Density"))
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

    private func codeSyntaxColors(_ theme: PDFOptions.CodeSyntaxTheme) -> [PDFColor] {
        [
            theme.text,
            theme.keyword,
            theme.identifier,
            theme.string,
            theme.number,
            theme.comment,
            theme.operatorToken,
            theme.punctuation,
            theme.error,
        ]
    }

    private func contrastRatio(_ first: PDFColor, _ second: PDFColor) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: PDFColor) -> Double {
        0.2126 * linearizedSRGB(color.red)
            + 0.7152 * linearizedSRGB(color.green)
            + 0.0722 * linearizedSRGB(color.blue)
    }

    private func linearizedSRGB(_ channel: Double) -> Double {
        channel <= 0.03928
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }

    private func displayMathFractionRule(
        includeMATHTable: Bool,
        mathTypesetting: PDFOptions.MathTypesetting = .enabled,
    ) throws -> (y: Double, height: Double) {
        let fontData = SyntheticTrueTypeFont.data(
            glyphProfile: .latinWitness,
            includeGlyphOutlines: true,
            includeMATHTable: includeMATHTable,
        )
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "Public Math")
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 180),
                margins: PDFOptions.Margins(top: 24, right: 24, bottom: 24, left: 24),
                embeddedFonts: .allRoles(source),
                mathTypesetting: mathTypesetting,
            ),
        ).render(markdown: """
        $$
        \\frac{A}{B}
        $$
        """)
        let streamTokens = PDFInspector(data)
            .streams
            .map(\.body)
            .joined(separator: "\n")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        for index in streamTokens.indices where streamTokens[index] == "re" {
            let fillIndex = streamTokens.index(after: index)
            guard fillIndex < streamTokens.endIndex,
                  streamTokens[fillIndex] == "f",
                  index >= 4
            else {
                continue
            }

            let yIndex = streamTokens.index(index, offsetBy: -3)
            let heightIndex = streamTokens.index(before: index)
            guard let y = Double(streamTokens[yIndex]),
                  let height = Double(streamTokens[heightIndex])
            else {
                continue
            }
            return (y: y, height: height)
        }

        Issue.record("Expected display math to draw a filled fraction rule")
        return (y: 0, height: 0)
    }
}

private let sourceCodeKeywordOperator = "0.050 0.200 0.550 rg"
private let sourceCodeStringOperator = "0.500 0.180 0.050 rg"
private let sourceCodeNumberOperator = "0.340 0.180 0.550 rg"
private let sourceCodeCommentOperator = "0.280 0.380 0.280 rg"
private let sourceCodeOperatorOperator = "0.180 0.220 0.260 rg"

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
