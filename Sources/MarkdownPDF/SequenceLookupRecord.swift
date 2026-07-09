import Foundation

/// A "apply lookup N at input position i" instruction carried by a GSUB contextual
/// subtable (spec: OpenType `gsub`, SequenceLookupRecord). `sequenceIndex` is an index
/// into the matched input sequence (0 = the first input glyph); `lookupListIndex`
/// names another lookup in the LookupList to run there.
struct SequenceLookupRecord: Equatable {
    var sequenceIndex: UInt16
    var lookupListIndex: UInt16
}
