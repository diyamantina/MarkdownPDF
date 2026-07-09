import Foundation

struct PDFHeadingDestinationName {
    private var used: Set<String> = []

    mutating func uniqueName(for title: String) -> String {
        // Disambiguate against the names actually issued, not a per-base counter. A
        // counter keyed only on the base slug can hand out a name that a later
        // heading also produces naturally: "Cafe"/"Cafe" -> "cafe"/"cafe-2", then a
        // "Cafe 2" heading whose own slug is "cafe-2" would collide, putting two
        // identical keys in the PDF `/Dests` name tree (undefined viewer lookup).
        // Bump the suffix until the candidate name is unused.
        let base = Self.slug(for: title)
        var candidate = base
        var suffix = 1
        while used.contains(candidate) {
            suffix += 1
            candidate = "\(base)-\(suffix)"
        }
        used.insert(candidate)
        return candidate
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
            // Latin letters that carry no canonical decomposition (a stroke or a
            // ligature rather than a base + mark) are not reached by the decompose
            // step, so fold them to an ASCII base explicitly. This keeps the promise
            // "an accented Latin letter folds to its base" true for Croatian đ and
            // the Nordic and ligature letters, and stays normalization-stable because
            // these scalars are identical in NFC and NFD.
            if let fold = Self.asciiFolds[scalar] {
                output += fold
                previousWasSeparator = false
                continue
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

    /// Lowercase Latin letters that have no canonical decomposition (so the
    /// decompose step leaves them intact) mapped to an ASCII base. Titles are
    /// lowercased before lookup, so only the lowercase forms are needed.
    private static let asciiFolds: [UnicodeScalar: String] = [
        "\u{00E6}": "ae", // æ
        "\u{0153}": "oe", // œ
        "\u{00DF}": "ss", // ß
        "\u{00F8}": "o", //  ø
        "\u{0142}": "l", //  ł
        "\u{0111}": "d", //  đ (Croatian)
        "\u{00F0}": "d", //  ð eth
        "\u{00FE}": "th", // þ thorn
        "\u{0127}": "h", //  ħ
        "\u{0167}": "t", //  ŧ
    ]
}
