import Foundation
@testable import MarkdownPDF
import Testing

/// The oracle of the rule: every character of the input domain is DRAWN from a face that has the glyph, or REPORTED (a named list), and is never
/// replaced by a wrong letter (`v` for an arrow or a check mark, `?` for an emoji). The domain is the characters the WinAnsi faces do not cover in
/// the Markdown sources of a blog, a book, the documentation and the READMEs (53 code points, found by a read-only inventory), plus the sequences no
/// source holds (flags, keycaps, skin tones, joined emoji) and the emoji presentation of each text-default symbol.
///
/// The answer key is independent of the drawing code: whether a face "has" a character is read from the cmap of the embedded faces of the document
/// (``PDFEmbeddedFontCatalog/covers(_:font:)``) and from the colour face (a cluster it draws), for the configuration under test. What the page holds is
/// read back from the bytes: the base-14 strings of the content (where a stand-in letter would be), the glyph codes (`.notdef` is 0000), and the text
/// layer through the package's own reader.
@Suite("Symbol oracle: drawn from a face that has the glyph, or reported, never a wrong letter")
struct SymbolOracleTests {
    /// The code points of the inventory.
    static let codePoints: [UInt32] = [
        0x03C3, 0x0107, 0x2192, 0x2193, 0x2190, 0x2194, 0x2B06, 0x2B07, 0x2500, 0x251C, 0x2502, 0x2514, 0x2591, 0x2588, 0x2839, 0x2827, 0x2713, 0x2705, 0x2717,
        0x274C, 0x1F4E6, 0x1F4A1, 0x1F9E9, 0x1F449, 0x1F4DA, 0x1F680, 0x1F9E0, 0x1F9F1, 0x26A1, 0x1F310, 0x1F4AC, 0x1F4C1, 0x1F4C2, 0x1F4CA, 0x1F501, 0x1F50D,
        0x1F510, 0x1F5A5, 0x1F605, 0x1F7E1, 0x1F9EA, 0x1F9ED, 0x2699, 0x26A0, 0x2212, 0x2248, 0x2264, 0x2208, 0x2211, 0x2081, 0x2082, 0x279C,
    ]

    /// Each text-default symbol of the list with the emoji variation selector, as a writer of an article types it (`U+2B07 U+FE0F`), and the sequences
    /// no source holds: a flag (two regional indicators), a keycap, a skin tone, a joined emoji.
    static let sequences: [(name: String, text: String)] = [
        ("down arrow, emoji presentation", "\u{2B07}\u{FE0F}"), ("up arrow, emoji presentation", "\u{2B06}\u{FE0F}"), ("gear, emoji presentation", "\u{2699}\u{FE0F}"),
        ("warning, emoji presentation", "\u{26A0}\u{FE0F}"), ("check mark, emoji presentation", "\u{2714}\u{FE0F}"), ("computer, emoji presentation", "\u{1F5A5}\u{FE0F}"),
        ("flag of Germany", "\u{1F1E9}\u{1F1EA}"), ("keycap one", "1\u{FE0F}\u{20E3}"), ("thumbs up, medium skin tone", "\u{1F44D}\u{1F3FD}"),
        ("family, joined", "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"),
    ]

    static var domain: [(name: String, text: String)] {
        codePoints.map { ("U+" + String($0, radix: 16, uppercase: true), String(UnicodeScalar($0).map(Character.init) ?? "?")) } + sequences
    }

    /// A document that embeds the text faces and the code face, and one that embeds the text faces only (the code is then written with the base-14 font).
    static let configurations: [(name: String, fonts: PDFOptions.EmbeddedFonts)] = {
        var codeNotEmbedded = PDFOptions.EmbeddedFonts.dejaVu
        codeNotEmbedded.monospaced = nil
        // The third is what a caller that gives no face gets (a site generator that passes only the math option): the renderer takes the bundled faces
        // when the document holds text outside WinAnsi, and the page is judged against those.
        return [("every role embedded", .dejaVu), ("the code face not embedded", codeNotEmbedded), ("no face given, the renderer takes the bundled ones", .disabled)]
    }()

    /// Where the character stands: a code fence, a code span, the body.
    static let places: [(name: String, template: @Sendable (String) -> String)] = [
        ("code fence", { "```\na \($0) b\n```\n" }),
        ("code span", { "x `a \($0) b` y\n" }),
        ("body", { "a \($0) b\n" }),
    ]

