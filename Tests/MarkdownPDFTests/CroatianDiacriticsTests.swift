import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: the Markdown that was rendered. The five Croatian letters outside ASCII
/// (ć č š ž đ, in both cases) must come back exactly from the finished file, read
/// with ``PDFDocumentReader``: from the title, the author, the outline, the body in
/// every face, a table and the text of a link. The reader itself is checked against
/// a file written by hand in `PDFDocumentReaderTests`.
@Suite("Croatian diacritics survive in the PDF")
struct CroatianDiacriticsTests {
    private static let name = "Mihaela Mihaljević Jakić"
    private static let title = "Životopis: \(name)"
    private static let letters = "ć č š ž đ Ć Č Š Ž Đ"
    private static let linkText = "Šibenik i Đakovo: više"

    private static let markdown = """
    # \(name)

    ## Čišćenje, žeđ i đak

    Slova: \(letters). Riječi: Čakovec, Šibenik, Žminj, Đakovo, kuća, voće.

    **Podebljano čišćenje** i *kosi žeđ đak* i `kod šđčćž`.

    - Stavka: gospođa Mihaljević
    - [\(linkText)](https://example.com/sibenik)

    | Grad | Županija |
    |------|----------|
    | Đakovo | Osječko-baranjska |

    ### Školovanje
    """

    private static let expectedLines = [
        name,
        "Čišćenje, žeđ i đak",
        "Slova: \(letters). Riječi: Čakovec, Šibenik, Žminj, Đakovo, kuća, voće.",
        "Podebljano čišćenje i kosi žeđ đak i kod šđčćž.",
        "\u{2022} Stavka: gospođa Mihaljević",
        "\u{2022} \(linkText)",
        "Grad Županija",
        "Đakovo Osječko-baranjska",
        "Školovanje",
    ]

    private static func read(_ documentStrings: PDFOptions.DocumentStrings, tagged: Bool = false, compressed: Bool = false) throws -> PDFDocumentReader {
        var options = PDFOptions(title: title, author: name, documentStrings: documentStrings)
        options.taggedPDF = tagged ? .enabled : .disabled
        options.streamCompression = compressed ? .enabled : .disabled
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
        #expect(PDFInspector(pdf).canonicalStructureIssues().isEmpty || compressed)
        return try PDFDocumentReader(data: pdf)
    }

    @Test("Every letter comes back from the page, in every face", arguments: [false, true], [false, true])
    func pageText(tagged: Bool, compressed: Bool) throws {
        let document = try Self.read(.unicode, tagged: tagged, compressed: compressed)

        #expect(document.pageCount == 1)
        #expect(document.pages[0].lines == Self.expectedLines)
        #expect(!document.text.contains("?"))
        #expect(!document.text.contains("\u{FFFD}"))
    }

    @Test("The link keeps its text and its target")
    func linkTextAndTarget() throws {
        let document = try Self.read(.unicode)
        let page = document.pages[0]

        #expect(Set(document.links.map(\.target)) == [.uri("https://example.com/sibenik")])
        // The words that start inside the link's rectangles, in order, are the link text.
        let words = page.links.compactMap { link in
            page.runs.first { run in
                abs(link.x - run.x) < 0.01 && link.y < run.y && run.y < link.y + link.height
            }?.text.trimmingCharacters(in: .whitespaces)
        }
        #expect(words.joined(separator: " ") == Self.linkText)
    }

    @Test("The title and the author come back from the Info dictionary")
    func metadata() throws {
        let document = try Self.read(.unicode)
        #expect(document.title == Self.title)
        #expect(document.author == Self.name)
    }

    @Test("The outline keeps every heading's letters, at its level and on its page")
    func outline() throws {
        let document = try Self.read(.unicode)
        #expect(document.outline.map(\.title) == [Self.name, "Čišćenje, žeđ i đak", "Školovanje"])
        #expect(document.outline.map(\.level) == [1, 2, 3])
        #expect(document.outline.map(\.pageIndex) == [0, 0, 0])
    }

    @Test("A letter typed as a base letter and a combining mark comes back as one letter")
    func decomposedLettersAreComposed() throws {
        // c + U+0301 and Z + U+030C, as a macOS file name or a pasted text can hold them.
        let decomposed = "Mihaljevic\u{301} i Z\u{30C}minj"
        let composed = "Mihaljević i Žminj"
        let options = PDFOptions(title: decomposed, author: decomposed, documentStrings: .unicode)
        let pdf = try MarkdownPDFRenderer(options: options).render(markdown: "# \(decomposed)\n\n\(decomposed).\n")
        let document = try PDFDocumentReader(data: pdf)

        #expect(document.title?.unicodeScalars.elementsEqual(composed.unicodeScalars) == true)
        #expect(document.outline.first?.title.unicodeScalars.elementsEqual(composed.unicodeScalars) == true)
        #expect(document.pages[0].lines.map(\.precomposedStringWithCanonicalMapping) == [composed, "\(composed)."])
    }

    @Test("With WinAnsi strings the page text is still whole, only the strings outside the page lose letters")
    func winAnsiStringsLeaveThePageAlone() throws {
        let document = try Self.read(.winAnsi)
        #expect(document.pages[0].lines == Self.expectedLines)
        #expect(document.author == "Mihaela Mihaljevi? Jaki?")
        #expect(document.outline.first?.title == "Mihaela Mihaljevi? Jaki?")
    }
}
