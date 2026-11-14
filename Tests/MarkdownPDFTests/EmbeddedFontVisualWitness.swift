import Foundation
@testable import MarkdownPDF
import Testing

/// The witness battery for embedded-font renders, on the package's own reader.
///
/// A viewer advances glyphs by the widths the font dictionary declares (the CID
/// `/W` array), not by the font program, so a wrong width array garbles a page
/// that still extracts as the right text (see #194). `PDFDocumentReader` builds
/// its word boxes from those declared widths and from the position of every text
/// operator, so the width class of bug shows here as words that overlap on a line
/// or leave the page. The battery therefore checks, from the bytes of the file:
/// the structure, the extracted text, and the word-box layout.
///
/// What it cannot check is that a second renderer paints the same ink: that step
/// needed two outside rasterizers and is tracked in `Docs/NOT-VERIFIED.md`.
func assertEmbeddedFontVisualWitness(
    _ data: Data,
    name: String,
    expectedSubstrings: [String],
    minWords: Int = 1,
    sourceLocation: SourceLocation = #_sourceLocation,
) throws {
    try PDFValidation.writeArtifact(data, name: "\(name).pdf")

    // 1. Structural validity.
    try PDFValidation.requireSoundStructure(data, name: name, sourceLocation: sourceLocation)
    let document = try PDFDocumentReader(data: data)
    try #require(document.pageCount >= 1, "\(name): rendered no pages", sourceLocation: sourceLocation)
    #expect(document.pageCount == PDFInspector(data).pageCount, "\(name): the reader and the inspector count different pages", sourceLocation: sourceLocation)

    // 2. Content extraction.
    try PDFValidation.writeTextArtifact(document.text, name: "\(name)/text.txt")
    let extracted = document.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    for substring in expectedSubstrings {
        #expect(
            extracted.contains(substring),
            "\(name): expected extracted text to contain \"\(substring)\":\n\(document.text)",
            sourceLocation: sourceLocation,
        )
    }

    // 3. Word-box geometry from the declared widths: words that overlap on a
    //    line, collide across lines, or leave the page (text falling out of
    //    tables). This is the check that catches #194.
    let layout = ReaderTextLayout(document)
    try PDFValidation.writeTextArtifact(layout.tabSeparated, name: "\(name)/words.tsv")
    let layoutIssues = layout.visualLayoutIssues()
    #expect(
        layout.words.count >= minWords,
        "\(name): expected at least \(minWords) words, got \(layout.words.count)",
        sourceLocation: sourceLocation,
    )
    #expect(
        layoutIssues.isEmpty,
        "\(name): word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
        sourceLocation: sourceLocation,
    )
}
