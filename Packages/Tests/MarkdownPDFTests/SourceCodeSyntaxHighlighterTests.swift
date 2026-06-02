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
        #expect(SourceCodeLanguage(hint: "bash") == .bash)
        #expect(SourceCodeLanguage(hint: "sh") == .bash)
        #expect(SourceCodeLanguage(hint: "yaml") == .yaml)
        #expect(SourceCodeLanguage(hint: "yml") == .yaml)
        #expect(SourceCodeLanguage(hint: "ruby") == .ruby)
        #expect(SourceCodeLanguage(hint: "perl") == .perl)
        #expect(SourceCodeLanguage(hint: "r") == .r)
        #expect(SourceCodeLanguage(hint: "toml") == .toml)
        #expect(SourceCodeLanguage(hint: "ini") == .ini)
        #expect(SourceCodeLanguage(hint: "makefile") == .makefile)
        #expect(SourceCodeLanguage(hint: "dockerfile") == .dockerfile)
        #expect(SourceCodeLanguage(hint: "pascal") == .pascal)
        #expect(SourceCodeLanguage(hint: "delphi") == .pascal)
        #expect(SourceCodeLanguage(hint: "lisp") == .lisp)
        #expect(SourceCodeLanguage(hint: "scheme") == .lisp)
        #expect(SourceCodeLanguage(hint: "sql") == .sql)
        #expect(SourceCodeLanguage(hint: "lua") == .lua)
        #expect(SourceCodeLanguage(hint: "haskell") == .haskell)
        #expect(SourceCodeLanguage(hint: "ada") == .ada)
        #expect(SourceCodeLanguage(hint: "erlang") == .erlang)
        #expect(SourceCodeLanguage(hint: "latex") == .latex)
        #expect(SourceCodeLanguage(hint: "vb") == .visualBasic)
        #expect(SourceCodeLanguage(hint: "xml") == .xml)
        #expect(SourceCodeLanguage(hint: "html") == .xml)
        #expect(SourceCodeLanguage(hint: "plain") == nil)
        #expect(SourceCodeLanguage(hint: nil) == nil)
    }

    @Test("Scans hash-comment language fixtures")
    func scansHashCommentLanguageFixtures() {
        let fixtures: [(language: SourceCodeLanguage, line: String, keyword: String, comment: String)] = [
            (.bash, #"if [ "$name" = "Ada" ]; then # comment"#, "if", "# comment"),
            (.yaml, "enabled: true # comment", "true", "# comment"),
            (.ruby, "def call # comment", "def", "# comment"),
            (.perl, "my $value = 1 # comment", "my", "# comment"),
            (.r, "if (TRUE) # comment", "if", "# comment"),
            (.toml, "enabled = true # comment", "true", "# comment"),
            (.ini, "enabled = yes # comment", "yes", "# comment"),
            (.makefile, "include file.mk # comment", "include", "# comment"),
            (.dockerfile, "FROM swift:latest # comment", "FROM", "# comment"),
        ]

        for fixture in fixtures {
            var highlighter = SourceCodeSyntaxHighlighter(language: fixture.language)
            let tokens = highlighter.tokens(for: fixture.line)

            #expect(tokens.contains(SourceCodeToken(text: fixture.keyword, kind: .keyword)))
            #expect(tokens.contains(SourceCodeToken(text: fixture.comment, kind: .comment)))
        }
    }

    @Test("Scans data-driven line comment fixtures")
    func scansDataDrivenLineCommentFixtures() {
        let fixtures: [(language: SourceCodeLanguage, line: String, keyword: String, comment: String)] = [
            (.lisp, "(defun value () ; comment", "defun", "; comment"),
            (.sql, "SELECT value -- comment", "SELECT", "-- comment"),
            (.lua, "local value = 1 -- comment", "local", "-- comment"),
            (.haskell, "module Main where -- comment", "module", "-- comment"),
            (.ada, "procedure Main is -- comment", "procedure", "-- comment"),
            (.erlang, "case Value of % comment", "case", "% comment"),
            (.latex, #"\\section{Title} % comment"#, "section", "% comment"),
            (.visualBasic, "Dim value As String ' comment", "Dim", "' comment"),
        ]

        for fixture in fixtures {
            var highlighter = SourceCodeSyntaxHighlighter(language: fixture.language)
            let tokens = highlighter.tokens(for: fixture.line)

            #expect(tokens.contains(SourceCodeToken(text: fixture.keyword, kind: .keyword)))
            #expect(tokens.contains(SourceCodeToken(text: fixture.comment, kind: .comment)))
        }
    }

    @Test("Scans Pascal and Lisp block comments across lines")
    func scansPascalAndLispBlockCommentsAcrossLines() {
        var pascalHighlighter = SourceCodeSyntaxHighlighter(language: .pascal)
        let pascalFirstLine = pascalHighlighter.tokens(for: "begin (* block")
        let pascalSecondLine = pascalHighlighter.tokens(for: "continued *) end")
        let pascalBraceLine = pascalHighlighter.tokens(for: "{ brace } var value := 1;")

        #expect(pascalFirstLine.contains(SourceCodeToken(text: "begin", kind: .keyword)))
        #expect(pascalFirstLine.contains(SourceCodeToken(text: "(* block", kind: .comment)))
        #expect(pascalSecondLine.first == SourceCodeToken(text: "continued *)", kind: .comment))
        #expect(pascalSecondLine.contains(SourceCodeToken(text: "end", kind: .keyword)))
        #expect(pascalBraceLine.first == SourceCodeToken(text: "{ brace }", kind: .comment))
        #expect(pascalBraceLine.contains(SourceCodeToken(text: "var", kind: .keyword)))

        var lispHighlighter = SourceCodeSyntaxHighlighter(language: .lisp)
        let lispFirstLine = lispHighlighter.tokens(for: "#| block")
        let lispSecondLine = lispHighlighter.tokens(for: "continued |# (defun value ())")

        #expect(lispFirstLine == [SourceCodeToken(text: "#| block", kind: .comment)])
        #expect(lispSecondLine.first == SourceCodeToken(text: "continued |#", kind: .comment))
        #expect(lispSecondLine.contains(SourceCodeToken(text: "defun", kind: .keyword)))
    }

    @Test("Scans XML tags, strings, and block comments")
    func scansXMLTagsStringsAndBlockComments() {
        var highlighter = SourceCodeSyntaxHighlighter(language: .xml)
        let tagTokens = highlighter.tokens(for: #"<note id="a">&amp;</note>"#)
        let firstCommentLine = highlighter.tokens(for: "<!-- starts")
        let secondCommentLine = highlighter.tokens(for: "continues --> <tag/>")

        #expect(tagTokens.contains(SourceCodeToken(text: "<", kind: .operatorToken)))
        #expect(tagTokens.contains(SourceCodeToken(text: "note", kind: .identifier)))
        #expect(tagTokens.contains(SourceCodeToken(text: "id", kind: .identifier)))
        #expect(tagTokens.contains(SourceCodeToken(text: #""a""#, kind: .string)))
        #expect(firstCommentLine == [SourceCodeToken(text: "<!-- starts", kind: .comment)])
        #expect(secondCommentLine.first == SourceCodeToken(text: "continues -->", kind: .comment))
        #expect(secondCommentLine.contains(SourceCodeToken(text: "tag", kind: .identifier)))
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
