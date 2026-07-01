import Foundation

enum SourceCodeLanguage: Equatable {
    case swift
    case cFamily
    case python
    case json
    case bash
    case yaml
    case ruby
    case perl
    case r
    case toml
    case ini
    case makefile
    case dockerfile
    case pascal
    case lisp
    case sql
    case lua
    case haskell
    case ada
    case erlang
    case latex
    case visualBasic
    case xml

    init?(hint: String?) {
        guard let rawHint = hint?
            .split(whereSeparator: \.isWhitespace)
            .first?
            .lowercased()
        else {
            return nil
        }

        let normalized = rawHint.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch normalized {
        case "swift":
            self = .swift
        case "c", "h", "cc", "cpp", "c++", "hpp", "metal", "msl", "java", "javascript", "js", "typescript", "ts", "rust", "rs", "go", "csharp", "cs":
            self = .cFamily
        case "python", "py":
            self = .python
        case "json":
            self = .json
        case "bash", "sh", "shell", "zsh":
            self = .bash
        case "yaml", "yml":
            self = .yaml
        case "ruby", "rb":
            self = .ruby
        case "perl", "pl", "pm":
            self = .perl
        case "r":
            self = .r
        case "toml":
            self = .toml
        case "ini", "cfg", "conf":
            self = .ini
        case "make", "makefile":
            self = .makefile
        case "dockerfile", "docker":
            self = .dockerfile
        case "pascal", "delphi", "pp":
            self = .pascal
        case "lisp", "scheme", "clojure", "clj", "elisp":
            self = .lisp
        case "sql":
            self = .sql
        case "lua":
            self = .lua
        case "haskell", "hs":
            self = .haskell
        case "ada", "adb", "ads":
            self = .ada
        case "erlang", "erl":
            self = .erlang
        case "latex", "tex":
            self = .latex
        case "vb", "vbs", "visualbasic", "visual-basic":
            self = .visualBasic
        case "xml", "html", "xhtml", "svg":
            self = .xml
        default:
            return nil
        }
    }

    func isKeyword(_ text: String) -> Bool {
        if keywords.contains(text) {
            return true
        }
        return isCaseInsensitive && keywords.contains(text.lowercased())
    }

    var keywords: Set<String> {
        switch self {
        case .swift:
            [
                "actor", "as", "associatedtype", "async", "await", "break",
                "case", "catch", "class", "continue", "defer", "do", "else",
                "enum", "extension", "false", "for", "func", "guard", "if",
                "import", "in", "init", "inout", "let", "nil", "private",
                "protocol", "public", "return", "self", "static", "struct",
                "switch", "throw", "throws", "true", "try", "var", "where",
                "while",
            ]
        case .cFamily:
            [
                "auto", "bool", "break", "case", "class", "const", "continue",
                "default", "device", "do", "double", "else", "enum", "false",
                "float", "float2", "float3", "float4", "for", "func", "if",
                "int", "kernel", "let", "long", "namespace", "private",
                "public", "return", "short", "static", "struct", "switch",
                "template", "this", "thread", "true", "uint", "using", "var",
                "void", "while",
            ]
        case .python:
            [
                "and", "as", "async", "await", "break", "class", "continue",
                "def", "elif", "else", "except", "False", "finally", "for",
                "from", "if", "import", "in", "is", "lambda", "None", "not",
                "or", "pass", "raise", "return", "True", "try", "while",
                "with", "yield",
            ]
        case .json:
            ["false", "null", "true"]
        case .bash:
            [
                "case", "do", "done", "elif", "else", "esac", "export", "fi",
                "for", "function", "if", "in", "local", "select", "then",
                "until", "while",
            ]
        case .yaml:
            ["false", "no", "null", "off", "on", "true", "yes"]
        case .ruby:
            [
                "begin", "break", "case", "class", "def", "do", "else",
                "elsif", "end", "false", "if", "module", "nil", "return",
                "self", "then", "true", "unless", "until", "when", "while",
                "yield",
            ]
        case .perl:
            [
                "else", "elsif", "foreach", "if", "last", "my", "next", "our",
                "package", "return", "sub", "unless", "until", "use", "while",
            ]
        case .r:
            [
                "else", "FALSE", "for", "function", "if", "in", "NA", "NULL",
                "repeat", "return", "TRUE", "while",
            ]
        case .toml:
            ["false", "true"]
        case .ini:
            ["false", "no", "off", "on", "true", "yes"]
        case .makefile:
            ["define", "else", "endef", "endif", "export", "if", "ifdef", "ifeq", "ifndef", "ifneq", "include", "override", "private", "unexport", "vpath"]
        case .dockerfile:
            [
                "add", "arg", "cmd", "copy", "entrypoint", "env", "expose",
                "from", "healthcheck", "label", "maintainer", "onbuild", "run",
                "shell", "stopsignal", "user", "volume", "workdir",
            ]
        case .pascal:
            [
                "and", "array", "begin", "case", "class", "const", "div", "do",
                "downto", "else", "end", "false", "for", "function", "if",
                "implementation", "interface", "mod", "nil", "not", "of", "or",
                "procedure", "program", "record", "repeat", "then", "to",
                "true", "type", "unit", "until", "uses", "var", "while",
            ]
        case .lisp:
            [
                "defmacro", "defun", "if", "lambda", "let", "let*", "nil",
                "progn", "quote", "setf", "t",
            ]
        case .sql:
            [
                "and", "as", "by", "create", "delete", "false", "from", "group",
                "having", "insert", "into", "join", "left", "not", "null", "on",
                "or", "order", "right", "select", "set", "table", "true",
                "update", "values", "where",
            ]
        case .lua:
            [
                "and", "break", "do", "else", "elseif", "end", "false", "for",
                "function", "goto", "if", "in", "local", "nil", "not", "or",
                "repeat", "return", "then", "true", "until", "while",
            ]
        case .haskell:
            [
                "case", "class", "data", "deriving", "do", "else", "if",
                "import", "in", "infix", "instance", "let", "module", "newtype",
                "of", "then", "type", "where",
            ]
        case .ada:
            [
                "abort", "abs", "accept", "access", "all", "and", "array", "at",
                "begin", "body", "case", "constant", "declare", "delay", "delta",
                "digits", "do", "else", "elsif", "end", "entry", "exception",
                "exit", "for", "function", "generic", "if", "in", "is",
                "limited", "loop", "mod", "new", "not", "null", "of", "or",
                "others", "out", "package", "pragma", "private", "procedure",
                "raise", "range", "record", "rem", "renames", "return",
                "reverse", "select", "separate", "subtype", "tagged", "task",
                "then", "type", "until", "use", "when", "while", "with", "xor",
            ]
        case .erlang:
            ["after", "begin", "case", "catch", "end", "fun", "if", "of", "receive", "try", "when"]
        case .latex:
            ["begin", "documentclass", "end", "include", "input", "newcommand", "section", "usepackage"]
        case .visualBasic:
            [
                "as", "boolean", "byref", "byval", "class", "dim", "do", "else",
                "elseif", "end", "false", "for", "function", "if", "integer",
                "loop", "module", "new", "next", "not", "nothing", "or",
                "private", "public", "return", "string", "sub", "then", "true",
                "while",
            ]
        case .xml:
            []
        }
    }

