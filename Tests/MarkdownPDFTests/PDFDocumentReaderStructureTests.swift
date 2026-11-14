import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: a file typed out by hand in this suite, whose words, markers, structure
/// tree and faults are known before the reader sees them, and rendered documents
/// whose options say what the reader must find.
@Suite("PDF document reader: words, conformance markers and structure check")
struct PDFDocumentReaderStructureTests {
    private static let xmp = """
    <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF><rdf:Description>
    <pdfaid:part>2</pdfaid:part>
    <pdfaid:conformance>A</pdfaid:conformance>
    <pdfuaid:part>1</pdfuaid:part>
    </rdf:Description></rdf:RDF></x:xmpmeta>
    """

    private static let content = """
    BT /F1 10 Tf 20 250 Td (ab cd) Tj ET
    BT /F1 10 Tf 44.46 250 Td (ef) Tj ET
    BT /F1 10 Tf 30 250 Td (zz) Tj ET
    BT /F1 10 Tf 20 200 Td /Span << /ActualText (A B) >> BDC (xy) Tj EMC ET
    """

    /// The objects of a one page tagged file. Object 4 is the page content, 7 the
    /// color profile, 12 the Info dictionary.
    private static func objects() -> [String] {
        [
            "<< /Type /Catalog /Pages 2 0 R /Lang (hr-HR) /ViewerPreferences << /DisplayDocTitle true >> /Metadata 6 0 R "
                + "/OutputIntents [<< /Type /OutputIntent /S /GTS_PDFA1 /OutputConditionIdentifier (sRGB) /DestOutputProfile 7 0 R >>] "
                + "/MarkInfo << /Marked true >> /StructTreeRoot 8 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 200 300] /Resources << /Font << /F1 5 0 R >> >> >>",
            "<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>",
            HandWrittenPDF.stream(content),
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
            HandWrittenPDF.stream(xmp, entries: "/Type /Metadata /Subtype /XML"),
            HandWrittenPDF.stream("profile bytes", entries: "/N 3"),
            "<< /Type /StructTreeRoot /K 9 0 R >>",
            "<< /Type /StructElem /S /Document /P 8 0 R /K [10 0 R 11 0 R] >>",
            "<< /Type /StructElem /S /H1 /P 9 0 R /K << /Type /MCR /Pg 3 0 R /MCID 0 >> >>",
            "<< /Type /StructElem /S /Figure /P 9 0 R /Alt (A chart) /K [1 2] >>",
            "<< /Producer (By hand) >>",
        ]
    }

    private static func file(_ change: (inout [String]) -> Void = { _ in }) -> Data {
        var objects = objects()
        change(&objects)
        return HandWrittenPDF.file(objects: objects, trailer: "/Info 12 0 R")
    }

    private static func replacing(_ old: String, with new: String) throws -> Data {
        let text = String(decoding: file(), as: UTF8.self)
        try #require(text.contains(old))
        try #require(old.utf8.count == new.utf8.count, "a replacement of another length would move the objects")
        return Data(text.replacingOccurrences(of: old, with: new).utf8)
    }

    private typealias Issue = PDFDocumentReader.StructureIssue

    // MARK: Words

    @Test("Words are the text between spaces, with the box the font widths give them")
    func wordsOfAHandWrittenPage() throws {
        let words = try PDFDocumentReader(data: Self.file()).pages[0].words

        // Helvetica in the Adobe metrics, in thousandths: a 556, b 556, space 278,
        // c 500, d 556, e 556, f 278, x 500, y 500, z 500.
        let expected = [
            // "ab" ends at the space.
            PDFDocumentReader.Word(x: 20, y: 250, width: 11.12, fontSize: 10, text: "ab"),
            // "cd" starts after 556 + 556 + 278; "ef" is shown by another operator
            // exactly where "cd" ends, at 20 + 24.46, and continues the word.
            PDFDocumentReader.Word(x: 33.9, y: 250, width: 18.9, fontSize: 10, text: "cdef"),
            // "zz" is drawn over the others: it stays its own word.
            PDFDocumentReader.Word(x: 30, y: 250, width: 10, fontSize: 10, text: "zz"),
            // The text of an /ActualText span is one word over what the span draws.
            PDFDocumentReader.Word(x: 20, y: 200, width: 10, fontSize: 10, text: "A B"),
        ]
        try #require(words.count == expected.count)
        for (word, wanted) in zip(words, expected) {
            #expect(word.text == wanted.text)
            #expect(word.y == wanted.y && word.fontSize == wanted.fontSize)
            #expect(abs(word.x - wanted.x) < 1e-9, "\(word.text) starts at \(word.x)")
            #expect(abs(word.width - wanted.width) < 1e-9, "\(word.text) is \(word.width) wide")
        }
    }

