import Foundation

extension CanonicalCombiningClass {
    /// Reorders combining marks into Unicode canonical order (UAX #15): within each run
    /// of consecutive non-starter marks, sort by canonical combining class, stably (a
    /// tie keeps input order). Starters (class 0) are fixed points a mark never moves
    /// past, so letters keep their positions. No decomposition is performed, so the
    /// scalar set is unchanged, only reordered; the result is canonically equivalent to
    /// the input. This runs before shaping so a mark sequence typed out of order (e.g.
    /// shadda before a vowel) matches the reference shaper's mark stacking.
    static func canonicallyOrdered(_ scalars: [UnicodeScalar]) -> [UnicodeScalar] {
        guard scalars.contains(where: { of($0) != 0 }) else {
            return scalars
        }
        var result = scalars
        var index = 0
        while index < result.count {
            guard of(result[index]) != 0 else {
                index += 1
                continue
            }
            var end = index
            while end < result.count, of(result[end]) != 0 {
                end += 1
            }
            let ordered = result[index ..< end]
                .enumerated()
                .sorted { first, second in
                    let firstClass = of(first.element)
                    let secondClass = of(second.element)
                    return firstClass != secondClass ? firstClass < secondClass : first.offset < second.offset
                }
                .map(\.element)
            result.replaceSubrange(index ..< end, with: ordered)
            index = end
        }
        return result
    }
}
