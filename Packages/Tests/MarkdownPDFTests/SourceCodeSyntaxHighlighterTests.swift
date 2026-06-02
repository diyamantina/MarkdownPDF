@testable import MarkdownPDF
import Testing

@Suite("Source code syntax highlighter")
struct SourceCodeSyntaxHighlighterTests {
    @Test("Scans Swift token categories")
    func scansSwiftTokenCategories() {
        var highlighter = SourceCodeSyntaxHighlighter(language: .swift)
        let tokens = highlighter.tokens(for: #"let value = "record" + 42 // comment"#)

        #expect(tokens.contains(SourceCodeToken(text: "let", kind: .keyword)))
        #expect(tokens.contains(SourceCodeToken(text: "value", kind: .identifier)))
        #expect(tokens.contains(SourceCodeToken(text: "=", kind: .operatorToken)))
        #expect(tokens.contains(SourceCodeToken(text: #""record""#, kind: .string)))
        #expect(tokens.contains(SourceCodeToken(text: "+", kind: .operatorToken)))
        #expect(tokens.contains(SourceCodeToken(text: "42", kind: .number)))
        #expect(tokens.contains(SourceCodeToken(text: "// comment", kind: .comment)))
    }

    @Test("Scans punctuation and block comments across lines")
    func scansPunctuationAndBlockCommentsAcrossLines() {
        var highlighter = SourceCodeSyntaxHighlighter(language: .cFamily)
        let firstLine = highlighter.tokens(for: #"struct Record { /* starts"#)
        let secondLine = highlighter.tokens(for: #"comment */ int value = 7; }"#)

        #expect(firstLine.contains(SourceCodeToken(text: "struct", kind: .keyword)))
        #expect(firstLine.contains(SourceCodeToken(text: "{", kind: .punctuation)))
        #expect(firstLine.contains(SourceCodeToken(text: "/* starts", kind: .comment)))
        #expect(secondLine.first == SourceCodeToken(text: "comment */", kind: .comment))
        #expect(secondLine.contains(SourceCodeToken(text: "int", kind: .keyword)))
        #expect(secondLine.contains(SourceCodeToken(text: "7", kind: .number)))
        #expect(secondLine.contains(SourceCodeToken(text: ";", kind: .punctuation)))
        #expect(secondLine.contains(SourceCodeToken(text: "}", kind: .punctuation)))
    }

    @Test("Recognizes only supported language hints")
    func recognizesSupportedLanguageHints() {
        #expect(SourceCodeLanguage(hint: "swift") == .swift)
        #expect(SourceCodeLanguage(hint: "metal") == .cFamily)
        #expect(SourceCodeLanguage(hint: "python") == .python)
        #expect(SourceCodeLanguage(hint: "json") == .json)
        #expect(SourceCodeLanguage(hint: "plain") == nil)
        #expect(SourceCodeLanguage(hint: nil) == nil)
    }

    @Test("Keeps numeric operators separate from number tokens")
    func keepsNumericOperatorsSeparateFromNumberTokens() {
        var highlighter = SourceCodeSyntaxHighlighter(language: .swift)
        let tokens = highlighter.tokens(for: "let value = 1+2-3 * 4 / 5")

        #expect(tokens.contains(SourceCodeToken(text: "1", kind: .number)))
        #expect(tokens.contains(SourceCodeToken(text: "+", kind: .operatorToken)))
        #expect(tokens.contains(SourceCodeToken(text: "2", kind: .number)))
        #expect(tokens.contains(SourceCodeToken(text: "-", kind: .operatorToken)))
        #expect(tokens.contains(SourceCodeToken(text: "3", kind: .number)))
        #expect(!tokens.contains(SourceCodeToken(text: "1+2-3", kind: .number)))
    }

    @Test("Keeps ranges and exponents distinct")
    func keepsRangesAndExponentsDistinct() {
        var highlighter = SourceCodeSyntaxHighlighter(language: .swift)
        let tokens = highlighter.tokens(for: "let values = 0..<18 + 1.5e-2 + 0x2A")

        #expect(tokens.contains(SourceCodeToken(text: "0", kind: .number)))
        #expect(tokens.contains(SourceCodeToken(text: "..<", kind: .operatorToken)))
        #expect(tokens.contains(SourceCodeToken(text: "18", kind: .number)))
        #expect(tokens.contains(SourceCodeToken(text: "1.5e-2", kind: .number)))
        #expect(tokens.contains(SourceCodeToken(text: "0x2A", kind: .number)))
        #expect(!tokens.contains(SourceCodeToken(text: "0..", kind: .number)))
    }
}
