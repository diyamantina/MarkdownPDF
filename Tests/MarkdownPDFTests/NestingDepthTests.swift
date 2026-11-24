import Foundation
@testable import MarkdownPDF
import Testing

/// A document nested past the limit must degrade to prose and never end the process (MarkdownPDF issue 88).
///
/// Each case is rendered on a thread whose stack is 384 KB, a stack as small as the one of a pool thread, where the crash
/// was found: a list of 33 levels overflowed it in the layout. Measured on the unfixed layout: at 384 KB it ends the
/// process and the guarded layout does not; at 256 KB or less both end it, so the case would prove nothing. The PDF is
/// read back with the library's own reader and must hold the text of the deepest level, so that degrading to prose
/// loses no word.
@Suite("Nesting depth: a deep document degrades to prose")
struct NestingDepthTests {
    /// The stack of the thread a case renders on, in kilobytes: 384 unless `NESTING_STACK_KB` says otherwise (a measurement
    /// of how much stack each level takes sets it lower and finds the depth where the unguarded layout dies).
    private static var stackKilobytes: Int {
        ProcessInfo.processInfo.environment["NESTING_STACK_KB"].flatMap { Int($0) } ?? 384
    }

    /// Renders on a thread of the small stack and carries the bytes (or the error) out through a stream, which the
    /// compiler knows is safe to share between the thread and the test.
    private static func renderOnSmallStack(_ markdown: String) async throws -> Data {
        let (results, sender) = AsyncStream.makeStream(of: Result<Data, any Error>.self)
        let thread = Thread {
            sender.yield(Result { try MarkdownPDFRenderer().render(markdown: markdown) })
            sender.finish()
        }
        thread.stackSize = stackKilobytes * 1024
        thread.start()
        for await result in results {
            return try result.get()
        }
        throw CocoaError(.fileReadUnknown)
    }

    /// A list nested `depth` levels, one item for each level. The input grows with the square of the depth, so the
    /// deepest list of the suite is 1,000 levels (a megabyte); the quotes below reach 10,000 levels on one line.
    private static func nestedList(depth: Int) -> String {
        var text = "Nested list.\n\n"
        for level in 0 ..< depth {
            text += String(repeating: "  ", count: level) + "- level \(level + 1)\n"
        }
        return text
    }

    /// A block quote nested `depth` levels on one line: the form of the hostile input the parser's guard names.
    private static func nestedQuote(depth: Int) -> String {
        "Nested quote.\n\n" + String(repeating: "> ", count: depth) + "bottom \(depth)\n"
    }

    /// A footnote whose body is a quote nested `depth` levels: the third place where the parser nests.
    private static func nestedFootnote(depth: Int) -> String {
        "A sentence with a note.[^1]\n\n[^1]: " + String(repeating: "> ", count: depth) + "note bottom \(depth)\n"
    }

    /// The text of the PDF with every run of white space as one space: a line that wraps between two words must not hide them.
    private static func text(of data: Data) throws -> String {
        try PDFDocumentReader(data: data).text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The depths of the fast suite: both sides of the parser's limit of 32 and of the layout's guard. The extremes are in
    /// `NestingDepthLargeTests`, which the hook does not run (they cost minutes: the input of a list grows with the
    /// square of its depth).
    static let nearTheLimit = [31, 32, 33, 34]

    @Test("a list nested this many levels renders on a small stack and keeps its words", arguments: nearTheLimit)
    func list(depth: Int) async throws {
        try await Self.expectListKeepsItsWords(depth: depth)
    }

    @Test("a quote nested this many levels renders on a small stack and keeps its words", arguments: nearTheLimit)
    func quote(depth: Int) async throws {
        try await Self.expectQuoteKeepsItsWords(depth: depth)
    }

    @Test("a footnote body nested this many levels renders on a small stack and keeps its words", arguments: nearTheLimit)
    func footnote(depth: Int) async throws {
        try await Self.expectFootnoteKeepsItsWords(depth: depth)
    }

    static func expectListKeepsItsWords(depth: Int) async throws {
        let data = try await renderOnSmallStack(nestedList(depth: depth))
        let words = try text(of: data)
        #expect(words.contains("level 1"))
        #expect(words.contains("level \(depth)"), "the deepest item is in the PDF")
    }

    static func expectQuoteKeepsItsWords(depth: Int) async throws {
        let data = try await renderOnSmallStack(nestedQuote(depth: depth))
        #expect(try text(of: data).contains("bottom \(depth)"))
    }

    static func expectFootnoteKeepsItsWords(depth: Int) async throws {
        let data = try await renderOnSmallStack(nestedFootnote(depth: depth))
        #expect(try text(of: data).contains("note bottom \(depth)"))
    }
}
