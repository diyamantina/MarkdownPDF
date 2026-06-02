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

    @Test("Parses and linearizes the expanded symbol set")
    func parsesExpandedSymbolSet() throws {
        let parser = MarkdownMathParser()

        #expect(try parser.parse(#"\forall x \in S"#).linearizedText == "forall x in S")
        #expect(try parser.parse(#"a \approx b"#).linearizedText == "a ~= b")
        #expect(try parser.parse(#"x \leftarrow y \Rightarrow z"#).linearizedText == "x <- y => z")
        #expect(try parser.parse(#"\sin x + \cos y"#).linearizedText == "sin x + cos y")
        #expect(try parser.parse(#"A \cup B \cap C"#).linearizedText == "A cup B cap C")
        #expect(try parser.parse(#"\rho \tau \chi"#).linearizedText == "rho tau chi")
    }

    @Test("Treats limit-style operators as big operators with scripts")
    func treatsLimitOperatorsAsBigOperators() throws {
        #expect(try MarkdownMathParser().parse(#"\lim_{x \to 0} f"#).linearizedText == "lim_{x -> 0} f")
    }

    @Test("Parses and linearizes math accents")
    func parsesMathAccents() throws {
        let parser = MarkdownMathParser()

        #expect(try parser.parse(#"\hat{x}"#).linearizedText == "hat(x)")
        #expect(try parser.parse(#"\overline{AB}"#).linearizedText == "overline(AB)")
        #expect(try parser.parse(#"\vec{v}"#).linearizedText == "vec(v)")
        #expect(try parser.parse(#"\bar{y} + \tilde{z}"#).linearizedText == "bar(y) + tilde(z)")
    }
}
