import Foundation
import MarkdownPDF
import Testing

/// The corpus: every Markdown document of the fixtures and of the repository's own documents, rendered under five option sets, each
/// result written to a file so that two runs (before and after a change) can be compared byte for byte with `diff -r`.
///
/// It runs only when the environment variable `CORPUS_OUT` names a folder, and is reported as skipped otherwise: a skipped
/// test is named, never silent. A render that throws is written too, as `<name>.<set>.error.txt` holding the error's text, so that
/// every case is a file: rendered or failed with a reason.
///
/// Excluded on purpose: the two external fixtures with images (`us-patent-8130226`, `wwdc-2019-613-ray-tracing-with-metal`), whose
/// large stress render is 35 MB and is held by its own test.
@Suite("Corpus: byte-for-byte before and after")
struct CorpusTests {
    static let outputFolder = ProcessInfo.processInfo.environment["CORPUS_OUT"]

    /// The five option sets, named; the name is part of the output file name.
    static var optionSets: [(name: String, options: PDFOptions)] {
        var plain = PDFOptions()
        plain.title = nil
        var mathAndCode = PDFOptions()
        mathAndCode.mathTypesetting = .enabled
        mathAndCode.codeSyntaxHighlighting = .enabled
        var contents = PDFOptions()
        contents.baseFontSize = 12
        contents.tableOfContents = .enabled
        var tagged = PDFOptions()
        tagged.taggedPDF = .enabled
        // Tagged content without a conformance profile: a profile needs a title and embedded fonts, and refuses a document without them
        // (missingConformanceTitle, unembeddedBaseFontsForConformance), which would make the whole set one error text.
        tagged.title = "Corpus document"
        var loose = PDFOptions()
        loose.outlineMaxHeadingLevel = 2
        loose.lineHeightScale = 1.2
        loose.omitUndrawableEmoji = true
        return [("default", plain), ("math-code", mathAndCode), ("contents", contents), ("tagged", tagged), ("loose", loose)]
    }

    /// The repository root, found from this file's place: Tests/MarkdownPDFTests/CorpusTests.swift.
    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The documents, as paths relative to the root, sorted: fixtures and showcase fixtures (not the external ones), and the root documents.
    static func documents() throws -> [String] {
        let fileManager = FileManager.default
        var found: [String] = []
        for folder in ["Tests/MarkdownPDFTests/Fixtures", "Tests/MarkdownPDFTests/Fixtures/showcase"] {
            let names = try fileManager.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)
            for name in names where name.hasSuffix(".md") {
                found.append(folder + "/" + name)
            }
        }
        for name in ["README.md", "CHANGELOG.md", "CONTRIBUTING.md", "SECURITY.md", "SUPPORT.md", "Docs/NOT-VERIFIED.md"] {
            if fileManager.fileExists(atPath: root.appendingPathComponent(name).path) {
                found.append(name)
            }
        }
        return found.sorted()
    }

    /// Documents built in code that reach the parser's nesting limit (`MarkdownParser.maximumNestingDepth`, 32) from both sides: a list
    /// and a block quote nested 30, 31, 32, 33 and 34 levels. Without them no document of the corpus nests that deep, and a change of
    /// the limit (31 for 32) would be invisible to the comparison. A footnote body also nests through the same guard (a third site
    /// in the parser); it is not generated here, and that is a named gap of this corpus.
    static func nestedDocuments() -> [(name: String, markdown: String)] {
        var found: [(name: String, markdown: String)] = []
        for depth in [30, 31, 32, 33, 34] {
            var list = "Nested list, \(depth) levels.\n\n"
            for level in 0 ..< depth {
                list += String(repeating: "  ", count: level) + "- level \(level + 1)\n"
            }
            found.append(("generated-list-depth-\(depth).md", list))
            var quote = "Nested quote, \(depth) levels.\n\n"
            for level in 1 ... depth {
                quote += String(repeating: "> ", count: level) + "quote level \(level)\n"
            }
            found.append(("generated-quote-depth-\(depth).md", quote))
        }
        return found
    }

    @Test(
        "every document under every option set is written to a file",
        .enabled(if: CorpusTests.outputFolder != nil, "set CORPUS_OUT to a folder to write the corpus"),
    )
    func writeCorpus() throws {
        let out = try #require(Self.outputFolder)
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let documents = try Self.documents()
        #expect(documents.count >= 30, "the corpus has \(documents.count) documents")
        for (name, markdown) in Self.nestedDocuments() {
            for (setName, options) in Self.optionSets {
                let target = out + "/" + name + "." + setName
                do {
                    let data = try MarkdownPDFRenderer(options: options).render(markdown: markdown)
                    try data.write(to: URL(fileURLWithPath: target + ".pdf"))
                } catch {
                    try String(describing: error).write(toFile: target + ".error.txt", atomically: true, encoding: .utf8)
                }
            }
        }
        for path in documents {
            let url = Self.root.appendingPathComponent(path)
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let base = url.deletingLastPathComponent()
            let flat = path.replacingOccurrences(of: "/", with: "__")
            for (name, options) in Self.optionSets {
                let target = out + "/" + flat + "." + name
                do {
                    let data = try MarkdownPDFRenderer(options: options).render(markdown: markdown, assetsBaseURL: base)
                    try data.write(to: URL(fileURLWithPath: target + ".pdf"))
                } catch {
                    try String(describing: error).write(toFile: target + ".error.txt", atomically: true, encoding: .utf8)
                }
            }
        }
    }
}
