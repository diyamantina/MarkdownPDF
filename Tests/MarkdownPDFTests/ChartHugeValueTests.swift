@testable import MarkdownPDF
import Testing

/// The parser of charts is `ExtendedMarkdown.Core.Chart` (tested in the ExtendedMarkdown package); what is tested here is the
/// drawing of a chart whose values overflow the geometry.
@Suite("Chart drawing with huge values")
struct ChartHugeValueTests {
    @Test("A chart value large enough to overflow the geometry does not crash", arguments: [
        "```mermaid\npie\n    \"w\" : 1e308\n    \"v\" : 1e308\n```\n",
        "```mermaid\npie\n    \"a\" : 1e308\n    \"b\" : 1\n```\n",
        "```chart\ntype: bar\ncategories: A, B\nseries: X = 1e309, 5\n```\n",
        "```chart\ntype: line\ncategories: A\nseries: Y = 1e308\n```\n",
        "```chart\ntype: line\ncategories: A, B\nseries: Y = 9e307, 1.7e308\n```\n",
        "```chart\ntype: scatter\nseries: S = (-1e308,1), (1e308,2)\n```\n",
    ])
    func hugeChartValueDoesNotCrash(_ markdown: String) throws {
        // `2 * pi * value` overflows to Inf, and Inf / (Inf total) is NaN, which
        // reached `Int(NaN)` in the arc segment count and `Int(value.rounded())` in
        // the legend formatter. Both trapped and aborted the whole render.
        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        #expect(!data.isEmpty)

        // Stopping the trap is not enough: a non-finite coordinate must not reach the
        // content stream as a `nan`/`inf` token, which no reader can parse. Assert the
        // drawn operators carry no such token.
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n") {
            let lowered = line.lowercased()
            let hasBadToken = lowered.split(whereSeparator: { $0 == " " })
                .contains { $0 == "nan" || $0 == "inf" || $0 == "-inf" }
            #expect(!hasBadToken, "non-finite operand in content stream: \(line)")
        }
    }
}
