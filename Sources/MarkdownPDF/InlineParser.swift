import Foundation

struct InlineParser {
    var options: MarkdownParser.Options = .init()

    func parse(_ text: String) -> [MarkdownInline] {
        var parser = Scanner(source: text, options: options)
        return parser.parse()
    }

    private struct Scanner {
        var source: String
        var index: String.Index
        var options: MarkdownParser.Options

        /// For each close character, the earliest index from which it is known to be
        /// absent through the end of the source.
        ///
        /// Every opener that fails to find its closer scans to the end, and
        /// `consumeText` then advances a single character, so a run of unmatched
        /// openers (`[[[…`, `<<<…`, `[a]([a](…`) re-scanned the whole tail per
        /// character: O(n^2), a few KB of one byte wedging the parser for seconds.
        /// A close char absent from index i is absent from every j > i, so one
        /// recorded absence short-circuits every later scan. Soundness for the
        /// escape-aware `]` scan: two starts i < j can disagree on whether a given
        /// `]` is escaped only if j lands strictly inside the backslash run before
        /// it, i.e. the character before j is `\`. Every scan start is one or two
        /// positions past an opener, so the character before it is always `[`, `^`,
        /// `(`, `<`, or a backtick, never `\`. Escape parity past j is therefore
        /// start-invariant. The other three scans are plain substring searches, for
        /// which absence is trivially monotone.
        private var absentCloseFrom: [Character: String.Index] = [:]

        init(source: String, options: MarkdownParser.Options) {
            self.source = source
            self.options = options
            index = source.startIndex
        }

        /// The next occurrence of `character` at or after `start`, or nil when none
        /// remains. `unescaped` selects the backslash-aware scan used for `]`.
        private mutating func nextClose(
            _ character: Character,
            from start: String.Index,
            unescaped: Bool,
        ) -> String.Index? {
            if let known = absentCloseFrom[character], start >= known {
                return nil
            }
            let found = unescaped
                ? firstUnescaped(character, from: start)
                : source[start...].firstIndex(of: character)
            if found == nil {
                absentCloseFrom[character] = start
            }
            return found
        }

        mutating func parse() -> [MarkdownInline] {
            var result: [MarkdownInline] = []

            while index < source.endIndex {
                if consume("  \n") {
                    result.append(.lineBreak)
                } else if consume("\n") {
                    result.append(.softBreak)
                } else if let escaped = parseEscape() {
                    result.append(escaped)
                } else if let image = parseImage() {
                    result.append(image)
                } else if let footnote = parseFootnoteReference() {
                    result.append(footnote)
                } else if let link = parseLink() {
                    result.append(link)
                } else if let code = parseCodeSpan() {
                    result.append(code)
                } else if let math = parseInlineMath() {
                    result.append(math)
                } else if let strong = parseDelimited(marker: "**", transform: MarkdownInline.strong) {
                    result.append(strong)
                } else if let strong = parseDelimited(marker: "__", transform: MarkdownInline.strong) {
                    result.append(strong)
                } else if let strike = parseDelimited(marker: "~~", transform: MarkdownInline.strikethrough) {
                    result.append(strike)
                } else if let emphasis = parseDelimited(marker: "*", transform: MarkdownInline.emphasis) {
                    result.append(emphasis)
                } else if let emphasis = parseDelimited(marker: "_", transform: MarkdownInline.emphasis) {
                    result.append(emphasis)
                } else if let autolink = parseAutolink() {
                    result.append(autolink)
                } else {
                    result.append(.text(consumeText()))
                }
            }

            return mergeAdjacentText(result)
        }

        private mutating func parseDelimited(
            marker: String,
            transform: ([MarkdownInline]) -> MarkdownInline,
        ) -> MarkdownInline? {
            guard source[index...].hasPrefix(marker) else {
                return nil
            }

            let contentStart = source.index(index, offsetBy: marker.count)
            guard let close = source.range(of: marker, range: contentStart ..< source.endIndex)?.lowerBound else {
                return nil
            }

            let raw = String(source[contentStart ..< close])
            index = source.index(close, offsetBy: marker.count)
            return transform(InlineParser(options: options).parse(raw))
        }

