import Foundation
@testable import MarkdownPDF
import Testing

@Suite("Document strings")
struct DocumentStringsTests {
    private let name = "Mihaela Mihaljevi\u{0107} Jaki\u{0107}"
    private let nameAsUTF16 = "<FEFF004D0069006800610065006C00610020004D006900680061006C006A00650076006901070020004A0061006B00690107>"

    // MARK: The default

    @Test("The default is Unicode: the strings of the outline and the Info dictionary keep every character")
    func defaultIsUnicode() {
        #expect(PDFOptions().documentStrings == .unicode)
    }

    @Test("An explicit Unicode render is byte identical to the default render")
    func explicitUnicodeMatchesDefault() throws {
        let markdown = "# \(name)\n\n## Logro\u{00F1}o \u{2192} Skopje\n\nBody."
        let implicit = try MarkdownPDFRenderer(
            options: PDFOptions(title: name, taggedPDF: .enabled, author: name),
        ).render(markdown: markdown)
        let explicit = try MarkdownPDFRenderer(
            options: PDFOptions(title: name, taggedPDF: .enabled, author: name, documentStrings: .unicode),
        ).render(markdown: markdown)

        #expect(implicit == explicit)
    }

    /// The owner's fault: the outline of a PDF (the bookmarks in a viewer's sidebar) showed `? The Foundation Š ExtremePackaging` for the heading
    /// that starts with an emoji and holds an em dash: the emoji as `?` and the dash as another letter, because the title was written as 8-bit text.
    /// Read back with our own reader, the title of each outline entry is the heading text.
    @Test("The outline reads back with the emoji and the em dash of the headings", arguments: [
        "\u{1F9E9} The Foundation \u{2014} ExtremePackaging",
        "\u{1F680} Evolving Toward OpenAPI",
        "1. OpenAPI Schema & Code Generation",
        "YAMLMerger \u{2014} Schemas",
        "Mihaljevi\u{0107} \u{201C}quoted\u{201D} \u{20AC}5",
    ])
    func outlineReadsBackWhole(heading: String) throws {
        let data = try MarkdownPDFRenderer().render(markdown: "# \(heading)\n\nBody.\n")
        let document = try PDFDocumentReader(data: data)
        #expect(document.outline.map(\.title) == [heading], Comment(rawValue: "\(document.outline.map(\.title))"))
    }

    @Test("The Info title and author read back whole too")
    func infoReadsBackWhole() throws {
        let data = try MarkdownPDFRenderer(options: PDFOptions(title: "\u{1F9E9} A \u{2014} B", author: name)).render(markdown: "Body.\n")
        let document = try PDFDocumentReader(data: data)
        #expect(document.title == "\u{1F9E9} A \u{2014} B")
        #expect(document.author == name)
    }

    @Test("WinAnsi, asked for, still writes the old bytes: the em dash is one byte and the emoji a question mark")
    func winAnsiAskedFor() throws {
        let data = try MarkdownPDFRenderer(options: PDFOptions(documentStrings: .winAnsi)).render(markdown: "# \u{1F9E9} A \u{2014} B\n\nBody.\n")
        #expect(try PDFDocumentReader(data: data).outline.map(\.title) != ["\u{1F9E9} A \u{2014} B"])
    }

    @Test("WinAnsi still replaces a character it cannot hold")
    func winAnsiReplacesUnencodableCharacter() {
        #expect(PDFSyntax.Value.pdfTextString("Jaki\u{0107}", as: .winAnsi).serialized == "(Jaki?)")
    }

    // MARK: The text string value

