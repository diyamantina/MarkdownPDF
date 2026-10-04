import Foundation

/// The deterministic fold and ordering behind the index.
///
/// Foundation's locale collation differs between Apple platforms and Linux, so the
/// index never uses it. Instead a term is folded to a canonical scalar sequence and
/// ordered by plain scalar value:
///
/// 1. Canonical decomposition, so a precomposed letter and a base letter plus a
///    combining mark fold the same.
/// 2. Default Unicode lowercasing.
/// 3. Combining marks are dropped (`e` followed by U+0301 folds to `e`).
/// 4. Latin letters with no decomposition (`ae`, `oe`, sharp s, o with stroke, l
///    with stroke, d with stroke, eth, thorn, h with stroke, t with stroke) fold to
///    their ASCII spelling, the same table the heading anchors use.
/// 5. Every run of whitespace becomes one space and the ends are trimmed.
///
/// Folded terms compare by scalar value, so punctuation sorts before digits and
/// digits before letters, and letters of one script sort in code point order. Two
/// terms that fold equal are one entry. When two distinct strings fold equal (for
/// example two spellings of the same word), the display form compares by scalar
/// value as the final tie-break, so the result never depends on input order.
enum IndexCollation {
    static func fold(_ text: String) -> [Unicode.Scalar] {
        var scalars: [Unicode.Scalar] = []
        var pendingSpace = false
        for character in text {
            append(folded: character, to: &scalars, pendingSpace: &pendingSpace)
        }
        return scalars
    }

    /// Appends the folded scalars of one character. A whitespace character only arms
    /// `pendingSpace`; the single space is written before the next kept scalar, so
    /// runs collapse and both ends trim. Callers that need to map folded scalars
    /// back to their source (the term matcher) drive this one character at a time.
    static func append(
        folded character: Character,
        to scalars: inout [Unicode.Scalar],
        pendingSpace: inout Bool,
    ) {
        if character.isWhitespace || character.isNewline {
            pendingSpace = !scalars.isEmpty
            return
        }

        let lowered: String = if character.isASCII {
            character.lowercased()
        } else {
            String(character).decomposedStringWithCanonicalMapping.lowercased()
        }
        for scalar in lowered.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark, .spacingMark:
                continue
            default:
                break
            }
            if pendingSpace {
                scalars.append(" ")
                pendingSpace = false
            }
            if let replacement = PDFHeadingDestinationName.asciiFolds[scalar] {
                scalars.append(contentsOf: replacement.unicodeScalars)
            } else {
                scalars.append(scalar)
            }
        }
    }

    /// The folded form as a string, used as the identity of an index entry.
    static func key(_ text: String) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: fold(text))
        return String(view)
    }

    /// Whether `left` sorts before `right`: folded scalars first, then the display
    /// strings' scalars as the final tie-break.
    static func precedes(_ left: String, _ right: String) -> Bool {
        let foldedLeft = fold(left).map(\.value)
        let foldedRight = fold(right).map(\.value)
        if foldedLeft != foldedRight {
            return foldedLeft.lexicographicallyPrecedes(foldedRight)
        }
        return left.unicodeScalars.map(\.value).lexicographicallyPrecedes(right.unicodeScalars.map(\.value))
    }

    /// The letter heading an entry is grouped under: the uppercased first folded
    /// scalar when it is a letter, otherwise `#`.
    static func groupHeading(for term: String) -> String {
        guard let first = fold(term).first, first.properties.isAlphabetic else {
            return "#"
        }
        return String(first).uppercased()
    }

    /// True for a scalar that continues a word: a letter or a decimal digit.
    static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.generalCategory == .decimalNumber
    }
}
