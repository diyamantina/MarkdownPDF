import Foundation
@testable import MarkdownPDF
import Testing

/// The closed form of the floors: the widest words that fit the page together keep their widths; when they do not, the floors are `min(word_i, L)`
/// and `L` is the level at which they add up to the page (less one point, so the columns can still share what is left).
@Suite("Table column floors")
struct TableColumnFloorsTests {
    private func near(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    @Test("words that fit the page together keep their widths")
    func fit() {
        #expect(TableColumnFloors.waterFilled([100, 50, 80], minimum: [36, 36, 36], total: 500) == [100, 50, 80])
    }

    @Test("a column is never below its smallest width")
    func minimum() {
        #expect(TableColumnFloors.waterFilled([10, 50], minimum: [36, 36], total: 500) == [36, 50])
    }

    @Test("when the words do not fit, the widest are cut to the common level L and the narrow ones keep their widths")
    func waterFilling() {
        // total 401, target 400: 60 and 100 fit under an equal share of what is left (60 * 3 = 180 <= 400; 100 * 2 = 200 <= 340); 400 - 160 = 240 is shared
        // by the two widest, L = 120.
        let floors = TableColumnFloors.waterFilled([60, 100, 200, 300], minimum: [36, 36, 36, 36], total: 401)
        #expect(near(floors, [60, 100, 120, 120]), Comment(rawValue: "\(floors)"))
        #expect(abs(floors.reduce(0, +) - 400) < 1e-9)
    }

    @Test("all the words wider than an equal share are cut to that share")
    func allWide() {
        let floors = TableColumnFloors.waterFilled([200, 200, 200, 200], minimum: [36, 36, 36, 36], total: 401)
        #expect(near(floors, [100, 100, 100, 100]), Comment(rawValue: "\(floors)"))
    }

    @Test("the floors never exceed the words, never fall below the smallest width, and add up to at most the page, over many cases")
    func properties() {
        var seed: UInt64 = 12345
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        for _ in 0 ..< 500 {
            let columns = 2 + Int(next() * 6)
            let words = (0 ..< columns).map { _ in 10 + next() * 300 }
            let minimum = Array(repeating: 36.0, count: columns)
            let floors = TableColumnFloors.waterFilled(words, minimum: minimum, total: 495)
            for (index, floor) in floors.enumerated() {
                #expect(floor <= max(words[index], minimum[index]) + 1e-9)
                #expect(floor >= minimum[index] - 1e-9)
            }
            if words.reduce(0, +) > 494 {
                #expect(floors.reduce(0, +) <= 494 + Double(columns) * 36, "the floors of a table that does not fit stay near the page")
            } else {
                #expect(zip(floors, zip(words, minimum)).allSatisfy { $0 == max($1.0, $1.1) }, "words that fit keep their widths")
            }
        }
    }
}
