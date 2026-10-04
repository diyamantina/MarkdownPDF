import Foundation

/// Removes HTML comments from Markdown text before it is parsed.
///
/// This is the engine behind ``PDFOptions/IgnoreHTMLComments``. It is a pure function
/// of its input and touches no file, so its behaviour is fully fixed by the rules
/// below.
///
/// ## Rules
///
/// - A comment starts at `<!--` and ends at the first `-->` after it. The text from
///   the opener to the end of the closer is deleted. Comments do not nest: in
///   `<!-- a <!-- b --> c` the comment ends after `b`.
/// - A comment that is never closed is not a comment. Its `<!--` stays as literal
///   text, so a stray opener cannot swallow the rest of the document. `<!-->` is
///   unterminated by the same rule, because the closer must follow the opener.
/// - A comment may span lines. Deleting it joins the text before and after it.
/// - A line that held a comment and is left with nothing but white space is removed
///   entirely, newline included, so a marker such as `<!--print-only-->` on its own
///   line leaves no blank line behind and does not split the paragraph, list or
///   table around it. A line that keeps text after a deletion loses the trailing
///   white space the deletion exposed, so `# Title <!--x-->` becomes `# Title`.
///   Lines that were already blank stay.
/// - Comments inside fenced code blocks are literal text. A fence opens on a line
///   whose first non-container characters are three backticks or three tildes, where
///   the container prefix is any indentation, `>` quote markers and one list marker;
///   it closes on the next line that starts with the same three characters, or never.
///   This is the same test ``MarkdownParser`` applies, so the two agree on what is
///   code.
/// - Comments inside inline code spans are literal text. A run of `n` backticks opens
///   a span only when a run of exactly `n` backticks follows before the paragraph
///   ends (at a blank line); otherwise the backticks are plain text. A backslash
///   escapes the next character, so `\<!--` is no comment and `` \` `` opens no span.
/// - The page break marker `<!-- pagebreak -->` is not a comment for this purpose:
///   a comment whose text, trimmed and compared case-insensitively, is `pagebreak`
///   is kept because the parser needs it.
/// - Line endings are normalized to `\n`, as the parser does anyway.
///
/// Text without any removable comment comes back unchanged apart from that
/// normalization. The scan is linear in the length of the text.
enum HTMLCommentStripper {
    private static let opener = Array("<!--")
    private static let closer = Array("-->")

    static func strip(_ markdown: String) -> String {
        var scanner = Scanner(
            text: Array(
                markdown
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n"),
            ),
        )
        return scanner.run()
    }

    private struct Scanner {
        let text: [Character]
        var position = 0
        var output: [Character] = []
        /// Where the line being written starts in `output`.
        var lineStart = 0
        var lineLostComment = false
        var fence: [Character]?
        /// True once a search for `-->` from some start found none: none can exist
        /// after a later start either, which keeps stray openers linear.
        var noCloserAhead = false
        /// For a backtick run length, the paragraph end up to which a search already
        /// found no closing run. A later start inside that range cannot find one.
        var noSpanCloser: [Int: Int] = [:]
        var cachedParagraph: (start: Int, end: Int)?

        init(text: [Character]) {
            self.text = text
        }

        mutating func run() -> String {
            while position < text.count {
                if position == 0 || text[position - 1] == "\n", copyFenceLine() {
                    continue
                }
                let character = text[position]
                if character == "\n" {
                    endLine()
                } else if character == "\\" {
                    output.append(character)
                    position += 1
                    if position < text.count, text[position] != "\n" {
                        output.append(text[position])
                        position += 1
                    }
                } else if character == "`" {
                    copyBacktickRun()
                } else if character == "<", hasPrefix(HTMLCommentStripper.opener, at: position) {
                    consumeComment()
                } else {
                    output.append(character)
                    position += 1
                }
            }
            finishLine(terminator: false)
            return String(output)
        }

        // MARK: Lines

        mutating func endLine() {
            finishLine(terminator: true)
            position += 1
        }

        /// Closes the line being written. A line that lost a comment and holds only
        /// white space vanishes; one that kept text loses its trailing white space.
        mutating func finishLine(terminator: Bool) {
            if lineLostComment {
                while output.count > lineStart, output[output.count - 1] == " " || output[output.count - 1] == "\t" {
                    output.removeLast()
                }
                if output.count == lineStart {
                    lineLostComment = false
                    return
                }
            }
            if terminator {
                output.append("\n")
            }
            lineStart = output.count
            lineLostComment = false
        }

        // MARK: Fences

