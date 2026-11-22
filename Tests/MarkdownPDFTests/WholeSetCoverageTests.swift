import Foundation
@testable import MarkdownPDF
import Testing

/// The whole set: how many of every emoji and symbol that Unicode names the bundled faces draw, per class, and which they do not. The canonical list is the
/// Unicode Consortium's `emoji-test.txt` (every emoji sequence of one Unicode release, committed beside this file in `Unicode/` with the Unicode License V3,
/// which allows the copy provided its notice stays with it), and the symbol blocks that an article uses or may use (arrows, mathematical operators,
/// miscellaneous technical, box drawing, block elements, geometric shapes, miscellaneous symbols, dingbats, Braille, supplemental arrows, miscellaneous
/// symbols and arrows), read from the Swift standard library's own Unicode data (assigned code points only).
///
/// Every entry is DRAWN from a face that has it, REPORTED by name, or WRONG (replaced by a stand-in letter or drawn as the missing-glyph box): the count of the
/// wrong ones must be 0. The answer for each entry is the renderer's own report (``MarkdownPDF/Render/Report``), checked against the base-14 text the page
/// holds (a stand-in letter would be there) and against the glyph codes (`.notdef`); it is not the same code as the drawing.
///
/// The run is slow (a document of every entry, a few seconds) and is not in the default suite. Its command, from the root of the repository:
///
///     MARKDOWNPDF_WHOLE_SET=check swift test --filter WholeSetCoverageTests      # the report must equal Tests/MarkdownPDFTests/Unicode/whole-set-report.txt
///     MARKDOWNPDF_WHOLE_SET=write swift test --filter WholeSetCoverageTests      # rewrites that file (a change of the faces, or of the Unicode release)
///
/// The report is deterministic: the same bytes on a second run.
@Suite("Whole-set coverage of the emoji and the symbol blocks")
struct WholeSetCoverageTests {
    struct Entry {
        var scalars: [Unicode.Scalar]
        var name: String
        var status: String
        var group: String
        var classification: String

        var text: String {
            String(String.UnicodeScalarView(scalars))
        }

        var label: String {
            scalars.map { "U+" + String($0.value, radix: 16, uppercase: true) }.joined(separator: " ") + " " + name
        }
    }

    private static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Unicode")

