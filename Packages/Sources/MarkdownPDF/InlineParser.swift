import Foundation

struct InlineParser {
    func parse(_ text: String) -> [MarkdownInline] {
        var parser = Scanner(source: text)
        return parser.parse()
    }

    private struct Scanner {
        var source: String
        var index: String.Index

        init(source: String) {
            self.source = source
            index = source.startIndex
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
            return transform(InlineParser().parse(raw))
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
            guard let close = source[contentStart...].firstIndex(of: "`") else {
                return nil
            }

            let raw = String(source[contentStart ..< close])
            index = source.index(after: close)
            return .code(raw.replacingOccurrences(of: "\n", with: " "))
        }

        private mutating func parseImage() -> MarkdownInline? {
            guard source[index...].hasPrefix("![") else {
                return nil
            }

            let labelStart = source.index(index, offsetBy: 2)
            guard let labelEnd = firstUnescaped("]", from: labelStart) else {
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
            guard let labelEnd = firstUnescaped("]", from: labelStart) else {
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
                children: InlineParser().parse(label),
                destination: destination.url,
                title: destination.title,
            )
        }

        private mutating func parseFootnoteReference() -> MarkdownInline? {
            guard source[index...].hasPrefix("[^") else {
                return nil
            }

            let labelStart = source.index(index, offsetBy: 2)
            guard let labelEnd = firstUnescaped("]", from: labelStart) else {
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
            guard let close = source[contentStart...].firstIndex(of: ">") else {
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

        private func parseDestination(from start: String.Index) -> (url: String, title: String?, end: String.Index)? {
            guard let close = source[start...].firstIndex(of: ")") else {
                return nil
            }

            let raw = String(source[start ..< close]).trimmingCharacters(in: .whitespacesAndNewlines)
            let end = source.index(after: close)
            guard !raw.isEmpty else {
                return nil
            }

            if let quote = raw.firstIndex(of: "\""), raw.last == "\"" {
                let url = String(raw[..<quote]).trimmingCharacters(in: .whitespacesAndNewlines)
                let titleStart = raw.index(after: quote)
                let titleEnd = raw.index(before: raw.endIndex)
                let title = String(raw[titleStart ..< titleEnd])
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
