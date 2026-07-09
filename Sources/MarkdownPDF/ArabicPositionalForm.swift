/// The positional form an Arabic (or other cursive-script) letter takes once its
/// joining context is resolved. `unshaped` covers transparent marks and
/// non-joining characters, which keep their base glyph.
enum ArabicPositionalForm: Equatable {
    case isolated, initial, medial, final, unshaped

    /// The GSUB feature tag that selects this form, or nil for `unshaped`.
    var featureTag: String? {
        switch self {
        case .isolated: "isol"
        case .initial: "init"
        case .medial: "medi"
        case .final: "fina"
        case .unshaped: nil
        }
    }
}
