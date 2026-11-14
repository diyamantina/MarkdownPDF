import Foundation
@testable import MarkdownPDF
import Testing

@Suite("Document strings")
struct DocumentStringsTests {
    private let name = "Mihaela Mihaljevi\u{0107} Jaki\u{0107}"
    private let nameAsUTF16 = "<FEFF004D0069006800610065006C00610020004D006900680061006C006A00650076006901070020004A0061006B00690107>"

    // MARK: The default

    @Test("The default is WinAnsi")
    func defaultIsWinAnsi() {
        #expect(PDFOptions().documentStrings == .winAnsi)
    }

    @Test("An explicit WinAnsi render is byte identical to the default render")
    func explicitWinAnsiMatchesDefault() throws {
        let markdown = "# \(name)\n\n## Logro\u{00F1}o \u{2192} Skopje\n\nBody."
        let implicit = try MarkdownPDFRenderer(
            options: PDFOptions(title: name, taggedPDF: .enabled, author: name),
        ).render(markdown: markdown)
        let explicit = try MarkdownPDFRenderer(
            options: PDFOptions(title: name, taggedPDF: .enabled, author: name, documentStrings: .winAnsi),
        ).render(markdown: markdown)

        #expect(implicit == explicit)
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

        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "document-strings-unicode-qpdf")
        #expect(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
    }

    @Test("pdfinfo reads the Unicode title and author back")
    func pdfinfoReadsUnicodeTitle() throws {
        let data = try MarkdownPDFRenderer(
            options: PDFOptions(title: name, author: name, documentStrings: .unicode),
        ).render(markdown: "# \(name)\n\nBody.")
        let result = try PDFValidation.pdfinfo(data: data, name: "document-strings-unicode-info")
        let info = PDFValidation.parsedInfo(from: result)

        #expect(result.exitCode == 0, "pdfinfo failed:\n\(result.output)")
        #expect(info["Title"] == name, "Unexpected pdfinfo output:\n\(result.output)")
        #expect(info["Author"] == name, "Unexpected pdfinfo output:\n\(result.output)")
    }
}
