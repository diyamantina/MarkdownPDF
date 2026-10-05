import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle for index term variants. The correctness question: for a document with
/// known words on known pages, the pages listed under a heading are exactly the
/// pages that contain at least one of the heading's forms, no more and no fewer.
///
/// Witnesses, independent of the matcher: a pure closed form (split into words,
/// fold with Foundation, compare word sequences), hand-written expectations, and a
/// generated multi-page document whose page text is read back by Poppler and by
/// MuPDF before the index is compared with it.
@Suite("Index term variants")
struct IndexVariantTests {
    // MARK: Parsing

    @Test("A text without a pipe is one form, exactly as before")
    func noPipe() throws {
        let term = try PDFOptions.Index.Term(parsing: "  layer   tree ")
        #expect(term.heading == "layer   tree")
        #expect(term.variants.isEmpty)
        #expect(term.text == "layer   tree")
    }

    @Test("The first form is the heading and white space around forms is trimmed")
    func headingAndTrim() throws {
        let term = try PDFOptions.Index.Term(parsing: " flattening | flatten\t|flattens |\nflattened ")
        #expect(term.heading == "flattening")
        #expect(term.variants == ["flatten", "flattens", "flattened"])
        #expect(term.forms == ["flattening", "flatten", "flattens", "flattened"])
    }

    @Test("Duplicate forms collapse by case, diacritics and white space, first spelling kept")
    func duplicatesCollapse() throws {
        let term = try PDFOptions.Index.Term(parsing: "Caf\u{E9}|cafe|CAFE|latte|la  tte|Latte|la tte|latte")
        #expect(term.heading == "Caf\u{E9}")
        #expect(term.variants == ["latte", "la  tte"])
    }