        /// Copies the whole line at `position` when it opens, closes or lies inside a
        /// fenced code block, and returns true; returns false for an ordinary line.
        mutating func copyFenceLine() -> Bool {
            let end = lineEnd(from: position)
            let body = contentAfterContainerPrefix(position ..< end)
            if let open = fence {
                if body.starts(with: open) {
                    fence = nil
                }
            } else if body.starts(with: ["`", "`", "`"]) {
                fence = ["`", "`", "`"]
            } else if body.starts(with: ["~", "~", "~"]) {
                fence = ["~", "~", "~"]
            } else {
                return false
            }
            output.append(contentsOf: text[position ..< end])
            if end < text.count {
                output.append("\n")
                position = end + 1
            } else {
                position = end
            }
            lineStart = output.count
            lineLostComment = false
            return true
        }

        /// The line's characters after indentation, quote markers and one list marker.
        func contentAfterContainerPrefix(_ range: Range<Int>) -> ArraySlice<Character> {
            var index = range.lowerBound
            func skipBlanks() {
                while index < range.upperBound, text[index] == " " || text[index] == "\t" {
                    index += 1
                }
            }
            skipBlanks()
            while index < range.upperBound, text[index] == ">" {
                index += 1
                skipBlanks()
            }
            if index < range.upperBound {
                if "-*+".contains(text[index]), index + 1 < range.upperBound, text[index + 1] == " " {
                    index += 2
                } else {
                    var digits = index
                    while digits < range.upperBound, text[digits].isASCII, text[digits].isNumber {
                        digits += 1
                    }
                    if digits > index, digits + 1 < range.upperBound,
                       text[digits] == "." || text[digits] == ")", text[digits + 1] == " "
                    {
                        index = digits + 2
                    }
                }
                skipBlanks()
            }
            return text[index ..< range.upperBound]
        }

        func lineEnd(from start: Int) -> Int {
            var index = start
            while index < text.count, text[index] != "\n" {
                index += 1
            }
            return index
        }

        // MARK: Code spans

        mutating func copyBacktickRun() {
            var length = 0
            while position + length < text.count, text[position + length] == "`" {
                length += 1
            }
            if let close = spanEnd(openedBy: length) {
                output.append(contentsOf: text[position ..< close])
                position = close
            } else {
                output.append(contentsOf: text[position ..< position + length])
                position += length
            }
        }

        /// The index just past the closing run of exactly `length` backticks for a run
        /// of that length at `position`, or nil when the paragraph holds none.
        mutating func spanEnd(openedBy length: Int) -> Int? {
            let end = paragraphEnd(from: position)
            if let absentUntil = noSpanCloser[length], position < absentUntil {
                return nil
            }
            var index = position + length
            while index < end {
                if text[index] == "`" {
                    var run = 0
                    while index + run < end, text[index + run] == "`" {
                        run += 1
                    }
                    if run == length {
                        return index + run
                    }
                    index += run
                } else {
                    index += 1
                }
            }
            noSpanCloser[length] = end
            return nil
        }

        /// The end of the paragraph holding `start`: the newline that begins a blank
        /// line, or the end of the text.
        mutating func paragraphEnd(from start: Int) -> Int {
            if let cached = cachedParagraph, start >= cached.start, start < cached.end {
                return cached.end
            }
            var index = start
            var end = text.count
            while index < text.count {
                if text[index] == "\n" {
                    var next = index + 1
                    while next < text.count, text[next] == " " || text[next] == "\t" {
                        next += 1
                    }
                    if next >= text.count || text[next] == "\n" {
                        end = index
                        break
                    }
                }
                index += 1
            }
            cachedParagraph = (start, end)
            return end
        }

        // MARK: Comments

        mutating func consumeComment() {
            let bodyStart = position + HTMLCommentStripper.opener.count
            guard let closerIndex = firstCloser(from: bodyStart) else {
                output.append(text[position])
                position += 1
                return
            }
            let body = String(text[bodyStart ..< closerIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let afterCloser = closerIndex + HTMLCommentStripper.closer.count
            if body.lowercased() == "pagebreak" {
                output.append(contentsOf: text[position ..< afterCloser])
            } else {
                lineLostComment = true
            }
            position = afterCloser
        }

        mutating func firstCloser(from start: Int) -> Int? {
            if noCloserAhead {
                return nil
            }
            var index = start
            while index + HTMLCommentStripper.closer.count <= text.count {
                if hasPrefix(HTMLCommentStripper.closer, at: index) {
                    return index
                }
                index += 1
            }
            noCloserAhead = true
            return nil
        }

        func hasPrefix(_ pattern: [Character], at index: Int) -> Bool {
            guard index + pattern.count <= text.count else {
                return false
            }
            for offset in pattern.indices where text[index + offset] != pattern[offset] {
                return false
            }
            return true
        }
    }
}