    /// The emoji entries of `emoji-test.txt`, in file order, with the structural class of each.
    static func emojiEntries() throws -> (entries: [Entry], version: String, date: String) {
        let text = try String(contentsOf: folder.appendingPathComponent("emoji-test.txt"), encoding: .utf8)
        var entries: [Entry] = []
        var group = ""
        var version = ""
        var date = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("# Version:") {
                version = line.dropFirst("# Version:".count).trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("# Date:") {
                date = line.dropFirst("# Date:".count).trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("# group:") {
                group = line.dropFirst("# group:".count).trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("#") || line.isEmpty {
                continue
            }
            let parts = line.split(separator: ";", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let scalars = parts[0].split(separator: " ").compactMap { UInt32($0, radix: 16).flatMap(Unicode.Scalar.init) }
            let rest = parts[1].split(separator: "#", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard rest.count == 2 else { continue }
            // after the `#`: the character, `E<version>`, the name
            let words = rest[1].split(separator: " ", maxSplits: 2).map(String.init)
            let name = words.count == 3 ? words[2] : rest[1]
            entries.append(Entry(scalars: scalars, name: name, status: rest[0], group: group, classification: classify(scalars)))
        }
        return (entries, version, date)
    }

    /// The structural class of an emoji sequence.
    static func classify(_ scalars: [Unicode.Scalar]) -> String {
        let values = scalars.map(\.value)
        if values.contains(0x200D) {
            return "zwj sequence"
        }
        if values.last == 0x20E3 {
            return "keycap"
        }
        if values.count == 2, values.allSatisfy({ (0x1F1E6 ... 0x1F1FF).contains($0) }) {
            return "flag"
        }
        if values.contains(where: { (0xE0020 ... 0xE007F).contains($0) }) {
            return "tag sequence"
        }
        if values.count == 1, (0x1F3FB ... 0x1F3FF).contains(values[0]) {
            return "skin tone component"
        }
        if values.contains(where: { (0x1F3FB ... 0x1F3FF).contains($0) }) {
            return "modifier sequence"
        }
        if values.count == 2, values[1] == 0xFE0F {
            return "variation selector 16 sequence"
        }
        if values.count == 1 {
            return "single code point"
        }
        return "other sequence"
    }

    /// The symbol blocks, by name and range.
    static let blocks: [(name: String, range: ClosedRange<UInt32>)] = [
        ("Arrows", 0x2190 ... 0x21FF), ("Mathematical Operators", 0x2200 ... 0x22FF), ("Miscellaneous Technical", 0x2300 ... 0x23FF),
        ("Box Drawing", 0x2500 ... 0x257F), ("Block Elements", 0x2580 ... 0x259F), ("Geometric Shapes", 0x25A0 ... 0x25FF),
        ("Miscellaneous Symbols", 0x2600 ... 0x26FF), ("Dingbats", 0x2700 ... 0x27BF), ("Braille Patterns", 0x2800 ... 0x28FF),
        ("Supplemental Arrows-B", 0x2900 ... 0x297F), ("Miscellaneous Symbols and Arrows", 0x2B00 ... 0x2BFF),
    ]

    /// The assigned code points of the blocks, in code point order, as entries of the class `block <name>`.
    static func blockEntries() -> [Entry] {
        var entries: [Entry] = []
        for block in blocks {
            for value in block.range {
                guard let scalar = Unicode.Scalar(value) else { continue }
                let category = scalar.properties.generalCategory
                if category == .unassigned || category == .control || category == .surrogate || category == .privateUse {
                    continue
                }
                entries.append(Entry(scalars: [scalar], name: scalar.properties.name ?? "", status: "assigned", group: block.name, classification: "block " + block.name))
            }
        }
        return entries
    }

    struct Result {
        var entry: Entry
        /// `drawn`, `reported`, or `wrong: <why>`.
        var outcome: String
    }

    /// One document holding every entry, a line each, rendered with the faces a caller that gives none gets; each entry is judged from the report of the
    /// renderer and from the bytes.
    func judge(_ entries: [Entry]) throws -> [Result] {
        let markdown = "```\n" + entries.map { "x \($0.text) y" }.joined(separator: "\n") + "\n```\n"
        let output = try MarkdownPDFRenderer(options: PDFOptions(mathTypesetting: .enabled)).renderWithReport(markdown: markdown)
        // A skin tone modifier written alone after a space is part of the space's grapheme cluster (Unicode makes the modifier an extender), so the report
        // names the pair: the entry is the modifier, and the pair stands for it.
        var reported = Set(output.report.undrawn.map(\.text))
        for entry in entries where entry.scalars.count == 1 && (0x1F3FB ... 0x1F3FF).contains(entry.scalars[0].value) && reported.contains(" " + entry.text) {
            reported.insert(entry.text)
        }
        // The entries that are drawn are rendered again alone: a missing-glyph box is the look of a REPORTED character, so boxes and stand-in letters are
        // judged on the page of the drawn ones only.
        let drawnOnly = "```\n" + entries.filter { !reported.contains($0.text) }.map { "x \($0.text) y" }.joined(separator: "\n") + "\n```\n"
        let drawnOutput = try MarkdownPDFRenderer(options: PDFOptions(mathTypesetting: .enabled)).renderWithReport(markdown: drawnOnly)
        // What the base-14 font wrote: with the bundled faces nothing but ASCII may be there, and then only the markers of the lines.
        var standard = ""
        var notdef = 0
        let tokens = PDFInspector(drawnOutput.data).text.split(whereSeparator: \.isWhitespace)
        for index in tokens.indices.dropLast() where tokens[index + 1] == "Tj" {
            let token = tokens[index]
            if token.hasPrefix("<"), token.hasSuffix(">") {
                let hex = Array(token.dropFirst().dropLast())
                for start in stride(from: 0, to: hex.count - 3, by: 4) where String(hex[start ..< start + 4]) == "0000" {
                    notdef += 1
                }
            } else if token.hasPrefix("(") {
                standard += token
            }
        }
        let standardLetters = standard.filter(\.isLetter)
        var results: [Result] = []
        for entry in entries {
            results.append(Result(entry: entry, outcome: reported.contains(entry.text) ? "reported" : "drawn"))
        }
        // The two document-wide checks: a stand-in letter and a missing-glyph box anywhere in the page are failures of the whole set (the page holds only the
        // markers x and y as letters).
        if standardLetters.contains(where: { $0 != "x" && $0 != "y" }) {
            results.append(Result(
                entry: Entry(scalars: [], name: "the page", status: "", group: "", classification: "document"),
                outcome: "wrong: base-14 letters `\(standardLetters.prefix(40))`",
            ))
        }
        if notdef > 0 {
            // Name the entries that are boxes: halve the drawn entries until each box is one entry.
            let boxed = try boxedEntries(entries.filter { !reported.contains($0.text) })
            let names = Set(boxed.map(\.text))
            for index in results.indices where names.contains(results[index].entry.text) && results[index].outcome == "drawn" {
                results[index].outcome = "wrong: drawn as the missing-glyph box although the report counts it drawn"
            }
            if boxed.isEmpty {
                results.append(Result(
                    entry: Entry(scalars: [], name: "the page", status: "", group: "", classification: "document"),
                    outcome: "wrong: \(notdef) missing-glyph boxes (not one entry alone)",
                ))
            }
        }
        return results
    }

    /// The glyph codes 0000 (`.notdef`) in the content of a page that holds `entries`, a line each.
    func notdefCount(_ entries: [Entry]) throws -> Int {
        let markdown = "```\n" + entries.map { "x \($0.text) y" }.joined(separator: "\n") + "\n```\n"
        let data = try MarkdownPDFRenderer(options: PDFOptions(mathTypesetting: .enabled)).render(markdown: markdown)
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

    /// The entries that draw a box: a chunk without a box is dropped, a chunk with one is halved until the entry is alone.
    func boxedEntries(_ entries: [Entry]) throws -> [Entry] {
        guard !entries.isEmpty, try notdefCount(entries) > 0 else { return [] }
        if entries.count == 1 {
            return entries
        }
        let half = entries.count / 2
        return try boxedEntries(Array(entries[..<half])) + boxedEntries(Array(entries[half...]))
    }

    /// The deterministic report: counts per class, and the named list of those not drawn.
    func report(emoji: (entries: [Entry], version: String, date: String)) throws -> String {
        let classes = emoji.entries.map(\.classification)
        var order: [String] = []
        for name in classes + Self.blocks.map({ "block " + $0.name }) where !order.contains(name) {
            order.append(name)
        }
        let all = emoji.entries + Self.blockEntries()
        let results = try judge(all)
        var lines: [String] = []
        lines.append("Whole-set coverage of the bundled faces")
        lines.append("emoji source: emoji-test.txt, Unicode \(emoji.version), \(emoji.date), \(emoji.entries.count) entries")
        lines.append("symbol blocks: \(Self.blocks.map(\.name).joined(separator: ", ")) (assigned code points of the Swift standard library's Unicode data)")
        lines.append("")
        var totalDrawn = 0
        var totalAll = 0
        for name in order {
            let mine = results.filter { $0.entry.classification == name }
            let drawn = mine.filter { $0.outcome == "drawn" }.count
            let reported = mine.filter { $0.outcome == "reported" }.count
            let wrong = mine.filter { $0.outcome.hasPrefix("wrong") }.count
            totalDrawn += drawn
            totalAll += mine.count
            lines.append("\(name): \(mine.count) entries, \(drawn) drawn, \(reported) reported, \(wrong) wrong")
        }
        lines.append("")
        lines.append("TOTAL: \(totalAll) entries, \(totalDrawn) drawn")
        let wrongs = results.filter { $0.outcome.hasPrefix("wrong") }
        lines.append("WRONG: \(wrongs.count)" + wrongs.map { "\n  \($0.entry.label): \($0.outcome)" }.joined())
        lines.append("")
        lines.append("REPORTED, by class:")
        for name in order {
            let missing = results.filter { $0.entry.classification == name && $0.outcome == "reported" }
            guard !missing.isEmpty else { continue }
            lines.append("[\(name)] \(missing.count)")
            for item in missing {
                lines.append("  " + item.entry.label)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static let mode = ProcessInfo.processInfo.environment["MARKDOWNPDF_WHOLE_SET"]

    @Test(
        "every emoji and symbol is drawn from a face or reported by name, none wrongly replaced; the report equals the committed one",
        .enabled(if: mode == "check" || mode == "write"),
    )
    func wholeSet() throws {
        let text = try report(emoji: Self.emojiEntries())
        let again = try report(emoji: Self.emojiEntries())
        #expect(text == again, "the report is not the same on a second run")
        #expect(text.contains("\nWRONG: 0"), Comment(rawValue: String(text.prefix(3000))))
        let file = Self.folder.appendingPathComponent("whole-set-report.txt")
        if Self.mode == "write" {
            try text.write(to: file, atomically: true, encoding: .utf8)
        } else {
            let expected = try String(contentsOf: file, encoding: .utf8)
            #expect(text == expected, "the whole-set report changed: run with MARKDOWNPDF_WHOLE_SET=write after a deliberate change of the faces or of the Unicode release")
        }
    }
}
