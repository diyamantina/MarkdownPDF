@testable import MarkdownPDF
import Testing

@Suite("Heading destination names")
struct PDFHeadingDestinationNameTests {
    @Test("Canonically-equivalent headings produce the same slug")
    func canonicallyEquivalentHeadingsShareASlug() {
        // A precomposed é and a decomposed e + U+0301 are the same text; before the
        // fix they slugged to "caf-du-monde" and "cafe-du-monde" respectively, so an
        // internal link written in one normalization form missed a heading authored
        // in the other. See #39.
        var precomposed = PDFHeadingDestinationName()
        var decomposed = PDFHeadingDestinationName()
        #expect(precomposed.uniqueName(for: "Caf\u{00E9} du monde") == "cafe-du-monde")
        #expect(decomposed.uniqueName(for: "Caf\u{0065}\u{0301} du monde") == "cafe-du-monde")
    }

    @Test("Diacritics fold to their ASCII base rather than splitting or dropping the letter")
    func diacriticsFoldToASCIIBase() {
        // The combining mark is dropped and the base letter kept, so the word stays
        // whole: "naïve" -> "naive" (not "nai-ve"), and an accented letter is not
        // dropped outright ("café" -> "cafe", not "caf").
        #expect(PDFHeadingDestinationName.linkTargetName(for: "na\u{00EF}ve") == "naive")
        #expect(PDFHeadingDestinationName.linkTargetName(for: "nai\u{0308}ve") == "naive")
        #expect(PDFHeadingDestinationName.linkTargetName(for: "Caf\u{00E9}") == "cafe")
        // Croatian diacritics decompose to an ASCII base too.
        #expect(PDFHeadingDestinationName.linkTargetName(for: "\u{010D}okolada") == "cokolada") // čokolada
        #expect(PDFHeadingDestinationName.linkTargetName(for: "\u{0161}e\u{0107}er") == "secer") // šećer
    }

    @Test("A link target resolves to the heading's own generated name")
    func linkTargetMatchesGeneratedName() {
        var names = PDFHeadingDestinationName()
        let generated = names.uniqueName(for: "R\u{00E9}sum\u{00E9} Section")
        #expect(PDFHeadingDestinationName.linkTargetName(for: "r\u{00E9}sum\u{00E9}-section") == generated)
        // And in the other normalization form.
        #expect(PDFHeadingDestinationName.linkTargetName(for: "re\u{0301}sume\u{0301}-section") == generated)
    }

    @Test("Duplicate headings still get a disambiguating suffix")
    func duplicateHeadingsAreDisambiguated() {
        var names = PDFHeadingDestinationName()
        #expect(names.uniqueName(for: "Overview") == "overview")
        #expect(names.uniqueName(for: "Overview") == "overview-2")
        #expect(names.uniqueName(for: "Overview") == "overview-3")
        // The decomposed and precomposed forms collide into the same counter.
        #expect(names.uniqueName(for: "Caf\u{00E9}") == "cafe")
        #expect(names.uniqueName(for: "Caf\u{0065}\u{0301}") == "cafe-2")
    }

    @Test("Latin letters with no canonical decomposition still fold to an ASCII base")
    func nonDecomposableLatinLettersFold() {
        // These carry a stroke or are ligatures, so the decompose step leaves them
        // intact; an explicit fold keeps the ASCII-base promise, notably Croatian đ.
        #expect(PDFHeadingDestinationName.linkTargetName(for: "\u{0110}or\u{0111}e") == "dorde") // Đorđe
        #expect(PDFHeadingDestinationName.linkTargetName(for: "S\u{00F8}ren") == "soren")
        #expect(PDFHeadingDestinationName.linkTargetName(for: "\u{0141}\u{00F3}d\u{017A}") == "lodz") // Łódź
        #expect(PDFHeadingDestinationName.linkTargetName(for: "Stra\u{00DF}e") == "strasse")
        #expect(PDFHeadingDestinationName.linkTargetName(for: "\u{0152}uvre") == "oeuvre")
    }

    @Test("Generated names are unique even when a later heading's slug equals an earlier disambiguation")
    func generatedNamesNeverCollide() {
        // "Café" and "Cafe" both fold to "cafe", so the second becomes "cafe-2".
        // A third heading "Cafe 2" whose own slug is "cafe-2" must not reuse that
        // key: duplicate /Dests entries make viewer lookup undefined. See #39.
        var names = PDFHeadingDestinationName()
        let a = names.uniqueName(for: "Caf\u{00E9}")
        let b = names.uniqueName(for: "Cafe")
        let c = names.uniqueName(for: "Cafe 2")
        #expect(a == "cafe")
        #expect(b == "cafe-2")
        #expect(c == "cafe-2-2")
        #expect(Set([a, b, c]).count == 3, "generated destination names must be distinct")
    }

    @Test("Plain ASCII, punctuation, and empty titles are unchanged")
    func asciiAndEdgeCasesAreUnchanged() {
        var names = PDFHeadingDestinationName()
        #expect(names.uniqueName(for: "Hello, World!") == "hello-world")
        #expect(names.uniqueName(for: "  spaced  out  ") == "spaced-out")
        // A title with no sluggable characters falls back to "heading"; a second such
        // title collides into the same counter.
        #expect(names.uniqueName(for: "---") == "heading")
        #expect(names.uniqueName(for: "") == "heading-2")
    }
}
