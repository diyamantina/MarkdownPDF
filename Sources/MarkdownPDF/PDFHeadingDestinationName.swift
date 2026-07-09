import Foundation

struct PDFHeadingDestinationName {
    private var counts: [String: Int] = [:]

    mutating func uniqueName(for title: String) -> String {
        let base = Self.slug(for: title)
        let count = (counts[base] ?? 0) + 1
        counts[base] = count
        return count == 1 ? base : "\(base)-\(count)"
    }

    static func linkTargetName(for fragment: String) -> String? {
        guard !fragment.isEmpty else {
            return nil
        }

        return slug(for: fragment.removingPercentEncoding ?? fragment)
    }

    private static func slug(for title: String) -> String {
        var output = ""
        var previousWasSeparator = false

        // Decompose first, then drop the combining marks. An accented letter reaches
        // here as either a precomposed scalar (`é`) or a base letter plus a combining
        // mark (`e` + U+0301); decomposing unifies the two and keeps the ASCII base,
        // so canonically-equivalent headings produce the same slug (`café` -> "cafe"
        // in both forms) and an internal link resolves regardless of the author's
        // normalization form. Marks are skipped outright rather than treated as a
        // separator so the base letters stay contiguous (`naïve` -> "naive", not
        // "nai-ve"). See #39.
        for scalar in title.decomposedStringWithCanonicalMapping.lowercased().unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark, .spacingMark:
                continue
            default:
                break
            }
            if CharacterSet.alphanumerics.contains(scalar), scalar.value < 128 {
                output.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator, !output.isEmpty {
                output.append("-")
                previousWasSeparator = true
            }
        }

        while output.last == "-" {
            output.removeLast()
        }
        return output.isEmpty ? "heading" : output
    }
}
