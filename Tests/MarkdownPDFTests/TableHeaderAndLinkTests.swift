import Foundation
@testable import MarkdownPDF
import Testing

/// Two properties of the printed page that the board work depends on: a table that runs onto another page repeats its header row there, and an inline link
/// of any scheme the page keeps (a web address, a mail address, a corpus address) is a link annotation that leads where the text says.
@Suite("Table header on every page, and links as annotations")
struct TableHeaderAndLinkTests {
    @Test("a table that runs onto the next pages repeats its header row at the top of each")
    func headerRepeats() throws {
        let rows = (1 ... 120).map { "| row \($0) | value \($0) |" }.joined(separator: "\n")
        let markdown = "| Name | Amount |\n|:---|:---|\n\(rows)\n"
        let reader = try PDFDocumentReader(data: MarkdownPDFRenderer().render(markdown: markdown))
        #expect(reader.pages.count > 1)
        for (index, page) in reader.pages.enumerated() {
            let words = page.words.map(\.text)
            #expect(words.contains("Name") && words.contains("Amount"), Comment(rawValue: "page \(index + 1) has no header row"))
        }
    }

    @Test("each link of a kept scheme is an annotation to its address", arguments: [
        "https://example.com/a", "mailto:info@example.com", "apple-docs://swiftui/view", "swift-org://documentation/concurrency", "/contact/",
    ])
    func links(address: String) throws {
        let reader = try PDFDocumentReader(data: MarkdownPDFRenderer().render(markdown: "A [link text](\(address)) in a sentence.\n"))
        let targets = reader.pages.flatMap(\.links).map(\.target)
        #expect(targets.contains(.uri(address)), Comment(rawValue: "\(address): \(targets)"))
    }
}