    @Test("Unicode writes an ASCII string exactly as WinAnsi does", arguments: ["", "Intro", "A (nested) title \\ with escapes", "Tab\there"])
    func unicodeKeepsASCIIUnchanged(text: String) {
        #expect(
            PDFSyntax.Value.pdfTextString(text, as: .unicode).serialized
                == PDFSyntax.Value.pdfTextString(text, as: .winAnsi).serialized,
        )
    }

    @Test("Unicode writes a non-ASCII string as UTF-16BE with a byte order mark")
    func unicodeWritesUTF16() {
        #expect(PDFSyntax.Value.pdfTextString(name, as: .unicode).serialized == nameAsUTF16)
    }

    @Test("Unicode writes a Latin-1 letter as UTF-16BE too, not as a WinAnsi byte")
    func unicodeWritesLatin1AsUTF16() {
        #expect(PDFSyntax.Value.pdfTextString("\u{00F1}", as: .unicode).serialized == "<FEFF00F1>")
    }

    @Test("Unicode composes a decomposed diacritic before encoding")
    func unicodeComposesDecomposedDiacritic() {
        #expect(PDFSyntax.Value.pdfTextString("e\u{0301}", as: .unicode).serialized == "<FEFF00E9>")
    }

    @Test("Unicode writes a character beyond the basic plane as a surrogate pair")
    func unicodeWritesSurrogatePair() {
        #expect(PDFSyntax.Value.pdfTextString("\u{1F600}", as: .unicode).serialized == "<FEFFD83DDE00>")
    }

    // MARK: Where it applies

    @Test("Unicode applies to the Info title and author, and leaves the producer and XMP alone")
    func unicodeMetadata() {
        let winAnsi = PDFDocumentMetadata(title: name, author: name)
        let unicode = PDFDocumentMetadata(title: name, author: name, documentStrings: .unicode)

        #expect(
            winAnsi.infoDictionary.serialized()
                == "<< /Title (Mihaela Mihaljevi? Jaki?) /Author (Mihaela Mihaljevi? Jaki?) /Producer (MarkdownPDF) >>",
        )
        #expect(
            unicode.infoDictionary.serialized()
                == "<< /Title \(nameAsUTF16) /Author \(nameAsUTF16) /Producer (MarkdownPDF) >>",
        )
        #expect(unicode.xmpData == winAnsi.xmpData)
        #expect(String(decoding: unicode.xmpData, as: UTF8.self).contains(name))
    }

    @Test("Unicode applies to outline titles")
    func unicodeOutlineTitle() throws {
        let destination = PDFNamedDestinations.ResolvedDestination(
            destination: PDFHeadingDestination(name: "name", title: name, level: 1, x: 54, y: 720),
            page: PDFSyntax.Reference(objectNumber: 7),
        )
        let references = [PDFSyntax.Reference(objectNumber: 11)]
        let root = PDFSyntax.Reference(objectNumber: 10)

        let winAnsi = PDFDocumentOutline(destinations: [destination])
            .outlineObjects(root: root, itemReferences: references)
        let unicode = PDFDocumentOutline(destinations: [destination], documentStrings: .unicode)
            .outlineObjects(root: root, itemReferences: references)
        let winAnsiItem = try #require(winAnsi.first { $0.reference.objectNumber == 11 })
        let unicodeItem = try #require(unicode.first { $0.reference.objectNumber == 11 })

        #expect(winAnsiItem.dictionary.serialized().contains("/Title (Mihaela Mihaljevi? Jaki?)"))
        #expect(unicodeItem.dictionary.serialized().contains("/Title \(nameAsUTF16)"))
    }

    @Test("Unicode applies to the alternate description of a tagged element")
    func unicodeAlternateDescription() {
        let attributes = PDFTaggedContent.Attributes(alternateDescription: "Jaki\u{0107}")

        #expect(PDFSyntax.Dictionary(attributes.pdfEntries(documentStrings: .winAnsi)).serialized() == "<< /Alt (Jaki?) >>")
        #expect(PDFSyntax.Dictionary(attributes.pdfEntries(documentStrings: .unicode)).serialized() == "<< /Alt <FEFF004A0061006B00690107> >>")
    }

    // MARK: A whole render

    @Test("A document with only ASCII strings renders the same bytes in both modes")
    func asciiDocumentIsIdenticalInBothModes() throws {
        let markdown = "# Intro\n\n## Details\n\nBody text.\n"
        let winAnsi = try MarkdownPDFRenderer(
            options: PDFOptions(title: "Report", taggedPDF: .enabled, author: "A. Writer"),
        ).render(markdown: markdown)
        let unicode = try MarkdownPDFRenderer(
            options: PDFOptions(title: "Report", taggedPDF: .enabled, author: "A. Writer", documentStrings: .unicode),
        ).render(markdown: markdown)

        #expect(winAnsi == unicode)
    }

    @Test("A Unicode render keeps the name in the Info dictionary and the outline, and stays a valid file")
    func unicodeRenderKeepsName() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(title: name, author: name, documentStrings: .unicode),
        ).render(markdown: "# \(name)\n\nBody.")
        let inspector = PDFInspector(data)

        #expect(inspector.canonicalStructureIssues().isEmpty)
        #expect(inspector.text.contains("/Title \(nameAsUTF16) /Author \(nameAsUTF16)"))
        #expect(inspector.text.components(separatedBy: "/Title \(nameAsUTF16)").count == 3, "the Info title and one outline entry")
        #expect(!inspector.text.contains("Mihaljevi?"))

        PDFValidation.expectSoundStructure(data, name: "document-strings-unicode")
    }

    @Test("The reader reads the Unicode title and author back")
    func readerReadsUnicodeTitle() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(title: name, author: name, documentStrings: .unicode),
        ).render(markdown: "# \(name)\n\nBody.")
        let document = try PDFDocumentReader(data: data)

        #expect(document.title == name)
        #expect(document.author == name)
    }
}