    var lineCommentPrefixes: [String] {
        switch self {
        case .swift, .cFamily, .pascal:
            ["//"]
        case .python, .bash, .yaml, .ruby, .perl, .r, .toml, .ini, .makefile, .dockerfile:
            ["#"]
        case .lisp:
            [";"]
        case .sql, .lua, .haskell, .ada:
            ["--"]
        case .erlang, .latex:
            ["%"]
        case .visualBasic:
            ["'"]
        case .json, .xml:
            []
        }
    }

    var blockCommentDelimiters: [SourceCodeBlockCommentDelimiter] {
        switch self {
        case .swift, .cFamily:
            [SourceCodeBlockCommentDelimiter(start: "/*", end: "*/")]
        case .pascal:
            [
                SourceCodeBlockCommentDelimiter(start: "(*", end: "*)"),
                SourceCodeBlockCommentDelimiter(start: "{", end: "}"),
            ]
        case .lisp:
            [SourceCodeBlockCommentDelimiter(start: "#|", end: "|#")]
        case .lua:
            [SourceCodeBlockCommentDelimiter(start: "--[[", end: "]]")]
        case .haskell:
            [SourceCodeBlockCommentDelimiter(start: "{-", end: "-}")]
        case .xml:
            [SourceCodeBlockCommentDelimiter(start: "<!--", end: "-->")]
        case .python, .json, .bash, .yaml, .ruby, .perl, .r, .toml, .ini, .makefile, .dockerfile, .sql, .ada, .erlang, .latex, .visualBasic:
            []
        }
    }

    var isCaseInsensitive: Bool {
        switch self {
        case .swift, .cFamily, .python, .json, .bash, .yaml, .ruby, .perl, .r, .toml, .ini, .makefile, .lisp, .lua, .haskell, .latex, .xml:
            false
        case .dockerfile, .pascal, .sql, .ada, .erlang, .visualBasic:
            true
        }
    }

    var operatorCharacters: Set<Character> {
        ["=", "+", "-", "*", "/", "%", "<", ">", "!", "&", "|", "^", "~", "?", ":", "."]
    }

    var punctuationCharacters: Set<Character> {
        ["{", "}", "[", "]", "(", ")", ",", ";"]
    }
}