        private mutating func parseEscape() -> MarkdownInline? {
            guard source[index] == "\\" else {
                return nil
            }

            let escapedIndex = source.index(after: index)
            guard escapedIndex < source.endIndex,
                  isASCIIPunctuation(source[escapedIndex])
            else {
                return nil
            }

            index = source.index(after: escapedIndex)
            return .text(String(source[escapedIndex]))
        }

        private mutating func parseCodeSpan() -> MarkdownInline? {
            guard source[index] == "`" else {
                return nil
            }

            let contentStart = source.index(after: index)
            guard let close = nextClose("`", from: contentStart, unescaped: false) else {
                return nil
            }

            let raw = String(source[contentStart ..< close])
            index = source.index(after: close)
            return .code(raw.replacingOccurrences(of: "\n", with: " "))
        }

        private mutating func parseInlineMath() -> MarkdownInline? {
            guard options.mathTypesetting,
                  source[index] == "$",
                  !source[index...].hasPrefix("$$")
            else {
                return nil
            }

            let contentStart = source.index(after: index)
            guard contentStart < source.endIndex else {
                return nil
            }

            var cursor = contentStart
            var escaped = false
            while cursor < source.endIndex {
                let character = source[cursor]
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "$" {
                    let raw = String(source[contentStart ..< cursor])
                    guard isInlineMathContent(raw) else {
                        return nil
                    }
                    index = source.index(after: cursor)
                    return .inlineMath(MarkdownMath(source: raw, mode: .inline))
                } else if character == "\n" {
                    return nil
                }

                cursor = source.index(after: cursor)
            }

            return nil
        }

        private mutating func parseImage() -> MarkdownInline? {
            guard source[index...].hasPrefix("![") else {
                return nil
            }

            let labelStart = source.index(index, offsetBy: 2)
            guard let labelEnd = nextClose("]", from: labelStart, unescaped: true) else {
                return nil
            }
            let afterLabel = source.index(after: labelEnd)
            guard afterLabel < source.endIndex, source[afterLabel] == "(" else {
                return nil
            }
            guard let destination = parseDestination(from: source.index(after: afterLabel)) else {
                return nil
            }

            index = destination.end
            return .image(
                alt: String(source[labelStart ..< labelEnd]),
                source: destination.url,
                title: destination.title,
            )
        }

        private mutating func parseLink() -> MarkdownInline? {
            guard source[index] == "[" else {
                return nil
            }

            let labelStart = source.index(after: index)
            guard let labelEnd = nextClose("]", from: labelStart, unescaped: true) else {
                return nil
            }
            let afterLabel = source.index(after: labelEnd)
            guard afterLabel < source.endIndex, source[afterLabel] == "(" else {
                return nil
            }
            guard let destination = parseDestination(from: source.index(after: afterLabel)) else {
                return nil
            }

            index = destination.end
            let label = String(source[labelStart ..< labelEnd])
            return .link(
                children: InlineParser(options: options).parse(label),
                destination: destination.url,
                title: destination.title,
            )
        }

        private mutating func parseFootnoteReference() -> MarkdownInline? {
            guard source[index...].hasPrefix("[^") else {
                return nil
            }

            let labelStart = source.index(index, offsetBy: 2)
            guard let labelEnd = nextClose("]", from: labelStart, unescaped: true) else {
                return nil
            }

            let label = String(source[labelStart ..< labelEnd])
            guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !label.contains("\n")
            else {
                return nil
            }

            index = source.index(after: labelEnd)
            return .footnoteReference(label: label)
        }

        private mutating func parseAutolink() -> MarkdownInline? {
            guard source[index] == "<" else {
                return nil
            }

            let contentStart = source.index(after: index)
            guard let close = nextClose(">", from: contentStart, unescaped: false) else {
                return nil
            }

            let candidate = String(source[contentStart ..< close])
            guard candidate.hasPrefix("http://") || candidate.hasPrefix("https://") || candidate.contains("@") else {
                return nil
            }

            index = source.index(after: close)
            return .link(
                children: [.text(candidate)],
                destination: candidate,
                title: nil,
            )
        }

