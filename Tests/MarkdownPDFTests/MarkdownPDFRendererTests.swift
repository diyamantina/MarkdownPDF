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
    @Test("Unordered lists draw a bullet the bound font can actually paint")
    func unorderedListsDrawMarkers() throws {
        func embedded(_ profile: SyntheticTrueTypeFont.GlyphProfile) -> PDFOptions.EmbeddedFonts {
            let data = SyntheticTrueTypeFont.data(glyphProfile: profile, includeGlyphOutlines: true)
            return .allRoles(PDFOptions.EmbeddedFontSource(data: data, baseName: "Marker Witness"))
        }
        /// Embedded text is emitted as CID hex (`<0010> Tj`), never as a literal
        /// string, so counting text-showing operators is the only way to tell a
        /// drawn marker from an omitted one on that path.
        func showOperators(_ data: Data) -> Int {
            PDFInspector(data).text.components(separatedBy: " Tj").count - 1
        }

        // Base-14: WinAnsiEncoding maps U+2022 to 0x95, so each item paints a bullet.
        let base14 = try MarkdownPDFRenderer().render(markdown: "- alpha\n- beta\n")
        #expect(PDFInspector(base14).text.components(separatedBy: "(\\225) Tj").count - 1 == 2)

        // Ordered lists keep a numeric marker per item.
        let ordered = try PDFInspector(MarkdownPDFRenderer().render(markdown: "1. alpha\n2. beta\n")).text
        #expect(ordered.contains("(1.) Tj"))
        #expect(ordered.contains("(2.) Tj"))

        // Task items take the checkbox branch and must not also grow a bullet.
        let task = try MarkdownPDFRenderer().render(markdown: "- [x] done\n")
        #expect(!PDFInspector(task).text.contains("(\\225) Tj"))

        // Embedded font covering U+2022: marker plus body are two text objects.
        let withBullet = try MarkdownPDFRenderer(options: PDFOptions(embeddedFonts: embedded(.bulletWitness)))
            .render(markdown: "- ALPHA\n")
        #expect(showOperators(withBullet) == 2)

        // Embedded font covering `-` but not U+2022: the hyphen fallback draws,
        // so there are still two text objects, and the hyphen is a base-14-free
        // CID glyph rather than a literal.
        let withHyphen = try MarkdownPDFRenderer(options: PDFOptions(embeddedFonts: embedded(.hyphenWitness)))
            .render(markdown: "- ALPHA\n")
        #expect(showOperators(withHyphen) == 2)

        // Embedded font covering neither: the marker is omitted rather than
        // throwing missingGlyph, so exactly one text object remains, the body.
        let rtl = try MarkdownPDFRenderer(options: PDFOptions(embeddedFonts: embedded(.rtlWitness)))
            .render(markdown: "- ALPHA\n")
        #expect(showOperators(rtl) == 1)
        #expect(PDFInspector(rtl).hasValidXrefOffsets())
    }

    @Test("A list marker never separates from an image body across a page break")
    func unorderedMarkerStaysWithImageBody() throws {
        // renderStandaloneImage calls ensureSpace(drawHeight) of its own, so an item
        // whose body is a lone image can break the page after its marker is already
        // painted. renderList must reserve the figure's real height, not one line.
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/wwdc-2019-613-ray-tracing-with-metal/assets")
        let filler = String(repeating: "Filler paragraph.\n\n", count: 30)
        let markdown = filler + "- ![figure](2019_613_page-086.png)\n"

        let data = try MarkdownPDFRenderer().render(markdown: markdown, assetsBaseURL: directory)
        let inspector = PDFInspector(data)
        // The filler must actually push the figure onto a second page, otherwise
        // this test proves nothing.
        #expect(inspector.pageCount == 2)

        let bulletStreams = inspector.streams.filter { $0.body.contains("(\\225) Tj") }
        try #require(bulletStreams.count == 1, "expected exactly one bullet")
        // Same content stream means same page: the marker travelled with its figure.
        #expect(bulletStreams[0].body.contains(" Do"))
    }

    @Test("A base-14 marker is omitted rather than failing a conformance profile")
    func unorderedMarkerRespectsConformance() throws {
        let arial = SyntheticTrueTypeFont.data(glyphProfile: .bulletWitness, includeGlyphOutlines: true)
        // Only the regular role is embedded. A theme that draws the marker in bold
        // would reach for base-14 Helvetica-Bold, which PDF/UA-1 and PDF/A-2a forbid.
        let fonts = PDFOptions.EmbeddedFonts(regular: PDFOptions.EmbeddedFontSource(data: arial, baseName: "Witness"))
        var theme = PDFOptions.Theme.default
        var marker = theme.style(for: .listMarker)
        marker.fontRole = .bold
        theme.elements[.listMarker] = marker

        let conforming = PDFOptions(
            embeddedFonts: fonts,
            title: "Conformance",
            theme: theme,
            taggedPDF: .enabled,
            conformance: .pdfUA1AndPDFA2A,
        )
        // Renders at all: before the marker existed this document was valid, and a
        // decorative glyph must not be able to invalidate it.
        let data = try MarkdownPDFRenderer(options: conforming).render(markdown: "ALPHA\n\n- BETA\n")
        #expect(!PDFInspector(data).text.contains("(\\225) Tj"))

        // Without a conformance profile the same setup happily draws the base-14 bullet.
        let relaxed = PDFOptions(embeddedFonts: fonts, theme: theme)
        let plain = try MarkdownPDFRenderer(options: relaxed).render(markdown: "ALPHA\n\n- BETA\n")
        #expect(PDFInspector(plain).text.contains("(\\225) Tj"))
    }

    @Test("An HTML-comment page break starts a new page and never draws itself")
    func explicitPageBreaks() throws {
        func pageCount(_ markdown: String) throws -> Int {
            try PDFInspector(MarkdownPDFRenderer().render(markdown: markdown)).pageCount
        }

        #expect(try pageCount("A\n\nB\n") == 1)
        #expect(try pageCount("A\n\n<!-- pagebreak -->\n\nB\n") == 2)
        #expect(try pageCount("A\n\n<!-- pagebreak -->\n\nB\n\n<!-- pagebreak -->\n\nC\n") == 3)

        // Whitespace and case tolerance, matching how people actually type it.
        #expect(try pageCount("A\n\n<!--pagebreak-->\n\nB\n") == 2)
        #expect(try pageCount("A\n\n<!--   pageBreak   -->\n\nB\n") == 2)

        // A break is a separator, not content: leading, trailing, and repeated
        // breaks must never produce a blank page.
        #expect(try pageCount("<!-- pagebreak -->\n\nA\n") == 1)
        #expect(try pageCount("A\n\n<!-- pagebreak -->\n") == 1)
        #expect(try pageCount("A\n\n<!-- pagebreak -->\n\n<!-- pagebreak -->\n\nB\n") == 2)

        // The directive itself is consumed, never painted.
        let data = try MarkdownPDFRenderer().render(markdown: "A\n\n<!-- pagebreak -->\n\nB\n")
        #expect(!PDFInspector(data).text.contains("pagebreak"))

        // Any other HTML comment keeps its existing visible-text rendering.
        let other = try MarkdownPDFRenderer().render(markdown: "A\n\n<!-- note -->\n\nB\n")
        #expect(PDFInspector(other).text.contains("note"))
        #expect(try pageCount("A\n\n<!-- note -->\n\nB\n") == 1)
    }

    @Test("A block quote honors its theme role")
    func blockQuoteHonorsTheme() throws {
        let markdown = "Before.\n\n> quoted prose\n\nAfter.\n"

        var theme = PDFOptions.Theme.default
        var quote = theme.style(for: .blockQuote)
        quote.fontRole = .italic
        quote.color = PDFColor(red: 0.01, green: 0, blue: 0.27)
        quote.borderColor = PDFColor(red: 0, green: 0.82, blue: 0.59)
        theme.elements[.blockQuote] = quote

        let text = try PDFInspector(MarkdownPDFRenderer(options: PDFOptions(theme: theme))
            .render(markdown: markdown)).text

        // Body face and color come from the quote's own role.
        #expect(text.contains("/F3 11 Tf"))
        #expect(text.contains("0.010 0 0.270 rg"))
        // The left rule is stroked in the gutter the quote opens, 3pt in from the
        // page margin, well clear of the text at margin + 14.
        #expect(text.contains("0 0.820 0.590 RG"))
        #expect(text.contains("2 w 57 "))

        // Prose outside the quote keeps the body style.
        #expect(text.contains("0 0 0 rg"))
    }

    @Test("A quoted list marker takes the quote's color but keeps its own face")
    func quotedListMarkerTakesQuoteColor() throws {
        var theme = PDFOptions.Theme.default
        var quote = theme.style(for: .blockQuote)
        quote.fontRole = .italic
        quote.color = PDFColor(red: 0.01, green: 0, blue: 0.27)
        theme.elements[.blockQuote] = quote

        let text = try PDFInspector(MarkdownPDFRenderer(options: PDFOptions(theme: theme))
            .render(markdown: "> - item\n\n- outside\n")).text

        // The quoted bullet: quote color, regular face. Italicising a quote must not
        // italicise its bullets.
        #expect(text.contains("0.010 0 0.270 rg\nBT /F1 11 Tf 68 "))
        // The quoted item text: quote color, italic face.
        #expect(text.contains("0.010 0 0.270 rg\nBT /F3 11 Tf 92 "))
        // A bullet outside the quote is untouched.
        #expect(text.contains("0 0 0 rg\nBT /F1 11 Tf 54 "))

        // Ordered numbers are markers too.
        let ordered = try PDFInspector(MarkdownPDFRenderer(options: PDFOptions(theme: theme))
            .render(markdown: "> 1. item\n")).text
        #expect(ordered.contains("0.010 0 0.270 rg\nBT /F1 11 Tf 68 "))

        // So is a task checkbox, whose box and check are stroked from the same
        // `.listMarker` color.
        let task = try PDFInspector(MarkdownPDFRenderer(options: PDFOptions(theme: theme))
            .render(markdown: "> - [x] done\n")).text
        #expect(task.contains("0.010 0 0.270 RG"))
        #expect(!task.contains("0 0 0 RG"))
    }

    @Test("A block quote paints its background under its own text")
    func blockQuoteBackground() throws {
        var theme = PDFOptions.Theme.default
        var quote = theme.style(for: .blockQuote)
        quote.backgroundColor = PDFColor(red: 0.9, green: 0.9, blue: 1)
        theme.elements[.blockQuote] = quote
        let options = PDFOptions(theme: theme)

        // The fill is inserted, not appended: it must precede the quote's own text
        // in the content stream, or it would cover it.
        let text = try PDFInspector(MarkdownPDFRenderer(options: options)
            .render(markdown: "Above.\n\n> quoted prose\n\nAfter.\n")).text
        let fill = try #require(text.range(of: " re f Q"))
        let quoted = try #require(text.range(of: "(quoted "))
        #expect(fill.lowerBound < quoted.lowerBound)

        // It must not reach the text drawn above it on the same page.
        let aboveBaseline = 787.89
        let fillLine = try #require(text.split(separator: "\n").first { $0.contains(" re f Q") })
        let parts = fillLine.split(separator: " ")
        let fillY = try #require(Double(parts[6]))
        let fillHeight = try #require(Double(parts[8]))
        #expect(fillY + fillHeight < aboveBaseline)

        // Nested quotes stack: the outer fill is inserted last, so it is painted
        // first and the inner fill lands on top of it.
        let nested = try PDFInspector(MarkdownPDFRenderer(options: options)
            .render(markdown: "> outer\n>\n> > inner\n")).text
        let fills = nested.split(separator: "\n").filter { $0.contains(" re f Q") }
        try #require(fills.count == 2)
        let outerX = try #require(Double(fills[0].split(separator: " ")[5]))
        let innerX = try #require(Double(fills[1].split(separator: " ")[5]))
        #expect(outerX < innerX)

        // One fill per page the quote spans.
        let long = "> " + (1 ... 60).map { "line \($0)" }.joined(separator: "\n>\n> ") + "\n"
        let spanning = try PDFInspector(MarkdownPDFRenderer(options: options).render(markdown: long))
        #expect(spanning.pageCount >= 2)
        #expect(spanning.text.components(separatedBy: " re f Q").count - 1 == spanning.pageCount)

        // Tagged output marks the fill as an artifact, or PDF/UA-1 rejects it.
        let tagged = try PDFInspector(MarkdownPDFRenderer(options: PDFOptions(
            title: "Quote",
            theme: theme,
            taggedPDF: .enabled,
        )).render(markdown: "> quoted\n")).text
        #expect(tagged.contains("q /Artifact BMC"))

        // A theme without a background emits no fill at all.
        let plain = try PDFInspector(MarkdownPDFRenderer().render(markdown: "> quoted\n")).text
        #expect(!plain.contains(" re f Q"))

        // The quote fill goes above the page background, not under it. The dark
        // theme paints one, so its rectangle must be emitted first.
        var dark = PDFOptions.Theme.dark
        var darkQuote = dark.style(for: .blockQuote)
        darkQuote.backgroundColor = PDFColor(red: 0.9, green: 0.9, blue: 1)
        dark.elements[.blockQuote] = darkQuote
        let layered = try PDFInspector(MarkdownPDFRenderer(options: PDFOptions(theme: dark))
            .render(markdown: "> quoted\n")).text
        let pageBackground = try #require(layered.range(of: "re f\n"))
        let quoteFill = try #require(layered.range(of: " re f Q"))
        #expect(pageBackground.lowerBound < quoteFill.lowerBound)
    }

    @Test("A themeless block quote draws no rule and no recolor")
    func blockQuoteWithoutThemeIsUnchanged() throws {
        // The built-in themes set no `borderColor`, so default output must not
        // gain a stroke. This is the byte-stability guarantee for existing users.
        let markdown = "Before.\n\n> quoted prose\n\nAfter.\n"
        let text = try PDFInspector(MarkdownPDFRenderer().render(markdown: markdown)).text

        #expect(!text.contains(" RG"))
        #expect(!text.contains(" l S"))
        // Regular face throughout: no italic switch.
        #expect(!text.contains("/F3"))
    }

    @Test("The quote rule brackets its text, stays inside the margin, and never orphans")
    func blockQuoteRuleGeometry() throws {
        var theme = PDFOptions.Theme.default
        var quote = theme.style(for: .blockQuote)
        quote.borderColor = PDFColor(red: 1, green: 0, blue: 0)
        theme.elements[.blockQuote] = quote
        let options = PDFOptions(theme: theme)

        func ruleSegments(_ body: String) -> [(top: Double, bottom: Double)] {
            body.split(separator: "\n").compactMap { line in
                let parts = line.split(separator: " ")
                // `2 w 57 787.890 m 57 769.300 l S`
                guard parts.count == 9, parts[1] == "w", parts[4] == "m",
                      parts[7] == "l", parts[8] == "S",
                      let top = Double(parts[3]), let bottom = Double(parts[6])
                else { return nil }
                return (top, bottom)
            }
        }

        // The rule starts at the top of the first line's box, not at its baseline.
        // Starting at the baseline hangs the whole ascender above the rule.
        let single = try PDFInspector(MarkdownPDFRenderer(options: options).render(markdown: "> quoted prose\n"))
        let baseline = 782.94
        let segment = try #require(ruleSegments(single.text).first)
        #expect(segment.top > baseline)

        // `y` carries the last block's trailing spacing, which can dip below the
        // bottom margin without forcing a page break. The rule must not follow it.
        let deep = String(repeating: "Filler.\n\n", count: 28)
            + "```\n" + String(repeating: "code\n", count: 9) + "```\n\n> one\n>\n> two\n"
        let clamped = try PDFInspector(MarkdownPDFRenderer(options: options).render(markdown: deep))
        for segment in ruleSegments(clamped.text) {
            #expect(segment.bottom >= PDFOptions.Margins.standard.bottom)
        }

        // A quote whose first block reserves more than one line (a heading, a code
        // fence) must not break the page after the rule's origin was captured, or
        // page 1 keeps a rule with no quote content beside it.
        for opening in ["# Quoted Heading", "```\n> code\n> code\n> ```"] {
            let markdown = String(repeating: "Filler.\n\n", count: 36)
                + "> \(opening)\n>\n> quoted body\n"
            let inspector = try PDFInspector(MarkdownPDFRenderer(options: options).render(markdown: markdown))
            let pages = inspector.streams.filter { $0.body.contains(" Tj") || $0.body.contains(" l S") }
            for page in pages {
                let hasRule = page.body.contains(" l S")
                let hasQuote = page.body.lowercased().contains("(quoted")
                #expect(!hasRule || hasQuote, "a rule was drawn on a page with no quote content")
            }
        }
    }

    @Test("Rule and quote content appear on exactly the same pages", arguments: [
        "# Quoted Heading",
        "```\n> code\n> code\n> ```",
        "| a | b |\n> |---|---|\n> | 1 | 2 |",
        "```mermaid\n> flowchart LR\n>     A[Apps] --> B[Features]\n> ```",
        "---",
        "$$\\frac{a}{b}$$",
    ])
    func quoteRuleTracksItsContent(_ opening: String) throws {
        var theme = PDFOptions.Theme.default
        var quote = theme.style(for: .blockQuote)
        quote.borderColor = PDFColor(red: 1, green: 0, blue: 0)
        theme.elements[.blockQuote] = quote
        let options = PDFOptions(mathTypesetting: .enabled, theme: theme)

        // Body text outside a quote sits at the left margin, 54. A quote indents by
        // 14, so anything drawn at or past 68 is the quote's own content. Figures use
        // `Do`, and a quoted rule or math bar is a path starting at 68.
        let gutter = PDFOptions.Margins.standard.left + 14

        // One filler count is not enough: whether the first block breaks the page
        // depends on exactly how full the page is, so the interesting window is a
        // few paragraphs wide and a hardcoded value slides straight past it.
        for fillerCount in 30 ... 40 {
            let markdown = String(repeating: "Filler.\n\n", count: fillerCount)
                + "> \(opening)\n>\n> quoted body\n"
            let inspector = try PDFInspector(MarkdownPDFRenderer(options: options).render(markdown: markdown))

            for page in inspector.streams where page.body.contains(" Tj") || page.body.contains(" S") {
                let hasRule = page.body.contains("2 w \(Int(gutter - 11)) ")
                let hasQuoteContent = page.body.split(separator: "\n").contains { line in
                    if line.contains(" Do") { return true }
                    let parts = line.split(separator: " ")
                    // A quoted path: `0.750 w 68 75.900 m ...`
                    if parts.count > 3, parts.contains("m"), let x = Double(parts[2]), x >= gutter { return true }
                    guard parts.count > 6, parts[6] == "Td", let x = Double(parts[4]) else { return false }
                    return x >= gutter
                }
                #expect(
                    hasRule == hasQuoteContent,
                    "filler \(fillerCount), opening \(opening.prefix(12)): rule=\(hasRule) content=\(hasQuoteContent)",
                )
            }
        }
    }

    @Test("Nested quotes stack their rules, and the rule is a tagged artifact")
    func blockQuoteRuleNestsAndIsAnArtifact() throws {
        var theme = PDFOptions.Theme.default
        var quote = theme.style(for: .blockQuote)
        quote.borderColor = PDFColor(red: 0, green: 0.82, blue: 0.59)
        theme.elements[.blockQuote] = quote

        // Each quote opens a fresh 14pt gutter, so the inner rule sits 14pt right
        // of the outer one: 54+3 and 68+3.
        let nested = try PDFInspector(MarkdownPDFRenderer(options: PDFOptions(theme: theme))
            .render(markdown: "> outer\n>\n> > inner\n")).text
        #expect(nested.contains("2 w 57 "))
        #expect(nested.contains("2 w 71 "))

        // The rule is decoration. Under a tagged PDF it must be an artifact, or it
        // becomes untagged page content and fails PDF/UA-1.
        let tagged = try PDFInspector(MarkdownPDFRenderer(options: PDFOptions(
            title: "Quote",
            theme: theme,
            taggedPDF: .enabled,
        )).render(markdown: "> quoted\n")).text
        #expect(tagged.contains("/Artifact BMC"))
    }

    @Test("A block quote rule follows the quote across a page break")
    func blockQuoteRuleSpansPages() throws {
        var theme = PDFOptions.Theme.default
        var quote = theme.style(for: .blockQuote)
        quote.borderColor = PDFColor(red: 1, green: 0, blue: 0)
        theme.elements[.blockQuote] = quote

        let body = (1 ... 60).map { "quoted line \($0)" }.joined(separator: "\n\n> ")
        let markdown = "> \(body)\n"
        let data = try MarkdownPDFRenderer(options: PDFOptions(theme: theme)).render(markdown: markdown)
        let inspector = PDFInspector(data)
        try #require(inspector.pageCount >= 2, "the quote must span pages for this test to mean anything")

        // One rule segment per page the quote touches, never zero on a later page.
        let segments = inspector.streams
            .filter { $0.body.contains(" Tj") }
            .map { $0.body.components(separatedBy: " l S").count - 1 }
        #expect(segments.allSatisfy { $0 >= 1 })
        #expect(segments.count == inspector.pageCount)
    }

    @Test("Deep list nesting cannot explode the page count")
    func deepListIndentIsClamped() throws {
        /// Unclamped, each level added 24pt of indent; past the page width the content
        /// column went negative, every token landed on its own near-empty page, and a
        /// few KB of markdown produced hundreds of pages. The indent is now capped so
        /// the page count stays roughly linear in the input.
        func pageCount(depth: Int) throws -> Int {
            let markdown = (0 ..< depth)
                .map { String(repeating: "  ", count: $0) + "- item \($0)" }
                .joined(separator: "\n")
            return try PDFInspector(MarkdownPDFRenderer().render(markdown: markdown)).pageCount
        }

        // On main this was ~81 pages; clamped it is a handful.
        let hundred = try pageCount(depth: 100)
        #expect(hundred < 15, "100-deep list produced \(hundred) pages")

        // Shallow, realistic nesting is untouched: three levels fit one page.
        #expect(try pageCount(depth: 3) == 1)

        /// Block quotes indent through the same clamp. A list of deep quotes, or
        /// quotes interleaved with lists, otherwise pushed the content column off the
        /// page and every glyph landed outside the MediaBox, invisible.
        func offPageTextOps(_ markdown: String) throws -> Int {
            let text = try PDFInspector(MarkdownPDFRenderer().render(markdown: markdown)).text
            let rightEdge = PDFOptions.PageSize.a4.width - PDFOptions.Margins.standard.right
            return text.split(separator: "\n").count(where: { line in
                let parts = line.split(separator: " ")
                guard parts.count > 6, parts[6] == "Td", line.contains("Tj"),
                      let x = Double(parts[4]) else { return false }
                return x > rightEdge + 0.5
            })
        }
        let tokens = (0 ..< 400).map { "tok\($0)" }.joined(separator: " ")
        // 16 list levels then 16 quote levels, within the parser's depth cap.
        let listThenQuote = String(repeating: "- ", count: 16)
            + String(repeating: "> ", count: 16) + tokens
        #expect(try offPageTextOps(listThenQuote) == 0, "content drawn off the page")
        // Quotes alternating with lists.
        let alternating = String(repeating: "> - ", count: 16) + tokens
        #expect(try offPageTextOps(alternating) == 0, "content drawn off the page")
    }

    @Test("A byte-order mark in text does not abort the render")
    func byteOrderMarkIsStripped() throws {
        // U+FEFF classified as an Arabic presentation form and threw
        // `unsupportedComplexScriptScalar` under an embedded font, aborting the whole
        // render; the base-14 path drew it as `?`. It is invisible formatting and is
        // stripped before it reaches either path.
        // Stripped at the scalar level, so a BOM fused into a composed grapheme
        // (`\u{FEFF}\u{0301}`) is removed too; a grapheme-aware replace would leave
        // it. This is font-independent, so it uses no glyphs.
        for input in ["AB\u{FEFF}CD", "AB\u{FEFF}\u{0301}CD", "A\u{FEFF}\u{FEFF}B", "\u{FEFF}\u{0301}x"] {
            let run = PDFTextRun(text: input, font: .helvetica, size: 10)
            #expect(!run.text.unicodeScalars.contains("\u{FEFF}"), "BOM survived in \(input.debugDescription)")
        }

        // Embedded font: previously threw. Now renders. Inputs use only glyphs the
        // synthetic witness font provides (uppercase Latin).
        let witness = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let embedded = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: witness, baseName: "Witness"),
        ))
        for input in ["AB\u{FEFF}CD", "\u{FEFF}HELLO", "\u{FEFF}", "A\u{FEFF}\u{FEFF}B"] {
            let data = try MarkdownPDFRenderer(options: embedded).render(markdown: input)
            #expect(!data.isEmpty)
        }

        // Base-14: the BOM is not painted as `?`, and the surrounding text survives.
        let text = try PDFInspector(MarkdownPDFRenderer().render(markdown: "AB\u{FEFF}CD")).text
        #expect(!text.contains("(?) Tj"))
        #expect(text.contains("(ABCD)") || text.contains("(AB)"))
    }

    @Test("Invisible default-ignorable format controls never abort an embedded-font render", arguments: [
        "\u{200B}", // ZERO WIDTH SPACE
        "\u{200C}", // ZERO WIDTH NON-JOINER
        "\u{200D}", // ZERO WIDTH JOINER
        "\u{2060}", // WORD JOINER
        "\u{00AD}", // SOFT HYPHEN
        "\u{034F}", // COMBINING GRAPHEME JOINER
        "\u{FEFF}", // BYTE ORDER MARK
        "\u{FE0F}", // VARIATION SELECTOR-16
        "\u{3164}", // HANGUL FILLER
        "\u{E0041}", // TAG LATIN CAPITAL LETTER A
        "\u{200D}\u{200D}", // a doubled control, adjacent
    ])
    func invisibleFormatControlsDoNotAbortEmbeddedRender(_ control: String) throws {
        // Follow-up to the BOM fix (#27): under an embedded font whose cmap lacks
        // them, every one of these threw `missingGlyph` and aborted the whole
        // document. Per Unicode they are default-ignorable and semantically inert,
        // so they render invisibly. They are stripped before either font path sees
        // them.
        let input = "AB\(control)CD"

        // The run text is clean, so measurement and encoding never see the control.
        let run = PDFTextRun(text: input, font: .helvetica, size: 10)
        #expect(run.text == "ABCD", "control survived in \(input.debugDescription): \(run.text.debugDescription)")

        // Embedded font: previously aborted. Now renders. The witness font provides
        // only uppercase Latin, so ABCD is the whole visible payload.
        let witness = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let embedded = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: witness, baseName: "Witness"),
        ))
        let data = try MarkdownPDFRenderer(options: embedded).render(markdown: input)
        #expect(!data.isEmpty)

        // Base-14: the control is not painted as `?`, and the surrounding text survives.
        let text = try PDFInspector(MarkdownPDFRenderer().render(markdown: input)).text
        #expect(!text.contains("(?) Tj"), "control painted as ? for \(input.debugDescription)")
    }

    @Test("Semantically load-bearing controls are preserved, not stripped as invisible", arguments: [
        "\u{061C}", // ARABIC LETTER MARK (bidi)
        "\u{200E}", // LEFT-TO-RIGHT MARK (bidi)
        "\u{200F}", // RIGHT-TO-LEFT MARK (bidi)
        "\u{202A}", // LEFT-TO-RIGHT EMBEDDING (bidi)
        "\u{202E}", // RIGHT-TO-LEFT OVERRIDE (bidi)
        "\u{2066}", // LEFT-TO-RIGHT ISOLATE (bidi)
        "\u{2069}", // POP DIRECTIONAL ISOLATE (bidi)
        "\u{2028}", // LINE SEPARATOR (Zl, a word boundary)
        "\u{2029}", // PARAGRAPH SEPARATOR (Zp, a word boundary)
        "\u{FFF9}", // INTERLINEAR ANNOTATION ANCHOR (ruby delimiter)
    ])
    func loadBearingControlsSurviveTheStrip(_ control: String) throws {
        // These are default-ignorable for glyph purposes but drive ordering,
        // word boundaries, or annotation structure. Stripping them changes meaning:
        // a bidi control silently reorders, and a separator fuses the words it
        // split. The strip must leave them for the layer that owns them.
        let scalar = try #require(control.unicodeScalars.first)
        let run = PDFTextRun(text: "AB\(control)CD", font: .helvetica, size: 10)
        #expect(run.text.unicodeScalars.contains(scalar), "\(control.debugDescription) was wrongly stripped")
    }

    @Test("A line separator between words is not fused into one word")
    func lineSeparatorDoesNotFuseWords() {
        // U+2028 is a word boundary. Deleting it would turn "foo bar" into "foobar",
        // changing both the painted glyphs and the extracted text.
        let run = PDFTextRun(text: "foo\u{2028}bar", font: .helvetica, size: 10)
        #expect(run.text == "foo\u{2028}bar")
    }

    @Test("An explicit bidi control still refuses ordering rather than reordering wrongly")
    func explicitBidiControlStillRefuses() {
        // The strip must not defang BidiParagraphOrdering's correct-or-refuse
        // posture: an RLO inside a paragraph with RTL text has no supported
        // ordering, so the engine refuses instead of painting a UBA-divergent order.
        #expect(throws: BidiParagraphOrdering.ValidationError.self) {
            _ = try BidiParagraphOrdering().order("abc \u{202E}xy\u{202C} \u{05D0}\u{05D1}")
        }
    }

    @Test("A visible scalar the embedded font lacks renders as notdef, not a whole-document abort", arguments: [
        "\u{1F600}", // GRINNING FACE (emoji the witness font has no glyph for)
        "\u{4E2D}", // CJK 中
        "\u{2211}", // N-ARY SUMMATION
    ])
    func missingVisibleGlyphFallsBackToNotdef(_ missing: String) throws {
        // Under an embedded font whose cmap lacks the scalar, `TrueTypeGlyphMapper`
        // with the default `.reject` policy threw `missingGlyph` and dropped the
        // whole document. The render path now maps that one scalar to the font's
        // `.notdef` glyph so the rest of the page survives.
        let witness = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let source = PDFOptions.EmbeddedFontSource(data: witness, baseName: "Witness")
        let embedded = PDFOptions(embeddedFonts: .allRoles(source))

        let data = try MarkdownPDFRenderer(options: embedded).render(markdown: "AB\(missing)CD")
        #expect(!data.isEmpty)

        // The surrounding text and the ToUnicode span survive, so the page is a real
        // document, not an aborted stub.
        let inspector = try PDFInspector(data)
        #expect(inspector.text.contains("/ToUnicode"))
        let extracted = try PDFValidation.pdftotext(data: data, name: "notdef-actual-text").output
        #expect(extracted.contains("AB\(missing)CD"))
    }

    @Test("Several distinct missing scalars in one run do not collide at notdef's code 0")
    func multipleMissingScalarsShareNotdefWithoutToUnicodeConflict() throws {
        // Every missing scalar resolves to the .notdef glyph (id 0) and so shares
        // PDF character code 0. Because distinct missing scalars carry distinct
        // Unicode values, emitting a ToUnicode entry for each threw
        // `conflictingToUnicodeMapping(code: 0, ...)`. The notdef glyphs must
        // contribute no ToUnicode mapping. The witness font is uppercase-only, so
        // the lowercase letters and the emoji and the CJK glyph are all missing.
        let witness = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let embedded = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: witness, baseName: "Witness"),
        ))
        let data = try MarkdownPDFRenderer(options: embedded).render(markdown: "AB\u{1F600}CD emoji then \u{4E2D} cjk tail")
        #expect(!data.isEmpty)

        // The uppercase letters the font does draw still recover through ToUnicode.
        let inspector = try PDFInspector(data)
        #expect(inspector.text.contains("/ToUnicode"))
        let extracted = try PDFValidation.pdftotext(data: data, name: "multiple-notdef-actual-text").output
        #expect(extracted.contains("AB😀CD emoji then 中 cjk tail"))
    }

    @Test("A font resource that draws only notdef renders without trapping on an empty ToUnicode")
    func allNotdefUsageDoesNotTrapOnEmptyToUnicode() throws {
        // When every scalar a font resource is asked to draw is missing from its
        // cmap, the resource has no real glyph and so no ToUnicode mapping. Building
        // the CMap unconditionally trapped on its non-empty precondition (an
        // uncatchable crash, worse than the pre-fix thrown error). The witness font
        // is uppercase-only, so "xyz" is entirely notdef.
        let witness = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let embedded = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: witness, baseName: "Witness"),
        ))
        let data = try MarkdownPDFRenderer(options: embedded).render(markdown: "xyz")
        #expect(!data.isEmpty)

        // The all-notdef font carries no `/ToUnicode`, which is legal in a plain PDF.
        let inspector = try PDFInspector(data)
        #expect(!inspector.text.contains("/ToUnicode"))
        let extracted = try PDFValidation.pdftotext(data: data, name: "all-notdef-actual-text").output
        #expect(extracted.contains("xyz"))
    }

    @Test("A conformance profile refuses a missing glyph rather than drawing notdef", arguments: [
        PDFOptions.Conformance.pdfUA1,
        PDFOptions.Conformance.pdfA2A,
    ])
    func conformanceRefusesMissingGlyphInsteadOfNotdef(_ conformance: PDFOptions.Conformance) throws {
        // PDF/UA-1 and PDF/A-2a forbid referencing the .notdef glyph in content and
        // require a Unicode mapping for every code, so drawing notdef would ship
        // spec-violating output under a conformance claim. The render must refuse.
        let witness = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let options = PDFOptions(
            embeddedFonts: .allRoles(PDFOptions.EmbeddedFontSource(data: witness, baseName: "Witness")),
            title: "Conformance",
            taggedPDF: .enabled,
            conformance: conformance,
        )
        #expect(throws: (any Error).self) {
            _ = try MarkdownPDFRenderer(options: options).render(markdown: "AB\u{1F600}CD")
        }

        // The same document with no missing glyph still renders under conformance,
        // so it is the missing glyph, not the conformance setup, that refuses.
        let clean = try MarkdownPDFRenderer(options: options).render(markdown: "ABCD")
        #expect(!clean.isEmpty)
    }

    @Test("The notdef render fallback does not weaken the strict coverage probe")
    func notdefFallbackKeepsCoverageProbeStrict() throws {
        // covers() drives math-symbol transliteration and must keep reporting a
        // missing glyph as uncovered even though the render path now tolerates it.
        let witness = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let source = PDFOptions.EmbeddedFontSource(data: witness, baseName: "Witness")
        let catalog = try PDFEmbeddedFontCatalog(fonts: PDFOptions.EmbeddedFonts(regular: source))

        #expect(catalog.covers("A", font: .helvetica))
        #expect(!catalog.covers("\u{1F600}", font: .helvetica))
        #expect(!catalog.covers("\u{2211}", font: .helvetica))
    }

    @Test("The base-14 path NFC-normalizes decomposed diacritics to a WinAnsi byte")
    func base14NFCNormalizesDecomposedDiacritics() {
        // A decomposed diacritic (base + combining mark) drew the mark as `?` because
        // the mark is not a WinAnsi code point. NFC folds it to the precomposed
        // scalar, which is one WinAnsi byte. See #37.
        //
        // Compare UnicodeScalar arrays, not Strings: Swift `String ==`/`contains` use
        // canonical equivalence, so `"cafe\u{0301}" == "caf\u{00E9}"` is already true
        // and a String assertion would pass even without the fix.

        // Width scalars track the drawn form: one representable scalar, not base + `?`.
        #expect(PDFTextEncoding.portableScalars(for: "cafe\u{0301}") == ["c", "a", "f", "\u{00E9}"])
        #expect(PDFTextEncoding.portableScalars(for: "nin\u{0303}o") == ["n", "i", "\u{00F1}", "o"])
        #expect(PDFTextEncoding.portableScalars(for: "s\u{030C}") == ["\u{0161}"]) // s + caron -> š (CP1252 0x9A)
        #expect(PDFTextEncoding.portableScalars(for: "u\u{0308}ber") == ["\u{00FC}", "b", "e", "r"])

        // Already-precomposed text and plain ASCII are unchanged (idempotent).
        #expect(PDFTextEncoding.portableScalars(for: "caf\u{00E9}") == ["c", "a", "f", "\u{00E9}"])
        #expect(PDFTextEncoding.portableScalars(for: "hello") == ["h", "e", "l", "l", "o"])

        // A character with no WinAnsi precomposed form stays `?` on base-14 (needs an
        // embedded font); NFC does not invent a glyph.
        #expect(PDFTextEncoding.portableScalars(for: "\u{010D}") == ["?"]) // Croatian č

        // Byte emission: the decomposed form serializes to the same WinAnsi bytes as
        // the precomposed form, and never emits the `?` fallback byte (0x3F). The
        // serialized output is pure ASCII, so this String compare is byte-exact.
        #expect(PDFSyntax.LiteralString("cafe\u{0301}").serialized == PDFSyntax.LiteralString("caf\u{00E9}").serialized)
        #expect(!PDFSyntax.LiteralString("cafe\u{0301}").serialized.contains("?"))
    }

    @Test("NFC normalization does not touch the embedded path's run text")
    func nfcDoesNotAlterEmbeddedRunText() {
        // The embedded shaper reads run.text directly and attaches the combining mark
        // itself, so the run text must stay decomposed. Compare scalar arrays, since
        // String equality would not distinguish the decomposed and precomposed forms.
        let run = PDFTextRun(text: "cafe\u{0301}", font: .helvetica, size: 10)
        #expect(Array(run.text.unicodeScalars) == ["c", "a", "f", "e", "\u{0301}"])
    }

    @Test("Document strings (outline and Info title) NFC-normalize like page content")
    func documentStringsNFCNormalize() throws {
        // The outline/Info `/Title`, named destinations, and tagged `Alt` are
        // LiteralStrings that bypass the run path, so before the byte-boundary fix a
        // decomposed diacritic in a heading or title still degraded to `?` in the
        // bookmark while the page body rendered `é`. See #37.
        let options = PDFOptions(title: "Caf\u{0065}\u{0301} Title", tableOfContents: .enabled)
        let data = try MarkdownPDFRenderer(options: options).render(markdown: "# Caf\u{0065}\u{0301} Heading\n\nBody text.")
        // Read the raw PDF as Latin-1 so high bytes survive and the ASCII `Cafe?`
        // fallback, if present anywhere (title, outline, body), is detectable.
        let raw = String(String.UnicodeScalarView(data.map { UnicodeScalar($0) }))
        #expect(!raw.contains("Cafe?"), "a decomposed diacritic degraded to ? in a document string")
    }

    @Test("An embedded font from a .ttc collection renders via its selected face")
    func embeddedCollectionFontRenders() throws {
        // Before this, a TrueType collection was rejected outright; a user could not
        // embed a system CJK/Arabic/Hebrew font (those ship as collections). The
        // source now carries a face index (default 0). See #41.
        // A real 2-face collection; embed the second face (its directory is not at
        // offset 0), exercising the non-first-face path end to end.
        let collection = SyntheticTrueTypeFont.makeCollection(faces: [
            SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true),
            SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true),
        ])
        let embedded = PDFOptions(embeddedFonts: .allRoles(
            PDFOptions.EmbeddedFontSource(data: collection, baseName: "Collection", faceIndex: 1),
        ))
        let data = try MarkdownPDFRenderer(options: embedded).render(markdown: "ABCD")
        #expect(!data.isEmpty)
        let inspector = try PDFInspector(data)
        #expect(inspector.text.contains("/FontFile2")) // the selected face was embedded
    }

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

    @Test("Unresolvable image degrades to a placeholder instead of failing the document")
    func unresolvableImageDegradesInsteadOfThrowing() throws {
        // A site-absolute path with no asset root, and an undecodable format
        // (SVG), must not fail the whole render. See issue #211.
        let markdown = """
        # Heading

        ![hero](/assets/hero.svg)

        Body text after the image.
        """
        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let inspector = PDFInspector(data)
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "unresolvable-image")
        let textResult = try PDFValidation.pdftotext(data: data, name: "unresolvable-image-text")
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        let extracted = normalizedExtractedText(textResult.output)

        #expect(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        // The document still renders: heading and body survive.
        #expect(extracted.contains("Heading"))
        #expect(extracted.contains("Body text after the image"))
        // The image degraded to a visible placeholder rather than throwing.
        #expect(extracted.contains("[Image: hero]"))
        #expect(inspector.hasValidXrefOffsets())
    }

    @Test("Math spacing commands typeset in display and inline math without falling back")
    func mathSpacingCommandsTypeset() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(mathTypesetting: .enabled),
        ).render(markdown: """
        Inline $a \\quad b \\, c$ stays in the paragraph.

        $$
        x \\quad y \\qquad z \\, p \\: q \\; r \\! s
        $$
        """)
        let inspector = PDFInspector(data)
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "math-spacing")
        let textResult = try PDFValidation.pdftotext(data: data, name: "math-spacing-text")
        let mupdf = try PDFValidation.mutoolStructuredText(data: data, name: "math-spacing-mupdf")
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        try #require(mupdf.exitCode == 0, "mutool failed:\n\(mupdf.output)")
        let extracted = normalizedExtractedText(textResult.output)
        let structured = try MuPDFStructuredText(xml: mupdf.output)

        #expect(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        // No spacing command leaked as visible LaTeX source (no formula fallback).
        #expect(!extracted.contains("quad"), "Spacing fell back to source:\n\(textResult.output)")
        #expect(extracted.contains("stays in the paragraph"))
        // The negative thin space (\!) and the positive spaces produce no corrupt
        // or flipped character quads.
        #expect(
            structured.characterQuadIssues().isEmpty,
            "spacing produced bad quads:\n\(structured.characterQuadIssues().joined(separator: "\n"))",
        )
        #expect(inspector.hasValidXrefOffsets())
    }

    @Test("A larger math space pushes following content further right")
    func mathSpacingWidensOutput() throws {
        func rightmostGlyphX(_ markdown: String, name: String) throws -> Double {
            let data = try MarkdownPDFRenderer(options: PDFOptions(mathTypesetting: .enabled))
                .render(markdown: markdown)
            let mupdf = try PDFValidation.mutoolStructuredText(data: data, name: name)
            try #require(mupdf.exitCode == 0, "mutool failed:\n\(mupdf.output)")
            let structured = try MuPDFStructuredText(xml: mupdf.output)
            return structured.pages.flatMap(\.lines).flatMap(\.glyphs)
                .filter { !$0.isWhitespace }
                .map(\.box.right)
                .max() ?? 0
        }

        // The same formula with a wider gap pushes its trailing glyph further right.
        let quad = try rightmostGlyphX("$$a \\quad b$$", name: "math-space-quad")
        let qquad = try rightmostGlyphX("$$a \\qquad b$$", name: "math-space-qquad")
        #expect(qquad > quad + 1, "qquad (\(qquad)) should exceed quad (\(quad)) by at least the extra em")
    }

    @Test("Inline fractions and radicals typeset as 2D boxes in the text flow")
    func inlineFractionsTypesetAsBoxes() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(mathTypesetting: .enabled),
        ).render(markdown: "Pressure is $\\frac{a}{b}$, the bound is $\\sqrt{x}$, and a power $x^{\\frac{1}{2}}$ inline.")
        let inspector = PDFInspector(data)
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "inline-math-box")
        let textResult = try PDFValidation.pdftotext(data: data, name: "inline-math-box-text")
        try #require(textResult.exitCode == 0, "pdftotext failed:\n\(textResult.output)")
        let extracted = normalizedExtractedText(textResult.output)

        #expect(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        // The inline fraction bar, radical overbar, and the fraction nested inside
        // the superscript each emit rule rectangles in the text flow rather than
        // the parenthesized prose fallback. The superscript fraction proves the
        // box survives the scripts reconstruction.
        #expect(streamText.components(separatedBy: " re f").count - 1 >= 3)
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

    @Test("Math symbol coverage: a Latin-only embedded font reports no math glyphs")
    func mathSymbolCoverageFallsBackForLatinOnlyFont() throws {
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let source = PDFOptions.EmbeddedFontSource(data: fontData, baseName: "Latin Only")
        let catalog = try PDFEmbeddedFontCatalog(fonts: PDFOptions.EmbeddedFonts(regular: source))

        // A capital letter the witness font draws is covered; the Unicode math
        // block it lacks is not, so those symbols fall back to ASCII.
        #expect(catalog.covers("A", font: .helvetica))
        #expect(!catalog.covers("\u{2211}", font: .helvetica)) // summation
        #expect(!catalog.covers("\u{00B1}", font: .helvetica)) // plus-minus
        #expect(!catalog.covers("\u{03C3}", font: .helvetica)) // sigma

        // The base-14 portable profile has no embedded entry, so it covers nothing.
        let portable = try PDFEmbeddedFontCatalog(fonts: PDFOptions.EmbeddedFonts())
        #expect(!portable.covers("A", font: .helvetica))
        #expect(!portable.covers("\u{2211}", font: .helvetica))
    }

    @Test(
        "Math symbols render as Unicode glyphs when the embedded font covers them",
        .enabled(if: OpenTrueTypeFontFixture.isAvailable, OpenTrueTypeFontFixture.skipReason),
    )
    func mathSymbolsRenderAsUnicodeWhenCovered() throws {
        let fontURL = try #require(OpenTrueTypeFontFixture.url)
        let source = try PDFOptions.EmbeddedFontSource(data: Data(contentsOf: fontURL), baseName: "Open Math")

        // DejaVu Sans and Liberation Sans both cover these symbols.
        let catalog = try PDFEmbeddedFontCatalog(fonts: PDFOptions.EmbeddedFonts(regular: source))
        #expect(catalog.covers("\u{2211}", font: .helvetica)) // ∑
        #expect(catalog.covers("\u{00B1}", font: .helvetica)) // ±

        let data = try MarkdownPDFRenderer(
            options: PDFOptions(
                embeddedFonts: PDFOptions.EmbeddedFonts(regular: source),
                mathTypesetting: .enabled,
            ),
        ).render(markdown: "$$\\sum_{i=1}^{n} i \\pm c$$")

        // The drawn summation glyph carries a ToUnicode mapping back to U+2211,
        // proving the symbol reached the page as a real glyph rather than "sum".
        let inspector = PDFInspector(data)
        let streamText = inspector.streams.map(\.body).joined(separator: "\n")
        #expect(streamText.contains("2211"), "Expected a ToUnicode entry for U+2211 (summation)")
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "math-unicode-coverage")
        #expect(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
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

        // Run the full visual witness battery so a wrong CID `/W` width array or
        // mis-scaled FontDescriptor metric fails the build instead of shipping a
        // garbled render. See #194 and #195.
        try assertEmbeddedFontVisualWitness(
            data,
            name: "open-font-fixture",
            expectedSubstrings: [
                "Table of Contents",
                "Café résumé text uses embedded glyphs.",
            ],
            minWords: 6,
        )
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

        // Extraction alone is blind to a wrong CID `/W` width array, so run the
        // full visual witness battery (Poppler word-box geometry, MuPDF quads,
        // and a Poppler-vs-MuPDF raster comparison). Diacritic Latin, Cyrillic,
        // and Greek are covered by the open CI fonts (DejaVu Sans on Linux,
        // Liberation Sans on macOS) and round-trip through the subset and
        // ToUnicode map; complex tables keep their headers and mixed-script
        // cells. See #194 and #195.
        try assertEmbeddedFontVisualWitness(
            data,
            name: "multilingual-corpus",
            expectedSubstrings: [
                "café",
                "résumé",
                "Привет",
                "Καλημέρα",
                "Script",
                "Sample",
                "Привет мир",
            ],
            minWords: 50,
        )
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

enum OpenTrueTypeFontFixture {
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
