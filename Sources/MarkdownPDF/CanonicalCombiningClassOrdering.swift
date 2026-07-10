import Foundation

extension CanonicalCombiningClass {
    /// Reorders combining marks into Unicode canonical order (UAX #15): within each run
    /// of consecutive non-starter marks, sort by canonical combining class, stably (a
    /// tie keeps input order). Starters (class 0) are fixed points a mark never moves
    /// past, so letters keep their positions. No decomposition is performed, so the
    /// scalar set is unchanged, only reordered; the result is canonically equivalent to
    /// the input. This runs before shaping so a mark sequence typed out of order (e.g.
    /// shadda before a vowel) matches the reference shaper's mark stacking.
    ///
    /// A run is reordered only when every mark in it is a core Arabic haraka (the short
    /// vowels, tanwin, shadda, and sukun, U+064B...U+0652), for which the reference
    /// shaper's mark ordering coincides with raw canonical combining class. HarfBuzz's
    /// Arabic shaper follows UTR #53, not raw canonical order, for other marks (hamza,
    /// the Quranic annotation marks, subscript alef, and so on): reordering a run that
    /// contains one would place the marks differently than the reference, so such a run
    /// is left in typed order. This keeps the vocalized-harakat gain while never
    /// diverging from the reference on the marks UTR #53 treats specially.
    static func canonicallyOrdered(_ scalars: [UnicodeScalar]) -> [UnicodeScalar] {
        reordered(scalars, where: isReorderableHaraka)
    }

    /// Reorders Hebrew niqqud and cantillation marks into Unicode canonical order before
    /// shaping. Unlike Arabic, every Hebrew combining mark is reorderable by raw canonical
    /// combining class: the reference shaper normalizes a Hebrew mark run by stable
    /// canonical ordering, verified as `shape(run) == shape(canonicalOrder(run))` for every
    /// permutation of the niqqud and accents (there is no UTR #53 special case for Hebrew,
    /// because the points carry distinct combining classes and same-class accents keep
    /// their input order under a stable sort). A run mixing a non-Hebrew mark is left in
    /// typed order.
    static func canonicallyOrderedHebrew(_ scalars: [UnicodeScalar]) -> [UnicodeScalar] {
        reordered(scalars, where: isReorderableHebrewMark)
    }

    /// Within each run of consecutive non-starter marks, stably sort by canonical combining
    /// class, but only when every mark in the run satisfies `isReorderable`; runs with a
    /// mark the caller does not vouch for are left in typed order. Starters (class 0) are
    /// fixed points, so letters keep their positions and no decomposition is performed.
    private static func reordered(
        _ scalars: [UnicodeScalar],
        where isReorderable: (UnicodeScalar) -> Bool,
    ) -> [UnicodeScalar] {
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
            let run = result[index ..< end]
            if run.allSatisfy(isReorderable) {
                let ordered = run
                    .enumerated()
                    .sorted { first, second in
                        let firstClass = of(first.element)
                        let secondClass = of(second.element)
                        return firstClass != secondClass ? firstClass < secondClass : first.offset < second.offset
                    }
                    .map(\.element)
                result.replaceSubrange(index ..< end, with: ordered)
            }
            index = end
        }
        return result
    }

    /// Whether `scalar` is a core Arabic haraka whose canonical combining class ordering
    /// matches the reference shaper: fathatan, dammatan, kasratan, fatha, damma, kasra,
    /// shadda, and sukun (U+064B...U+0652). Other combining marks are left in typed
    /// order because the reference orders them by UTR #53, not raw combining class.
    private static func isReorderableHaraka(_ scalar: UnicodeScalar) -> Bool {
        (0x064B ... 0x0652).contains(scalar.value)
    }

    /// Whether `scalar` is a Hebrew niqqud or cantillation mark, the marks whose reference
    /// ordering coincides with raw canonical combining class (U+0591...U+05BD points and
    /// accents, U+05BF rafe, U+05C1/U+05C2 shin/sin dots, U+05C4/U+05C5 upper/lower dots,
    /// U+05C7 qamats qatan).
    private static func isReorderableHebrewMark(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0591 ... 0x05BD, 0x05BF, 0x05C1, 0x05C2, 0x05C4, 0x05C5, 0x05C7:
            true
        default:
            false
        }
    }
}