        private mutating func parseDestination(from start: String.Index) -> (url: String, title: String?, end: String.Index)? {
            guard let close = nextClose(")", from: start, unescaped: false) else {
                return nil
            }

            let raw = String(source[start ..< close]).trimmingCharacters(in: .whitespacesAndNewlines)
            let end = source.index(after: close)
            guard !raw.isEmpty else {
                return nil
            }

            // A title needs an opening quote strictly before the closing quote at
            // the end. When the only `"` is the last character (`[a](")`,
            // `[a](url")`), it is not a title opener; treating it as one built an
            // inverted `titleStart ..< titleEnd` range and crashed the renderer. In
            // that case the quote belongs to the destination.
            let lastIndex = raw.index(before: raw.endIndex)
            if let quote = raw.firstIndex(of: "\""), raw.last == "\"", quote < lastIndex {
                let url = String(raw[..<quote]).trimmingCharacters(in: .whitespacesAndNewlines)
                let title = String(raw[raw.index(after: quote) ..< lastIndex])
                return (url, title, end)
            }

            return (raw, nil, end)
        }

        private mutating func consumeText() -> String {
            let start = index

            while index < source.endIndex {
                if source[index...].hasPrefix("![") ||
                    source[index...].hasPrefix("[") ||
                    source[index...].hasPrefix("**") ||
                    source[index...].hasPrefix("__") ||
                    source[index...].hasPrefix("~~") ||
                    source[index...].hasPrefix("*") ||
                    source[index...].hasPrefix("_") ||
                    source[index...].hasPrefix("`") ||
                    (options.mathTypesetting && source[index...].hasPrefix("$")) ||
                    source[index...].hasPrefix("<") ||
                    source[index...].hasPrefix("\\") ||
                    source[index...].hasPrefix("\n")
                {
                    break
                }
                index = source.index(after: index)
            }

            if start == index {
                let next = source.index(after: index)
                defer { index = next }
                return String(source[start ..< next])
            }

            return String(source[start ..< index])
        }

        private func firstUnescaped(
            _ character: Character,
            from start: String.Index,
        ) -> String.Index? {
            var cursor = start
            var escaped = false
            while cursor < source.endIndex {
                if escaped {
                    escaped = false
                } else if source[cursor] == "\\" {
                    escaped = true
                } else if source[cursor] == character {
                    return cursor
                }
                cursor = source.index(after: cursor)
            }

            return nil
        }

        private func isASCIIPunctuation(_ character: Character) -> Bool {
            guard let scalar = character.unicodeScalars.first,
                  character.unicodeScalars.count == 1
            else {
                return false
            }

            return (0x21 ... 0x2F).contains(scalar.value)
                || (0x3A ... 0x40).contains(scalar.value)
                || (0x5B ... 0x60).contains(scalar.value)
                || (0x7B ... 0x7E).contains(scalar.value)
        }

        private func isInlineMathContent(_ raw: String) -> Bool {
            guard !raw.isEmpty,
                  raw.first?.isWhitespace == false,
                  raw.last?.isWhitespace == false
            else {
                return false
            }

            return !raw.contains("\n")
        }

        private mutating func consume(_ prefix: String) -> Bool {
            guard source[index...].hasPrefix(prefix) else {
                return false
            }

            index = source.index(index, offsetBy: prefix.count)
            return true
        }

        private func mergeAdjacentText(_ inlines: [MarkdownInline]) -> [MarkdownInline] {
            var merged: [MarkdownInline] = []

            for item in inlines {
                if case let .text(next) = item,
                   case let .text(existing) = merged.last
                {
                    merged.removeLast()
                    merged.append(.text(existing + next))
                } else {
                    merged.append(item)
                }
            }

            return merged
        }
    }
}