    @Test("Every empty form is a typed error, including pipes only")
    func emptyFormsThrow() {
        for text in ["a||b", "|a", "a|", "|", "||", "a| |b", "", "   "] {
            #expect(throws: MarkdownPDFError.indexTermEmptyForm(term: text), "\(text.debugDescription)") {
                try PDFOptions.Index.Term(parsing: text)
            }
        }
    }

    @Test("A backslash before a pipe is a literal pipe; other backslashes are ordinary")
    func escapes() throws {
        let term = try PDFOptions.Index.Term(parsing: #"a\|b|c\d|e\\|f\"#)
        // Forms: "a|b", "c\d", "e\" (the pair "\|" after the second backslash is an escape
        // for the pipe, so the form continues), and the trailing "f\".
        #expect(term.forms == ["a|b", #"c\d"#, #"e\|f\"#])
        let roundTrip = try PDFOptions.Index.Term(parsing: term.text)
        #expect(roundTrip == term)
    }

    @Test("The text form round-trips for awkward forms")
    func roundTrips() throws {
        let terms = [
            PDFOptions.Index.Term(heading: "a|b", variants: ["c", "d|e|"]),
            PDFOptions.Index.Term(heading: #"x\"#, variants: []),
            PDFOptions.Index.Term(heading: "main > sub", variants: ["other"]),
        ]
        for term in terms {
            #expect(try PDFOptions.Index.Term(parsing: term.text) == term, "\(term.text)")
        }
    }

    // MARK: Matcher, against a closed form

    /// Independent closed form. A text is cut into words (maximal runs of letters and
    /// digits, folded with Foundation) with the gap string before each word. A form
    /// matches at a word where its own words equal the following words and every gap
    /// inside the form is white space only (a line break is white space, so a phrase
    /// runs across lines, and the match belongs to the line of its first word).
    private func expectedLines(forms: [String], in lines: [String]) -> Set<Int> {
        func folded(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        func words(_ text: String) -> [String] {
            folded(text).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        }
        // (word, line, gap-before-is-white-space-only)
        var sequence: [(word: String, line: Int, spaceBefore: Bool)] = []
        var gap = ""
        var first = true
        for (index, line) in lines.enumerated() {
            gap += "\n"
            var word = ""
            for character in folded(line) + " " {
                if character.isLetter || character.isNumber {
                    word.append(character)
                } else {
                    if !word.isEmpty {
                        sequence.append((word, index, first || gap.allSatisfy(\.isWhitespace)))
                        first = false
                        gap = ""
                        word = ""
                    }
                    gap.append(character)
                }
            }
        }
        var result = Set<Int>()
        for form in forms {
            let target = words(form)
            guard !target.isEmpty, sequence.count >= target.count else {
                continue
            }
            for start in 0 ... sequence.count - target.count {
                let window = sequence[start ..< start + target.count]
                let sameWords = zip(window, target).allSatisfy { $0.word == $1 }
                let spaced = window.dropFirst().allSatisfy(\.spaceBefore)
                if sameWords, spaced {
                    result.insert(sequence[start].line)
                }
            }
        }
        return result
    }

    private func matchedLines(_ text: String, in lines: [String]) throws -> Set<Int> {
        let term = try PDFOptions.Index.Term(parsing: text)
        let entry = try #require(IndexRegistry.entry(for: term.heading))
        let matcher = IndexTermMatcher(terms: term.forms.enumerated().map { index, form in
            (entry.id, index == 0 ? entry.sub ?? entry.main : form)
        })
        return Set(matcher.matches(inLines: lines).map(\.line))
    }

    private static let corpus = [
        "Flattening the path: flatten, FLATTENS and flattened.",
        "Reflatten, flattenings, flatteningly and unflatten are other words.",
        "The (flatten) and flatten-ed and flatten_ed and flatten2.",
        "A blend",
        "mode and Blend Modes; blendmode, blend-mode.",
        "Caf\u{E9} and cafe and CAF\u{C9}, caf\u{E9}s.",
        "",
        "flatten",
    ]

    @Test(
        "Pages of a heading equal the union of the pages of its forms",
        arguments: [
            "flattening|flatten|flattens|flattened",
            "flatten|flattening",
            "flattening|flatten",
            "flatten",
            "blend mode|blend modes",
            "blend mode",
            "cafe|caf\u{E9}s",
            "never|nothing|nada",
            "Flattened|FLATTEN",
        ],
    )
    func unionOfForms(_ text: String) throws {
        let term = try PDFOptions.Index.Term(parsing: text)
        #expect(try matchedLines(text, in: Self.corpus) == expectedLines(forms: term.forms, in: Self.corpus), "\(text)")
    }

    @Test("A variant that is a prefix of another never matches inside it")
    func prefixVariants() throws {
        let lines = ["flattening", "flatten", "flattenings", "flatten flattening"]
        #expect(try matchedLines("flatten", in: lines) == [1, 3])
        #expect(try matchedLines("flattening", in: lines) == [0, 3])
        #expect(try matchedLines("flatten|flattening", in: lines) == [0, 1, 3])
    }

    @Test("Phrases with variants, across a line break")
    func phraseVariants() throws {
        let lines = ["see the blend", "mode here", "and blend modes", "and blend", "moded"]
        #expect(try matchedLines("blend mode|blend modes", in: lines) == [0, 2])
    }

    @Test("A form with a literal pipe matches the pipe character")
    func literalPipe() throws {
        #expect(try matchedLines(#"a\|b|zeta"#, in: ["x a|b y", "a b", "zeta"]) == [0, 2])
    }

    @Test("The same form under two headings records under both")
    func sameFormTwoHeadings() throws {
        let one = try PDFOptions.Index.Term(parsing: "stroke|line")
        let two = try PDFOptions.Index.Term(parsing: "path|line")
        var terms: [(entry: IndexEntryID, text: String)] = []
        for term in [one, two] {
            let entry = try #require(IndexRegistry.entry(for: term.heading))
            terms += term.forms.map { (entry.id, $0) }
        }
        let hits = IndexTermMatcher(terms: terms).matches(inLines: ["a line"]).map(\.entry.main).sorted()
        #expect(hits == ["path", "stroke"])
    }

    // MARK: Rendering

    /// One page per element; `<!-- pagebreak -->` separates them.
    private static let pages = [
        "# Intro\n\nThe path is Flattening here.",
        "We flatten it. Also flattened, and FLATTENS.",
        "Reflatten, flattenings and flatteningly are other words. Zeta is not here.",
        "| Step | Note |\n|---|---|\n| one | the flattens cell |",
        "## Heading flattened",
        "ALPHA arrives, and blend modes too. Caf\u{E9} here.",
        "A Blend Mode, CAFE, and `flatten` in code.\n\n```\nflattened in a block\n```",
    ]

    private static let markdown = pages.joined(separator: "\n\n<!-- pagebreak -->\n\n")

    /// Hand-derived: the pages (1-based) each heading must list.
    private static let handExpected: [String: [Int]] = [
        "flattening": [1, 2, 4, 5],
        "Zeta": [3, 6],
        "blend mode": [6, 7],
        "caf\u{E9}": [6, 7],
        "never": [],
    ]

    private static let terms = [
        "flattening|flatten|flattens|flattened",
        "Zeta|alpha",
        "blend mode|blend modes",
        "caf\u{E9}|cafe",
        "never|nope",
    ]

    private func render(_ options: PDFOptions, _ markdown: String = markdown) throws -> Data {
        try MarkdownPDFRenderer(options: options).render(markdown: markdown)
    }

    /// The index page as Poppler reads it: rows like `a, 1, 3-4` as `heading -> pages`.
    private func listing(of pdf: Data) throws -> [(heading: String, pages: [Int])] {
        let result = try PDFValidation.pdftotext(data: pdf, name: "index-variants-listing")
        try #require(result.exitCode == 0, "pdftotext failed:\n\(result.output)")
        let pages = result.output.components(separatedBy: "\u{0C}").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let last = try #require(pages.last)
        var entries: [(String, [Int])] = []
        for row in last.components(separatedBy: "\n") where row.contains(", ") {
            let parts = row.components(separatedBy: ", ")
            var numbers: [Int] = []
            for part in parts.dropFirst() {
                let bounds = part.split(separator: "-").compactMap { Int($0) }
                guard let low = bounds.first, let high = bounds.last else {
                    Issue.record("unreadable reference \(part) in \(row)")
                    continue
                }
                numbers += Array(low ... high)
            }
            entries.append((parts[0], numbers))
        }
        return entries
    }

    /// The text of every body page as Poppler reads it, the index page dropped.
    private func poppler(_ pdf: Data) throws -> [String] {
        let result = try PDFValidation.pdftotext(data: pdf, name: "index-variants")
        try #require(result.exitCode == 0, "pdftotext failed:\n\(result.output)")
        var pages = result.output.components(separatedBy: "\u{0C}")
        if pages.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            pages.removeLast()
        }
        return Array(pages.dropLast())
    }

    private func mupdf(_ pdf: Data) throws -> [String] {
        let stext = try PDFValidation.mutoolStructuredText(data: pdf, name: "index-variants-mupdf")
        try #require(stext.exitCode == 0, "mutool failed:\n\(stext.output)")
        let pages = try MuPDFStructuredText(xml: stext.output).pages
        return pages.dropLast().map { Self.decodingCharacterReferences($0.lines.map(\.text).joined(separator: "\n")) }
    }

    /// The MuPDF reader leaves numeric character references such as `&#xe9;` in its
    /// text; this is the witness-side decoding of them.
    private static func decodingCharacterReferences(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let start = rest.range(of: "&#x") {
            result += rest[rest.startIndex ..< start.lowerBound]
            let after = rest[start.upperBound...]
            if let end = after.firstIndex(of: ";"),
               let value = UInt32(after[after.startIndex ..< end], radix: 16),
               let scalar = Unicode.Scalar(value)
            {
                result.unicodeScalars.append(scalar)
                rest = after[after.index(after: end)...]
            } else {
                result += "&#x"
                rest = after
            }
        }
        return result + rest
    }

    /// Pages (1-based) of `text` that hold any form of `term`, by whole-word
    /// comparison of Foundation-folded word sequences, ignoring code. Page text is read back, so the fixture's two code
    /// snippets are dropped from it by hand first.
    private func witnessPages(forms: [String], in pageTexts: [String]) -> [Int] {
        let withoutCode = pageTexts.map {
            $0.replacingOccurrences(of: "flattened in a block", with: "").replacingOccurrences(of: "flatten in code", with: "")
        }
        var result: [Int] = []
        for (index, text) in withoutCode.enumerated() where !expectedLines(forms: forms, in: [text]).isEmpty {
            result.append(index + 1)
        }
        return result
    }

    @Test("Rendered index pages equal the union of the pages holding any form, per two readers")
    func renderedUnion() throws {
        let options = PDFOptions(index: PDFOptions.Index(isEnabled: true, terms: Self.terms))
        let pdf = try render(options)
        let listed = try listing(of: pdf)

        // Hand-derived expectation.
        for (heading, pages) in Self.handExpected {
            let entry = listed.first { $0.heading == heading }
            if pages.isEmpty {
                #expect(entry == nil, "\(heading) has no occurrences and must be omitted")
            } else {
                #expect(entry?.pages == pages, "\(heading)")
            }
        }
        #expect(listed.count == 4)

        // Independent page readers.
        for (name, texts) in try [("poppler", poppler(pdf)), ("mupdf", mupdf(pdf))] {
            try #require(texts.count == Self.pages.count, "\(name) page count \(texts.count)")
            for term in Self.terms {
                let parsed = try PDFOptions.Index.Term(parsing: term)
                let expected = witnessPages(forms: parsed.forms, in: texts)
                let entry = listed.first { $0.heading == parsed.heading }
                #expect((entry?.pages ?? []) == expected, "\(name): \(term)")
            }
        }
    }

    @Test("A generated 24-page document with a known word-to-page map lists exactly those pages", arguments: [1, 7, 2026])
    func generatedWordMap(seed: UInt64) throws {
        let vocabulary = [
            "stroke", "strokes", "stroked", "stroking", "strokeless", "bitmap context", "bitmap contexts", "context", "bitmap",
            "dither", "dithering", "filler", "words", "only",
        ]
        let terms = ["stroke|strokes|stroked|stroking", "bitmap context|bitmap contexts", "dither|dithering"]
        var state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var pageWords: [[String]] = []
        for _ in 0 ..< 24 {
            var words: [String] = []
            for _ in 0 ..< 4 {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                words.append(vocabulary[Int((state >> 33) % UInt64(vocabulary.count))])
            }
            pageWords.append(words)
        }
        let markdown = pageWords.map { "Page text: \($0.joined(separator: ", "))." }
            .joined(separator: "\n\n<!-- pagebreak -->\n\n")
        // By construction: a heading lists the pages whose word list holds one of its forms exactly.
        var expected: [String: [Int]] = [:]
        for term in terms {
            let parsed = try PDFOptions.Index.Term(parsing: term)
            let pages = pageWords.indices.filter { page in
                parsed.forms.contains { form in pageWords[page].contains(form) }
            }.map { $0 + 1 }
            if !pages.isEmpty {
                expected[parsed.heading] = pages
            }
        }
        let options = PDFOptions(index: PDFOptions.Index(isEnabled: true, terms: terms))
        let listed = try listing(of: render(options, markdown))
        #expect(listed.count == expected.count)
        for (heading, pages) in expected {
            #expect(listed.first { $0.heading == heading }?.pages == pages, "\(heading) seed \(seed)")
        }
    }

    @Test("The heading sorts by its own folded form, not by its variants, and a never-seen term is omitted")
    func headingOrder() throws {
        let options = PDFOptions(index: PDFOptions.Index(isEnabled: true, terms: Self.terms))
        let listed = try listing(of: render(options)).map(\.heading)
        // "Zeta|alpha" has a variant that sorts first, but is filed under Z.
        #expect(listed == ["blend mode", "caf\u{E9}", "flattening", "Zeta"])
    }

    @Test("An index made only of variant terms, in any order of forms, lists the same pages")
    func onlyVariantTerms() throws {
        let options = PDFOptions(index: PDFOptions.Index(isEnabled: true, terms: ["flatten|flattening|flattens|flattened"]))
        let listed = try listing(of: render(options))
        #expect(listed.count == 1)
        #expect(listed.first?.heading == "flatten")
        #expect(listed.first?.pages == [1, 2, 4, 5])
    }

    @Test("A term without a pipe renders exactly as the list written one form per entry")
    func singleFormsUnchanged() throws {
        let plain = ["flatten", "Zeta", "alpha"]
        let viaTerms = PDFOptions(index: PDFOptions.Index(isEnabled: true, terms: plain))
        let viaParsed = try PDFOptions(index: PDFOptions.Index(isEnabled: true, terms: plain.map { try PDFOptions.Index.Term(parsing: $0).text }))
        #expect(try render(viaTerms) == render(viaParsed))
    }

    @Test("A variant term and a marker for the same heading merge into one entry")
    func markerMerges() throws {
        let options = PDFOptions(index: PDFOptions.Index(isEnabled: true, terms: ["flattening|flatten"]))
        let markdown = "Start. {{index: flattening}}\n\n<!-- pagebreak -->\n\nA flatten here.\n\n<!-- pagebreak -->\n\nNothing."
        let listed = try listing(of: render(options, markdown))
        #expect(listed.count == 1)
        #expect(listed.first?.pages == [1, 2])
    }

    @Test("An empty form fails the render with the typed error, and only when the index is enabled")
    func renderThrows() throws {
        let enabled = PDFOptions(index: PDFOptions.Index(isEnabled: true, terms: ["fine", "a||b"]))
        #expect(throws: MarkdownPDFError.indexTermEmptyForm(term: "a||b")) {
            try render(enabled, "text")
        }
        let disabled = PDFOptions(index: PDFOptions.Index(isEnabled: false, terms: ["a||b"]))
        _ = try render(disabled, "text")
        let blank = PDFOptions(index: PDFOptions.Index(isEnabled: true, terms: ["  ", ""]))
        _ = try render(blank, "text")
    }

    @Test("A variant term yields a structurally valid PDF")
    func validPDF() throws {
        let options = PDFOptions(index: PDFOptions.Index(isEnabled: true, terms: Self.terms))
        let pdf = try render(options)
        let qpdf = try PDFValidation.qpdfCheck(data: pdf, name: "index-variants-valid")
        #expect(qpdf.exitCode == 0, "qpdf failed:\n\(qpdf.output)")
        let inspector = PDFInspector(pdf)
        #expect(inspector.canonicalStructureIssues().isEmpty, "\(inspector.canonicalStructureReport())")
    }
}
