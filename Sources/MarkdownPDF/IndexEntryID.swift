import Foundation

/// The identity of an index entry: the folded keys of its main term and optional
/// sub-term, so differently cased or accented spellings are one entry.
struct IndexEntryID: Hashable {
    var main: String
    var sub: String?
}
