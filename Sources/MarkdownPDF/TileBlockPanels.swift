/// The tiles that are text in a box: a callout, a call to action, a hero and a grid of cards. The text of each is inline Markdown (emphasis, code, links), and
/// a button is a link written `[Label](url)`.
extension TileBlock {
    struct Callout: Equatable {
        var title: String
        var body: String?
    }

    /// A button of a call to action or a hero: a label that is a link.
    struct Button: Equatable {
        var label: String
        var destination: String
    }

    struct CTA: Equatable {
        var title: String
        var body: String?
        var buttons: [Button]
    }

    struct Hero: Equatable {
        var eyebrow: String?
        var title: String?
        var body: String?
        var buttons: [Button]
    }

    struct Card: Equatable {
        var title: String
        var badge: String?
        var body: String?
        var link: String?
    }

    struct Cards: Equatable {
        var columns: Int
        var cards: [Card]
    }
}
