import Foundation

/// The least width each column of a table may be given, so that no word is broken inside itself where that can be avoided.
///
/// A column's floor is the width of its widest word (the words are cut at the places a line may break). When the widest words of all the columns fit
/// the page together, each column keeps its own. When they do not, the floors are cut down to one common level `L` (water filling): the floor of
/// column `i` is `min(word_i, L)` and `L` is the level at which the floors add up to the page. A word wider than `L`, the widest ones, is the only one
/// that is broken by character; every other word of every column stays whole. No floor is below its column's smallest width.
enum TableColumnFloors {
    /// The floors, one for each column. `words` are the widths of the widest words, `minimum` the smallest width each column may have, `total` the
    /// width of the page. The floors add up to less than `total` whenever the smallest widths do, so the columns can still share what is left.
    static func waterFilled(_ words: [Double], minimum: [Double], total: Double) -> [Double] {
        precondition(words.count == minimum.count, "one smallest width for each column")
        let target = total - 1
        guard words.reduce(0, +) > target else {
            return zip(words, minimum).map { max($0, $1) }
        }
        // Sorted ascending, each word that fits under an equal share of what is left keeps its width; the rest share what is left equally: that
        // share is the level L.
        var remaining = target
        var count = Double(words.count)
        var level = Double.infinity
        for word in words.sorted() {
            if word * count <= remaining {
                remaining -= word
                count -= 1
            } else {
                level = remaining / count
                break
            }
        }
        return zip(words, minimum).map { max(min($0, level), $1) }
    }
}
