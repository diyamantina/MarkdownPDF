import Foundation
@testable import MarkdownPDF
import Testing

@Suite("Arabic shaper")
struct ArabicShaperTests {
    // MARK: - Joining state machine (pure, exact)

    private func forms(_ text: String) -> [ArabicPositionalForm] {
        ArabicShaper.positionalForms(for: Array(text.unicodeScalars))
    }

    @Test("Three dual-joining letters take initial, medial, final")
    func threeDualLettersJoin() {
        #expect(forms("\u{0628}\u{0628}\u{0628}") == [.initial, .medial, .final]) // ببب
    }

    @Test("A mixed word resolves each letter's form")
    func mixedWordForms() {
        // مرحبا = meem(D) reh(R) hah(D) beh(D) alef(R); verified against HarfBuzz.
        #expect(forms("\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}") == [.initial, .final, .initial, .medial, .final])
    }

    @Test("A single letter is isolated")
    func singleLetterIsolated() {
        #expect(forms("\u{0628}") == [.isolated]) // beh
        #expect(forms("\u{0627}") == [.isolated]) // alef (right-joining)
    }

    @Test("A right-joining letter joins only to the preceding letter")
    func rightJoiningLetter() {
        // beh(D) + alef(R): beh joins forward to alef → beh initial, alef final.
        #expect(forms("\u{0628}\u{0627}") == [.initial, .final])
        // alef(R) + beh(D): alef is right-joining, so it does NOT connect to a
        // following letter; beh has nothing joinable before it and nothing after,
        // so both are isolated (verified against hb-shape).
        #expect(forms("\u{0627}\u{0628}") == [.isolated, .isolated])
    }

    @Test("A transparent harakat mark does not break joining")
    func markDoesNotBreakJoining() {
        // beh + fatha(mark) + beh: the two beh still join across the mark.
        #expect(forms("\u{0628}\u{064E}\u{0628}") == [.initial, .unshaped, .final])
    }

    @Test("A non-joining character breaks the cursive chain")
    func nonJoiningBreaksChain() {
        // beh + space + beh: each beh is isolated.
        #expect(forms("\u{0628} \u{0628}") == [.isolated, .unshaped, .isolated])
        // beh + digit + beh: digit is non-joining.
        #expect(forms("\u{0628}5\u{0628}") == [.isolated, .unshaped, .isolated])
    }

    @Test("containsJoiningScript detects Arabic, not Latin")
    func detectsJoiningScript() {
        #expect(ArabicShaper.containsJoiningScript("\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}"))
        #expect(!ArabicShaper.containsJoiningScript("hello"))
        #expect(!ArabicShaper.containsJoiningScript("café"))
    }

    // MARK: - Differential oracle against HarfBuzz (hb-shape)

    /// Words Noto shapes purely with GSUB single-substitution (isol/init/medi/fina)
    /// and non-lam-alef ligatures, i.e. the lookup types this shaper implements
    /// (1 and 4). Each must match hb-shape's glyph ids exactly.
    private static let oracleCorpus = [
        "\u{0628}", "\u{062A}", "\u{0646}", // isolated beh, teh, noon
        "\u{0628}\u{0628}\u{0628}", // ببب
        "\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}", // مرحبا
        "\u{0628}\u{0633}\u{0645}", // بسم
        "\u{0627}\u{0644}\u{0644}\u{0647}", // الله
        "\u{0643}\u{062A}\u{0627}\u{0628}", // كتاب
        "\u{0645}\u{062D}\u{0645}\u{062F}", // محمد
        "\u{0646}\u{0639}\u{0645}", // نعم
        "\u{0639}\u{0631}\u{0628}\u{064A}", // عربي
        "\u{0634}\u{0643}\u{0631}\u{0627}", // شكرا
        "\u{0643}\u{0644}\u{0645}\u{0629}", // كلمة
    ]

