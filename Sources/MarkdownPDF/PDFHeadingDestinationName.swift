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

        for scalar in title.lowercased().unicodeScalars {
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
