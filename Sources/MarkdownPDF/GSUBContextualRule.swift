import Foundation

/// A normalized chained-context substitution rule, coverage-based (format 3). A plain
/// contextual rule (GSUB lookup type 5) is the special case with empty `backtrack` and
/// `lookahead`; a chained contextual rule (type 6) uses all three.
///
/// Each position is the set of glyph ids that may sit there. `backtrack` is stored in
/// text order (the glyph immediately before the input is `backtrack.last`), matching
/// how the applier walks the buffer, even though the font stores it reversed. On a
/// full match the `lookupRecords` fire, each running its named lookup at its input
/// position.
struct GSUBContextualRule: Equatable {
    var backtrack: [Set<UInt16>]
    var input: [Set<UInt16>]
    var lookahead: [Set<UInt16>]
    var lookupRecords: [SequenceLookupRecord]
}
