import Foundation
@testable import MarkdownPDF
import Testing

@Suite("PDF syntax serialization")
struct PDFSyntaxTests {
    @Test("Escapes PDF names")
    func escapesPDFNames() {
        #expect(PDFSyntax.Name("SF Pro/Text#100%").serialized == "/SF#20Pro#2FText#23100#25")
        #expect(PDFSyntax.Name("Cvor").serialized == "/Cvor")
        #expect(PDFSyntax.Name("čvor").serialized == "/#C4#8Dvor")
    }

    @Test("Escapes PDF literal strings")
    func escapesPDFLiteralStrings() {
        #expect(PDFSyntax.LiteralString(#"a(b)\"# + "\n").serialized == #"(a\(b\)\\\n)"#)
        // WinAnsi: NBSP is byte 0xA0 (octal \240); a non-WinAnsi scalar (c-caron)
        // falls back to "?" in the painted bytes (the codepoint is preserved in
        // the page's /ActualText span).
        #expect(PDFSyntax.LiteralString("\u{00A0}").serialized == "(\\240)")
        #expect(PDFSyntax.LiteralString("č").serialized == "(?)")
    }

    @Test("WinAnsi encoding paints representable scalars and falls back otherwise")
    func winAnsiEncodingPaintsRepresentableScalars() {
        let text = "Caf\u{00E9} ni\u{00F1}o NBSP\u{00A0}done \u{201C}quoted\u{201D} \u{20AC} \u{010D} \u{03C0} \u{1F680}"

        // ActualText preserves the original text verbatim, so extraction/copy
        // recovers it even where the painted glyph is a fallback.
        #expect(PDFTextEncoding.portableText(for: text) == text)
        // Painted bytes: accented Latin, NBSP, curly quotes, and euro encode to
        // their CP1252 bytes; c-caron / pi / rocket are not in WinAnsi -> "?".
        #expect(PDFSyntax.LiteralString(text).serialized == "(Caf\\351 ni\\361o NBSP\\240done \\223quoted\\224 \\200 ? ? ?)")
    }

    @Test("Text runs preserve original text and measure the painted glyphs")
    func textRunsPreserveOriginalTextAndMeasurePaintedGlyphs() {
        let text = "Caf\u{00E9} \u{03C0} \u{1F680}"
        let run = PDFTextRun(text: text, font: .helvetica, size: 10)

        #expect(run.text == text)
        // The run preserves the real text for extraction; pi and rocket paint as
        // the fallback glyph, e-acute paints as itself.
        #expect(run.portableText == text)
        #expect(run.width(fontSet: .pdfBase) > 0)
    }

    @Test("Serializes dictionaries, arrays, references, and nulls")
    func serializesDictionariesArraysAndReferences() {
        let reference = PDFSyntax.Reference(objectNumber: 7)
        let dictionary = PDFSyntax.Dictionary([
            .init("Type", .pdfName("Example")),
            .init("Kids", .pdfArray([.reference(reference), .null])),
            .init("Title", .pdfString("A (B)")),
        ])

        #expect(dictionary.serialized() == "<< /Type /Example /Kids [7 0 R null] /Title (A \\(B\\)) >>")
    }

    @Test("Serializes PDF numbers")
    func serializesPDFNumbers() {
        #expect(PDFSyntax.Number(12).serialized == "12")
        #expect(PDFSyntax.Number(12.3456).serialized == "12.346")
    }

    @Test("Serializes stream length from bytes")
    func serializesStreamLengthFromBytes() {
        let stream = PDFSyntax.Stream(
            dictionary: PDFSyntax.Dictionary([
                .init("Subtype", .pdfName("Image")),
            ]),
            data: Data([0, 1, 2, 10]),
        )
        let text = String(decoding: stream.serialized, as: UTF8.self)

        #expect(text.hasPrefix("<< /Subtype /Image /Length 4 >>\nstream\n"))
        #expect(text.hasSuffix("\nendstream"))
    }

    @Test("Stream length replaces caller supplied length")
    func streamLengthReplacesCallerSuppliedLength() {
        let stream = PDFSyntax.Stream(
            dictionary: PDFSyntax.Dictionary([
                .init("Length", .int(99)),
            ]),
            data: Data([1, 2, 3]),
        )
        let text = String(decoding: stream.serialized, as: UTF8.self)

        #expect(text.hasPrefix("<< /Length 3 >>\nstream\n"))
    }

    @Test("Serializes indirect objects")
    func serializesIndirectObjects() {
        let object = PDFSyntax.IndirectObject(
            reference: PDFSyntax.Reference(objectNumber: 3),
            body: Data("<< >>".utf8),
        )

        #expect(String(decoding: object.serialized, as: UTF8.self) == "3 0 obj\n<< >>\nendobj\n")
    }

    @Test("Serializes xref table entries from object references")
    func serializesXrefTableEntriesFromObjectReferences() {
        let xref = PDFSyntax.XrefTable(objectOffsets: [
            (reference: PDFSyntax.Reference(objectNumber: 1), offset: 15),
            (reference: PDFSyntax.Reference(objectNumber: 2, generation: 3), offset: 27),
        ])

        #expect(xref.entries[0] == .freeObjectZero)
        #expect(xref.entries[1].objectNumber == 1)
        #expect(xref.entries[2].generation == 3)
        #expect(xref.serialized == "xref\n0 3\n0000000000 65535 f \n0000000015 00000 n \n0000000027 00003 n \n")
    }
}