    @Test("Words of a rendered page: styled pieces of one word join, table cells and lines do not")
    func wordsOfARenderedPage() throws {
        let markdown = "alpha be**ta**`gam`ma delta\n\n| City | County |\n|---|---|\n| Split | Dalmatia |\n"
        let page = try PDFDocumentReader(data: MarkdownPDFRenderer().render(markdown: markdown)).pages[0]

        #expect(page.words.map(\.text) == ["alpha", "betagamma", "delta", "City", "County", "Split", "Dalmatia"])
        // Words on one line follow each other without touching.
        for (word, next) in zip(page.words, page.words.dropFirst()) where word.y == next.y {
            #expect(word.x + word.width < next.x, "\(word.text) runs into \(next.text)")
        }
        let size = page.size
        #expect(page.words.allSatisfy { $0.x >= 0 && $0.x + $0.width <= size.width && $0.y > 0 && $0.y < size.height })
    }

    // MARK: Markers

    @Test("The version, producer, language, title flag, XMP identifiers, output intent and structure tree read back as typed")
    func markersOfAHandWrittenFile() throws {
        let document = try PDFDocumentReader(data: Self.file())

        #expect(document.version == "1.4")
        #expect(document.producer == "By hand")
        #expect(document.language == "hr-HR")
        #expect(document.displaysDocumentTitle)
        #expect(document.xmpMetadata == Self.xmp)
        #expect(document.pdfAConformance == "2A")
        #expect(document.pdfUAPart == 1)
        #expect(document.outputIntents == [
            PDFDocumentReader.OutputIntent(subtype: "GTS_PDFA1", outputConditionIdentifier: "sRGB", profileComponents: 3),
        ])
        #expect(document.isTagged)
        #expect(document.structure == [
            PDFDocumentReader.StructureElement(type: "Document", alternateText: nil, markedContentCount: 0, children: [
                PDFDocumentReader.StructureElement(type: "H1", alternateText: nil, markedContentCount: 1, children: []),
                PDFDocumentReader.StructureElement(type: "Figure", alternateText: "A chart", markedContentCount: 2, children: []),
            ]),
        ])
        #expect(document.structure[0].flattened.map(\.type) == ["Document", "H1", "Figure"])
    }

    @Test("A file without the markers reads as having none")
    func markersAbsent() throws {
        let document = try PDFDocumentReader(data: HandWrittenPDF.file(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [] /Count 0 >>",
        ]))

        #expect(document.producer == nil)
        #expect(document.language == nil)
        #expect(!document.displaysDocumentTitle)
        #expect(document.xmpMetadata == nil)
        #expect(document.pdfAConformance == nil)
        #expect(document.pdfUAPart == nil)
        #expect(document.outputIntents.isEmpty)
        #expect(document.structure.isEmpty)
        #expect(PDFDocumentReader.structureIssues(in: HandWrittenPDF.file(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [] /Count 0 >>",
        ])).isEmpty)
    }

    @Test("An XMP property written as an attribute is read like one written as an element")
    func xmpAttributeForm() throws {
        let data = Self.file { objects in
            objects[5] = HandWrittenPDF.stream("<rdf:Description pdfaid:part=\"3\" pdfaid:conformance=\"B\"/>", entries: "/Type /Metadata /Subtype /XML")
        }
        let document = try PDFDocumentReader(data: data)
        #expect(document.pdfAConformance == "3B")
        #expect(document.pdfUAPart == nil)
    }

    @Test("A rendered document carries the markers its options ask for, and no others")
    func markersOfRenderedDocuments() throws {
        let markdown = "# Title\n\nBody with a picture.\n"
        let plain = try PDFDocumentReader(data: MarkdownPDFRenderer(options: PDFOptions(title: "T")).render(markdown: markdown))
        #expect(plain.version == "1.4")
        #expect(plain.producer == "MarkdownPDF")
        #expect(plain.pdfAConformance == nil)
        #expect(plain.pdfUAPart == nil)
        #expect(plain.outputIntents.isEmpty)
        #expect(plain.structure.isEmpty)

        let options = PDFOptions(embeddedFonts: .dejaVu, title: "T", taggedPDF: .enabled, conformance: .pdfUA1AndPDFA2A)
        let archival = try PDFDocumentReader(data: MarkdownPDFRenderer(options: options).render(markdown: markdown))
        #expect(archival.pdfAConformance == "2A")
        #expect(archival.pdfUAPart == 1)
        #expect(archival.displaysDocumentTitle)
        #expect(archival.language != nil)
        #expect(archival.outputIntents.map(\.subtype) == ["GTS_PDFA1"])
        #expect(archival.outputIntents.map(\.profileComponents) == [3])
        #expect(archival.fonts.map(\.isEmbedded) == Array(repeating: true, count: archival.fonts.count))
        #expect(!archival.fonts.isEmpty)
        #expect(archival.structure.map(\.type) == ["Document"])
        #expect(archival.structure[0].children.map(\.type) == ["H1", "P"])
        #expect(archival.structure[0].children.allSatisfy { $0.markedContentCount > 0 })
    }

    // MARK: Structure check

    @Test("A sound file has no structure issues, written by hand or rendered")
    func soundFiles() throws {
        #expect(PDFDocumentReader.structureIssues(in: Self.file()) == [])

        let markdown = "# Title\n\nBody **bold** `code` [link](https://example.com).\n\n| A | B |\n|---|---|\n| 1 | \u{3B1} |\n"
        var compressed = PDFOptions(title: "T", taggedPDF: .enabled, conformance: .pdfUA1AndPDFA2A)
        compressed.streamCompression = .enabled
        for options in [PDFOptions(), PDFOptions(title: "T", taggedPDF: .enabled), compressed] {
            let pdf = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
            #expect(PDFDocumentReader.structureIssues(in: pdf) == [])
        }
    }

    @Test("What is not a PDF is one issue that says so")
    func notAPDF() {
        #expect(PDFDocumentReader.structureIssues(in: Data("hello".utf8)) == [
            Issue(object: nil, message: "the PDF is malformed: the file does not start with %PDF-"),
        ])
        #expect(Issue(object: 4, message: "m").description == "object 4: m")
        #expect(Issue(object: nil, message: "m").description == "m")
    }

    @Test("A reference to an object the file does not hold is reported on the object that makes it")
    func danglingReference() {
        let data = Self.file { $0[2] = "<< /Type /Page /Parent 2 0 R /Contents 40 0 R >>" }
        #expect(PDFDocumentReader.structureIssues(in: data) == [
            Issue(object: 3, message: "it refers to object 40, which the file does not hold"),
        ])
    }

    @Test("A page tree node that miscounts its pages, or a page that names another parent, is reported")
    func pageTreeFaults() {
        let miscounted = Self.file { $0[1] = $0[1].replacingOccurrences(of: "/Count 1", with: "/Count 2") }
        #expect(PDFDocumentReader.structureIssues(in: miscounted) == [
            Issue(object: 2, message: "its /Count is 2 and it holds 1 pages"),
        ])

        let orphan = Self.file { $0[2] = "<< /Type /Page /Parent 1 0 R /Contents 4 0 R >>" }
        #expect(PDFDocumentReader.structureIssues(in: orphan) == [
            Issue(object: 3, message: "its /Parent is not object 2, the node that lists it"),
        ])

        let untyped = Self.file { $0[2] = "<< /Parent 2 0 R /Contents 4 0 R >>" }
        #expect(PDFDocumentReader.structureIssues(in: untyped).contains(Issue(object: 3, message: "a page tree node is neither /Pages nor /Page")))
    }

    @Test("A stream whose /Length is too long or too short is reported", arguments: [3, -1])
    func wrongStreamLength(offBy: Int) {
        let data = Self.file { $0[6] = HandWrittenPDF.stream("profile bytes", entries: "/N 3", length: 13 + offBy) }
        #expect(PDFDocumentReader.structureIssues(in: data) == [
            Issue(object: 7, message: "its stream does not end where its /Length says"),
        ])
    }

    @Test("A compressed stream that does not inflate is reported")
    func brokenCompressedStream() {
        let data = Self.file { $0[6] = HandWrittenPDF.stream("not zlib data", entries: "/N 3 /Filter /FlateDecode") }
        #expect(PDFDocumentReader.structureIssues(in: data) == [
            Issue(object: 7, message: "the PDF is malformed: a FlateDecode stream does not inflate"),
        ])
    }

    @Test("A stream in a filter the reader does not decode is not a fault")
    func foreignFilter() {
        let data = Self.file { $0[6] = HandWrittenPDF.stream("jpeg bytes", entries: "/N 3 /Filter /DCTDecode") }
        #expect(PDFDocumentReader.structureIssues(in: data) == [])
    }

    @Test("An object that lacks endobj, or sits under another number, is reported")
    func objectFraming() throws {
        let unclosed = try Self.replacing("/Producer (By hand) >>\nendobj", with: "/Producer (By hand) >>\nendobx")
        #expect(PDFDocumentReader.structureIssues(in: unclosed) == [
            Issue(object: 12, message: "it does not end with endobj"),
        ])

        let renumbered = try Self.replacing("\n5 0 obj\n", with: "\n6 0 obj\n")
        #expect(PDFDocumentReader.structureIssues(in: renumbered) == [
            Issue(object: 5, message: "the cross-reference table points at something that is not this object"),
        ])
    }

    @Test("A missing end of file marker and a /Size that is too small are reported")
    func fileFraming() throws {
        let unterminated = try Self.replacing("%%EOF\n", with: "%%EOX\n")
        #expect(PDFDocumentReader.structureIssues(in: unterminated) == [
            Issue(object: nil, message: "the file does not end with %%EOF"),
        ])

        let short = HandWrittenPDF.file(objects: Self.objects(), trailer: "/Info 12 0 R", size: 5)
        #expect(PDFDocumentReader.structureIssues(in: short) == [
            Issue(object: nil, message: "the trailer /Size 5 does not cover object 12"),
        ])
    }

    @Test("A fault the page reader finds, such as a font the page lacks, is reported too")
    func contentFault() {
        let data = Self.file { $0[3] = HandWrittenPDF.stream("BT /F9 10 Tf (a) Tj ET") }
        #expect(PDFDocumentReader.structureIssues(in: data) == [
            Issue(object: nil, message: "the PDF is malformed: the font /F9 is not in the page resources"),
        ])
    }

    @Test("A rendered file that is cut short or has a byte changed in its table is not sound")
    func damagedRenderedFile() throws {
        let pdf = try MarkdownPDFRenderer().render(markdown: "# Title\n\nBody.\n")
        #expect(PDFDocumentReader.structureIssues(in: pdf) == [])
        #expect(!PDFDocumentReader.structureIssues(in: pdf.prefix(pdf.count / 2)).isEmpty)

        // Move every object one byte by adding a space after the header line.
        var shifted = Array(pdf)
        let lineEnd = try #require(shifted.firstIndex(of: 0x0A))
        shifted.insert(0x20, at: lineEnd)
        #expect(!PDFDocumentReader.structureIssues(in: Data(shifted)).isEmpty)
    }
}
