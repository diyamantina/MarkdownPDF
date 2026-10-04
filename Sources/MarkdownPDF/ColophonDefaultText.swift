import Foundation

/// The blocks of the default colophon page. See ``PDFOptions/Colophon`` for the
/// Markdown they stand for.
///
/// The blocks are built directly, not parsed from a Markdown string, so a title or
/// an author that contains `*`, `_`, brackets or backslashes is drawn literally
/// instead of being read as Markup.
enum ColophonDefaultText {
    static let sourceURL = "https://codeberg.org/MarkdownPdfHQ/MarkdownPDF"

    static let description = "This edition was typeset with MarkdownPDF, a pure Swift Markdown to PDF renderer written by "
        + "Mihaela Mihaljevic. MarkdownPDF parses the Markdown, lays out the pages and writes the PDF bytes itself, "
        + "with no browser, no word processor and no LaTeX."

    static func blocks(title: String?, author: String?) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = [.heading(level: 1, content: [.text("Colophon")])]
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let author = author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (title.isEmpty, author.isEmpty) {
        case (false, false):
            blocks.append(.paragraph([.emphasis([.text(title)]), .text(" by \(author).")]))
        case (false, true):
            blocks.append(.paragraph([.emphasis([.text(title)]), .text(".")]))
        case (true, false):
            blocks.append(.paragraph([.text("By \(author).")]))
        case (true, true):
            break
        }
        blocks.append(.paragraph([.text(description)]))
        blocks.append(.paragraph([
            .text("MarkdownPDF is open source: "),
            .link(children: [.text(sourceURL)], destination: sourceURL, title: nil),
        ]))
        return blocks
    }
}