    @Test(
        "Shaped glyph ids match hb-shape for Noto (single-substitution and ligature scope)",
        .enabled(if: HarfBuzzOracle.isAvailable, "hb-shape not found on PATH"),
    )
    func matchesHarfBuzzOnNoto() throws {
        let font = try Self.notoFont()
        let shaper = ArabicShaper(fontData: font.data, metadata: font.metadata)
        for word in Self.oracleCorpus {
            let engine = try shaper.shape(word).map(\.glyphID)
            let oracle = try HarfBuzzOracle.shape(word, fontPath: font.path)
            #expect(engine == oracle, "mismatch for \(word.unicodeScalars.map { String($0.value, radix: 16) }): engine \(engine) vs hb-shape \(oracle)")
        }
    }

    @Test("Lam-alef ligates to a single presentation-form glyph")
    func lamAlefLigates() throws {
        // Noto refines lam-alef with an additional contextual (GSUB type 5/6)
        // substitution that this shaper does not implement yet. Without it the shaper
        // applies Noto's simple type-4 rlig ligature, which yields the canonical
        // single lam-alef presentation-form glyph (U+FEFB/U+FEFC, GID 733 = uniFEFC),
        // a complete, legible ligature. So the two input letters collapse to one glyph.
        let font = try Self.notoFont()
        let shaper = ArabicShaper(fontData: font.data, metadata: font.metadata)
        for word in ["\u{0644}\u{0627}", "\u{0644}\u{0623}", "\u{0644}\u{0625}", "\u{0644}\u{0622}"] {
            let glyphs = try shaper.shape(word)
            #expect(glyphs.count == 1, "\(word) should ligate lam-alef to one glyph, got \(glyphs.count)")
            #expect(glyphs.first?.glyphID != 0)
            // The ligature covers both source scalars.
            #expect(glyphs.first?.sourceScalarRange == 0 ..< 2)
        }
    }

    private static func notoFont() throws -> (data: Data, metadata: TrueTypeFontParser.Metadata, path: String) {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/NotoNaskhArabic-Regular.ttf")
        let data = try Data(contentsOf: url)
        let metadata = try TrueTypeFontParser().parse(data)
        return (data, metadata, url.path)
    }
}

/// Runs the reference HarfBuzz shaper (`hb-shape`) and returns its glyph ids in
/// logical order, as the differential oracle for Arabic shaping.
enum HarfBuzzOracle {
    static var isAvailable: Bool {
        (try? run(arguments: ["hb-shape", "--version"])) != nil
    }

    /// The glyph ids `hb-shape` produces for `text`, reordered from visual (RTL) to
    /// logical order by the cluster index each glyph carries.
    static func shape(_ text: String, fontPath: String) throws -> [UInt16] {
        // `--script=arab` pins itemization (so a Latin- or digit-adjacent Arabic run
        // is not mis-scripted) and `--cluster-level=1` gives each base and mark its
        // own cluster, so reordering by cluster below stays faithful for text with
        // marks. Without these the harness produces false diffs on extended corpora.
        let output = try run(arguments: [
            "hb-shape", "--font-file=\(fontPath)", "--no-glyph-names",
            "--script=arab", "--cluster-level=1", text,
        ])
        // Format: [glyph=cluster+advance|glyph=cluster+advance|...]
        let inner = output.trimmingCharacters(in: CharacterSet(charactersIn: "[]\n"))
        guard !inner.isEmpty else {
            return []
        }
        var entries: [(cluster: Int, glyph: UInt16)] = []
        for token in inner.split(separator: "|") {
            let glyphPart = token.prefix { $0 != "=" }
            let afterEquals = token.drop { $0 != "=" }.dropFirst()
            let clusterPart = afterEquals.prefix { $0 != "+" && $0 != "@" }
            guard let glyph = UInt16(glyphPart), let cluster = Int(clusterPart) else {
                continue
            }
            entries.append((cluster, glyph))
        }
        // Stable sort by cluster keeps hb's within-cluster order (base then marks).
        return entries.enumerated()
            .sorted { ($0.element.cluster, $0.offset) < ($1.element.cluster, $1.offset) }
            .map(\.element.glyph)
    }

    private static func run(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw OracleError.failed(status: process.terminationStatus)
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private enum OracleError: Error { case failed(status: Int32) }
}
