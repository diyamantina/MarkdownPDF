import Foundation

/// Splits text into plain text and colour emoji. A colour emoji here is one grapheme cluster that is an emoji by default presentation (a
/// single scalar such as U+1F4A1) or an emoji-capable scalar followed by the emoji variation selector U+FE0F (U+2699 U+FE0F). A text-default
/// scalar with no selector (U+2194) stays text, and U+FE0E asks for text. Sequences (flags, keycaps, skin tones, joined sequences) are left as
/// text for now: they need the font's ligatures and are a later phase.
enum EmojiSegmenter {
    struct Cluster: Equatable {
        /// The scalars of the cluster as written, the variation selector included.
        var scalars: [Unicode.Scalar]
        /// The scalar the font's cmap is asked for.
        var base: Unicode.Scalar

        var text: String {
            String(String.UnicodeScalarView(scalars))
        }
    }

    enum Segment: Equatable {
        case text(String)
        case emoji(Cluster)
    }

    /// The colour emoji a grapheme cluster is, nil when it is text.
    static func cluster(of character: Character) -> Cluster? {
        let scalars = Array(character.unicodeScalars)
        if scalars.count == 1, scalars[0].value > 0x7F, scalars[0].properties.isEmojiPresentation {
            return Cluster(scalars: scalars, base: scalars[0])
        }
        if scalars.count == 2, scalars[1].value == 0xFE0F, scalars[0].value > 0x7F, scalars[0].properties.isEmoji {
            return Cluster(scalars: scalars, base: scalars[0])
        }
        return nil
    }

    /// Whether the text holds any colour emoji (a quick test before the full split).
    static func containsColorEmoji(_ text: String) -> Bool {
        guard text.unicodeScalars.contains(where: { $0.value > 0x7F }) else { return false }
        return text.contains { cluster(of: $0) != nil }
    }

    /// The text in order as runs of plain text and emoji clusters; adjacent plain characters stay one segment.
    static func segments(of text: String) -> [Segment] {
        var segments: [Segment] = []
        var plain = ""
        for character in text {
            if let cluster = cluster(of: character) {
                if !plain.isEmpty {
                    segments.append(.text(plain))
                    plain = ""
                }
                segments.append(.emoji(cluster))
            } else {
                plain.append(character)
            }
        }
        if !plain.isEmpty {
            segments.append(.text(plain))
        }
        return segments
    }
}
