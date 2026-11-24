import Foundation
@testable import MarkdownPDF
import Testing

/// The extremes of the nesting test: 100 to 10,000 levels. They are slow (the input of a list grows with the square of its
/// depth: 1,000 levels is a megabyte), so the pre-push hook does not run them; `scripts/heavy-suites.txt` lists this suite
/// and the heavy script runs it. The cases near the limit are in `NestingDepthTests`.
@Suite("Nesting depth, the extremes: 100 to 10,000 levels degrade to prose")
struct NestingDepthLargeTests {
    @Test("a list nested this many levels renders on a small stack and keeps its words", arguments: [100, 1000])
    func list(depth: Int) async throws {
        try await NestingDepthTests.expectListKeepsItsWords(depth: depth)
    }

    @Test("a quote nested this many levels renders on a small stack and keeps its words", arguments: [100, 1000, 10000])
    func quote(depth: Int) async throws {
        try await NestingDepthTests.expectQuoteKeepsItsWords(depth: depth)
    }

    @Test("a footnote body nested this many levels renders on a small stack and keeps its words", arguments: [100, 1000, 10000])
    func footnote(depth: Int) async throws {
        try await NestingDepthTests.expectFootnoteKeepsItsWords(depth: depth)
    }
}
