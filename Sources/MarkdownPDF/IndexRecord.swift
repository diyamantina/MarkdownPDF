import Foundation

/// One finished index entry: its display text, the physical (zero-based) pages it
/// was found on in ascending order, and its sub-entries, all in final sort order.
struct IndexRecord: Equatable {
    var display: String
    var pages: [Int]
    var subentries: [IndexRecord]
}