    private func ignorable(_ scalar: UnicodeScalar) -> Bool {
        [0xFE0F, 0xFE0E, 0x200D].contains(scalar.value)
    }

    /// Whether a face of the configuration has what the text needs: the cmap of the embedded faces, the colour face for an emoji cluster.
    private func faceHas(_ text: String, catalog: PDFEmbeddedFontCatalog) -> Bool {
        for segment in EmojiSegmenter.segments(of: text) {
            switch segment {
            case let .text(part):
                for scalar in part.unicodeScalars where !ignorable(scalar) {
                    let one = String(scalar)
                    if !catalog.covers(one, font: .helvetica), !catalog.covers(one, font: .courier) {
                        return false
                    }
                }
            case let .emoji(cluster):
                if catalog.colorEmoji?.drawing(of: cluster, fontSize: 10) != nil {
                    continue
                }
                for scalar in cluster.text.unicodeScalars where !ignorable(scalar) {
                    let one = String(scalar)
                    if !catalog.covers(one, font: .helvetica), !catalog.covers(one, font: .courier) {
                        return false
                    }
                }
            }
        }
        return true
    }

    /// The strings of the base-14 `Tj` operators of the page content (`BT /F4 9.9 Tf 60 772 Td (let ) Tj ET`, one per word), joined.
    private func standardText(in data: Data) -> String {
        var joined = ""
        for line in PDFInspector(data).text.split(separator: "\n") where line.contains(") Tj") {
            guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close else { continue }
            joined += line[line.index(after: open) ..< close]
        }
        return joined
    }

    /// The glyph codes 0000 (`.notdef`, the missing-glyph box) of every `Tj` string of the content.
    private func notdefCodes(in data: Data) -> Int {
        var count = 0
        let tokens = PDFInspector(data).text.split(whereSeparator: \.isWhitespace)
        for index in tokens.indices.dropLast() where tokens[index + 1] == "Tj" && tokens[index].hasPrefix("<") && tokens[index].hasSuffix(">") {
            let hex = Array(tokens[index].dropFirst().dropLast())
            for start in stride(from: 0, to: hex.count - 3, by: 4) where String(hex[start ..< start + 4]) == "0000" {
                count += 1
            }
        }
        return count
    }

    private func textLayer(of data: Data) throws -> String {
        try PDFDocumentReader(data: data).pages.flatMap(\.words).map(\.text).joined(separator: " ")
    }

    struct Verdict {
        var configuration: String
        var place: String
        var entry: String
        /// nil: drawn from a face that has it. A reason: the character was replaced, lost or drawn as a box although a face has it.
        var wrong: String?
        /// True when no face of the configuration has the character: it is on the reported list, not judged.
        var reported = false
    }

    private func judge(
        _ entry: (name: String, text: String),
        place: (name: String, template: @Sendable (String) -> String),
        configuration: (name: String, fonts: PDFOptions.EmbeddedFonts),
    ) throws -> Verdict {
        var verdict = Verdict(configuration: configuration.name, place: place.name, entry: entry.name)
        let catalog = try PDFEmbeddedFontCatalog(fonts: configuration.fonts.hasNoTextFaces ? .dejaVu : configuration.fonts)
        let output = try MarkdownPDFRenderer(options: PDFOptions(embeddedFonts: configuration.fonts, mathTypesetting: .enabled))
            .renderWithReport(markdown: place.template(entry.text))
        let data = output.data
        // The renderer's own report must agree with the answer key (the cmaps): a character a face has is not in it, one no face has is.
        let inReport = output.report.undrawn.contains { $0.text == entry.text }
        guard faceHas(entry.text, catalog: catalog) else {
            verdict.reported = true
            if !inReport {
                verdict.wrong = "silent: no face has it, and the report does not name it"
            }
            return verdict
        }
        if inReport {
            verdict.wrong = "the report names a character that a face draws"
            return verdict
        }
        // 1. no stand-in letter: what the base-14 font wrote is the letters around the character and nothing else
        let standard = standardText(in: data).filter { !$0.isWhitespace }
        if standard != "", standard != "ab" {
            verdict.wrong = "replaced: the base-14 text is `\(standard)`"
            return verdict
        }
        // 2. not the missing-glyph box
        if notdefCodes(in: data) > 0 {
            verdict.wrong = "drawn as the missing-glyph box"
            return verdict
        }
        // 3. the text layer keeps the character (scalar for scalar, the variation selector may go)
        let layer = try textLayer(of: data)
        let kept = Set(layer.unicodeScalars)
        let lost = entry.text.unicodeScalars.filter { !ignorable($0) && !kept.contains($0) }
        if !lost.isEmpty {
            verdict.wrong = "lost from the text layer: \(lost.map { "U+" + String($0.value, radix: 16, uppercase: true) }) in `\(layer)`"
        }
        return verdict
    }

