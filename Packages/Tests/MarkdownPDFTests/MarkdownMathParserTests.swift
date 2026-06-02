@testable import MarkdownPDF
import Testing

@Suite("Markdown math parser")
struct MarkdownMathParserTests {
    @Test("Parses fixed left right delimiters")
    func parsesFixedLeftRightDelimiters() throws {
        let parser = MarkdownMathParser()

        #expect(try parser.parse(#"\left (\frac{x}{y}\right )"#).linearizedText == "(frac(x, y))")
        #expect(try parser.parse(#"\left\langle{x}\right\rangle"#).linearizedText == "<x>")
        #expect(try parser.parse(#"\left\{\frac{x}{y}\right\}"#).linearizedText == "{frac(x, y)}")
        #expect(try parser.parse(#"\left. x \right."#).linearizedText == "x")
        #expect(try parser.parse(#"\left/x\right\backslash"#).linearizedText == #"/x\"#)
        #expect(try parser.parse(#"\left< x \right>"#).linearizedText == "< x >")
    }

    @Test("Parses nested fixed left right delimiters")
    func parsesNestedFixedLeftRightDelimiters() throws {
        let parsed = try MarkdownMathParser().parse(#"\left(\left[x\right]\right)"#)

        #expect(parsed.linearizedText == "([x])")
    }

    @Test("Rejects malformed left right delimiters")
    func rejectsMalformedLeftRightDelimiters() throws {
        #expect(throws: MarkdownMathParser.ParseError.missingRightDelimiter) {
            try MarkdownMathParser().parse(#"\left(x"#)
        }
        #expect(throws: MarkdownMathParser.ParseError.missingDelimiter("right")) {
            try MarkdownMathParser().parse(#"\left(x\right"#)
        }
    }
}
