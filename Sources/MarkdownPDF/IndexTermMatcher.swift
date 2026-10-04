import Foundation

/// Finds whole-word, case and diacritic-insensitive occurrences of index terms in
/// laid-out text.
///
/// Text and terms use the same fold as ``IndexCollation``. A match must start and
/// end on word boundaries: the scalar before it and the scalar after it may not be
/// a letter or digit (the check applies only where the term itself begins or ends
/// with a word scalar, so `C++` still matches before a space). Terms of several
/// words match across any whitespace, including a line break.
struct IndexTermMatcher {
    private struct Term {
        var entry: IndexEntryID
        var scalars: [Unicode.Scalar]
        var needsLeadingBoundary: Bool
        var needsTrailingBoundary: Bool
    }

    private var termsByFirstScalar: [Unicode.Scalar: [Term]] = [:]

    var isEmpty: Bool {
        termsByFirstScalar.isEmpty
    }

    /// `terms` pairs each entry with the text to search for.
    init(terms: [(entry: IndexEntryID, text: String)]) {
        for term in terms {
            let scalars = IndexCollation.fold(term.text)
            guard let first = scalars.first, let last = scalars.last else {
                continue
            }
            termsByFirstScalar[first, default: []].append(Term(
                entry: term.entry,
                scalars: scalars,
                needsLeadingBoundary: IndexCollation.isWordScalar(first),
                needsTrailingBoundary: IndexCollation.isWordScalar(last),
            ))
        }
    }

    /// Every match as `(line, entry)`, where `line` is the index of the line the
    /// match starts on. A match is reported once per occurrence.
    func matches(inLines lines: [String]) -> [(line: Int, entry: IndexEntryID)] {
        guard !isEmpty else {
            return []
        }

        var scalars: [Unicode.Scalar] = []
        var lineOfScalar: [Int] = []
        var pendingSpace = false
        for (lineIndex, line) in lines.enumerated() {
            // A line break is whitespace: arm the collapsed space between lines.
            pendingSpace = !scalars.isEmpty
            for character in line {
                let before = scalars.count
                IndexCollation.append(folded: character, to: &scalars, pendingSpace: &pendingSpace)
                lineOfScalar.append(contentsOf: repeatElement(lineIndex, count: scalars.count - before))
            }
        }

        var found: [(line: Int, entry: IndexEntryID)] = []
        for position in scalars.indices {
            guard let candidates = termsByFirstScalar[scalars[position]] else {
                continue
            }
            for term in candidates where position + term.scalars.count <= scalars.count {
                guard scalars[position ..< position + term.scalars.count].elementsEqual(term.scalars) else {
                    continue
                }
                if term.needsLeadingBoundary, position > 0, IndexCollation.isWordScalar(scalars[position - 1]) {
                    continue
                }
                let end = position + term.scalars.count
                if term.needsTrailingBoundary, end < scalars.count, IndexCollation.isWordScalar(scalars[end]) {
                    continue
                }
                found.append((lineOfScalar[position], term.entry))
            }
        }
        return found
    }
}
