import Foundation
@testable import MarkdownPDF
import Testing

@Suite("PDF object registry")
struct PDFObjectRegistryTests {
    @Test("Assigns deterministic object references")
    func assignsDeterministicObjectReferences() {
        var registry = PDFObjectRegistry()

        let catalog = registry.reserve()
        let pages = registry.add(Data("<< /Type /Pages >>".utf8))
        registry.set(catalog, body: Data("<< /Type /Catalog /Pages 2 0 R >>".utf8))

        #expect(catalog == PDFSyntax.Reference(objectNumber: 1))
        #expect(pages == PDFSyntax.Reference(objectNumber: 2))
        #expect(registry.count == 2)
    }

    @Test("Serializes objects in registry order")
    func serializesObjectsInRegistryOrder() throws {
        var registry = PDFObjectRegistry()

        let first = registry.reserve()
        let second = registry.add(Data("<< /Second true >>".utf8))
        registry.set(first, body: Data("<< /First \(second.serialized) >>".utf8))
        let text = String(decoding: registry.serializedFile(root: first), as: UTF8.self)
        let firstRange = try #require(text.range(of: "1 0 obj"))
        let secondRange = try #require(text.range(of: "2 0 obj"))

        #expect(text.range(of: "1 0 obj\n<< /First 2 0 R >>") != nil)
        #expect(text.range(of: "2 0 obj\n<< /Second true >>") != nil)
        #expect(firstRange.lowerBound < secondRange.lowerBound)
    }

    @Test("Derives xref offsets, startxref, and trailer size from bytes")
    func derivesXrefOffsetsStartxrefAndTrailerSizeFromBytes() throws {
        var registry = PDFObjectRegistry()
        let root = registry.add(Data("<< /Type /Catalog >>".utf8))
        let data = registry.serializedFile(root: root)
        let text = String(decoding: data, as: UTF8.self)

        let objectOffset = try #require(offset(of: "1 0 obj\n", in: data))
        let xrefOffset = try #require(offset(of: "xref\n", in: data))

        #expect(text.contains("xref\n0 2\n0000000000 65535 f \n"))
        #expect(text.contains("\(Self.xrefEntryLine(offset: objectOffset))trailer"))
        #expect(text.contains("trailer\n<< /Size 2 /Root 1 0 R >>"))
        #expect(text.contains("startxref\n\(xrefOffset)\n%%EOF"))
    }

    private func offset(of marker: String, in data: Data) -> Int? {
        data.range(of: Data(marker.utf8))?.lowerBound
    }

    private static func xrefEntryLine(offset: Int) -> String {
        String(
            format: "%010d 00000 n \n",
            locale: Locale(identifier: "en_US_POSIX"),
            offset,
        )
    }
}
