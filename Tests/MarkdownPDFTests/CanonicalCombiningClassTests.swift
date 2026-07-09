import Foundation
@testable import MarkdownPDF
import Testing

/// Unit witness for the canonical combining class data and the canonical-ordering pass
/// that runs before Arabic shaping.
@Suite("Canonical combining class")
struct CanonicalCombiningClassTests {
    @Test("Reads combining classes from the Unicode data")
    func readsClasses() throws {
        // Arabic harakat: fatha 30, damma 31, kasra 32, shadda 33 (UnicodeData.txt).
        #expect(try CanonicalCombiningClass.of(#require(UnicodeScalar(0x064E))) == 30) // fatha
        #expect(try CanonicalCombiningClass.of(#require(UnicodeScalar(0x064F))) == 31) // damma
        #expect(try CanonicalCombiningClass.of(#require(UnicodeScalar(0x0650))) == 32) // kasra
        #expect(try CanonicalCombiningClass.of(#require(UnicodeScalar(0x0651))) == 33) // shadda
        // A base letter is a starter (class 0).
        #expect(try CanonicalCombiningClass.of(#require(UnicodeScalar(0x0628))) == 0) // beh
        // A Latin combining mark above is class 230.
        #expect(try CanonicalCombiningClass.of(#require(UnicodeScalar(0x0301))) == 230) // combining acute
    }

    private func scalars(_ string: String) -> [UnicodeScalar] {
        Array(string.unicodeScalars)
    }

    @Test("Orders a mark run by combining class, stably")
    func ordersMarkRun() {
        // shadda (33) then fatha (30) reorder to fatha then shadda.
        let input = scalars("\u{0628}\u{0651}\u{064E}") // beh + shadda + fatha
        let ordered = CanonicalCombiningClass.canonicallyOrdered(input)
        #expect(ordered == scalars("\u{0628}\u{064E}\u{0651}")) // beh + fatha + shadda
    }

    @Test("Leaves already-canonical order unchanged")
    func leavesCanonicalUnchanged() {
        let input = scalars("\u{0628}\u{064E}\u{0651}") // beh + fatha (30) + shadda (33)
        #expect(CanonicalCombiningClass.canonicallyOrdered(input) == input)
    }

    @Test("Never moves a mark across a starter")
    func doesNotCrossStarter() {
        // Two separate base+mark clusters: reordering must stay within each cluster.
        let input = scalars("\u{0628}\u{0651}\u{0645}\u{064E}") // beh + shadda + meem + fatha
        // shadda is alone on beh, fatha alone on meem: nothing to reorder across meem.
        #expect(CanonicalCombiningClass.canonicallyOrdered(input) == input)
    }

    @Test("Leaves runs with a non-core mark in typed order")
    func leavesNonCoreMarksInTypedOrder() {
        // Hamza above (U+0654) is a Modifier Combining Mark: HarfBuzz orders it by
        // UTR #53, not raw combining class, so a run containing it must not be reordered.
        let hamzaRun = scalars("\u{0628}\u{0654}\u{0651}") // beh + hamza above + shadda
        #expect(CanonicalCombiningClass.canonicallyOrdered(hamzaRun) == hamzaRun)
        // Subscript alef (U+0656), a Quranic annotation mark, is likewise left as typed
        // even though its combining class (220) would otherwise sort it after a kasra.
        let subscriptRun = scalars("\u{0628}\u{0656}\u{0650}") // beh + subscript alef + kasra
        #expect(CanonicalCombiningClass.canonicallyOrdered(subscriptRun) == subscriptRun)
    }

    @Test("Preserves input order for equal classes")
    func stableForEqualClasses() {
        // Two class-230 marks keep their input order (stable).
        let input = scalars("e\u{0300}\u{0301}") // e + grave (230) + acute (230)
        #expect(CanonicalCombiningClass.canonicallyOrdered(input) == input)
    }
}