    /// Every verdict of the domain in every configuration and place.
    private func computeVerdicts() -> [Verdict] {
        var all: [Verdict] = []
        for configuration in Self.configurations {
            for place in Self.places {
                for entry in Self.domain {
                    do {
                        try all.append(judge(entry, place: place, configuration: configuration))
                    } catch {
                        var failed = Verdict(configuration: configuration.name, place: place.name, entry: entry.name)
                        failed.wrong = "the page could not be made: \(error)"
                        all.append(failed)
                    }
                }
            }
        }
        return all
    }

    /// The verdicts, made once for the three tests of the suite.
    private static let cachedVerdicts: [Verdict] = SymbolOracleTests().computeVerdicts()

    private func verdicts() -> [Verdict] {
        Self.cachedVerdicts
    }

    @Test("MEASURED: how many characters of the domain are drawn from a face, wrongly replaced, or reported, per configuration and place")
    func measure() {
        let all = verdicts()
        var lines: [String] = []
        for configuration in Self.configurations {
            for place in Self.places {
                let mine = all.filter { $0.configuration == configuration.name && $0.place == place.name }
                let wrong = mine.filter { $0.wrong != nil }.count
                let reported = mine.filter(\.reported).count
                lines
                    .append(
                        "\(configuration.name) / \(place.name): \(mine.count) entries, \(mine.count - wrong - reported) drawn from a face, \(wrong) wrong, \(reported) reported",
                    )
            }
        }
        // Not an assertion: the numbers are the measurement, they appear in the log of the run.
        Issue.record(Comment(rawValue: "MEASURED\n" + lines.joined(separator: "\n")), severity: .warning)
    }

    @Test("every character a face has is drawn from it: no stand-in letter, no missing-glyph box, nothing lost from the text layer")
    func nothingWrong() {
        let wrong = verdicts().filter { $0.wrong != nil }
        let list = wrong.prefix(40).map { "\($0.configuration) / \($0.place) / \($0.entry): \($0.wrong ?? "")" }
        #expect(wrong.isEmpty, Comment(rawValue: "\(wrong.count) wrongly handled:\n" + list.joined(separator: "\n")))
    }

    @Test("the characters no face of the configuration has are the named list, the same in every place")
    func reportedList() {
        let all = verdicts()
        for configuration in Self.configurations {
            var perPlace: [Set<String>] = []
            for place in Self.places {
                perPlace.append(Set(all.filter { $0.configuration == configuration.name && $0.place == place.name && $0.reported }.map(\.entry)))
            }
            #expect(perPlace.dropFirst().allSatisfy { $0 == perPlace[0] }, Comment(rawValue: "\(configuration.name): the reported list differs between places: \(perPlace)"))
            #expect(perPlace[0].sorted() == Self.expectedReported[configuration.name]?.sorted() ?? [], Comment(rawValue: "\(configuration.name): reported \(perPlace[0].sorted())"))
        }
    }

    /// The characters no face has, per configuration. Filled from the first measured run; a change is a decision.
    static let expectedReported: [String: [String]] = [
        "every role embedded": ["U+1F5A5", "family, joined", "flag of Germany", "keycap one", "thumbs up, medium skin tone"],
        "the code face not embedded": ["U+1F5A5", "family, joined", "flag of Germany", "keycap one", "thumbs up, medium skin tone"],
        "no face given, the renderer takes the bundled ones": ["U+1F5A5", "family, joined", "flag of Germany", "keycap one", "thumbs up, medium skin tone"],
    ]
}
