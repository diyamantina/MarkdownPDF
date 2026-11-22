/// A board tile of a TileDown page drawn in the PDF: a status pill, a progress bar or a row of figure cards.
///
/// It is written as a fenced block, ```` ```tile TYPE ````, and the lines of its body are the lines of the tile on the page (`status: running`, `value: 37`,
/// `kpi: Open issues`), so a page and its print say the same thing in the same syntax. A block is either a tile or a refusal that names what is wrong:
/// nothing is guessed, and a refusal is printed as a code block with the reason, as a chart or a diagram the engine cannot draw is.
///
/// The numbers are integer arithmetic: the width of a bar is whole hundredths of a percent, rounded down, so a bar is never fuller than its count.
enum TileBlock: Equatable {
    case pill(Pill)
    case progress(Progress)
    case kpi([KPICard])
    case timeline(Timeline)
    case flow(Flow)

    /// What a parse gives: the tile, or the reason the block cannot be drawn.
    enum ParseResult: Equatable {
        case tile(TileBlock)
        case unsupported(String)
    }

    /// The five states of a piece of work, in the words of the page.
    enum Status: String, Equatable {
        case running
        case waiting
        case blocked
        case done
        case failed

        static let words = "running, waiting, blocked, done or failed"
    }

    struct Pill: Equatable {
        var status: Status
        var label: String?
    }

    struct Progress: Equatable {
        var value: Int
        var max: Int
        var label: String?
        var status: Status

        /// The largest total, so that `value * 10000` cannot overflow.
        static let largestMax = 1_000_000_000_000

        /// The width of the bar in whole hundredths of a percent, rounded down.
        var hundredths: Int {
            value * 10000 / max
        }

        /// The percent, rounded down.
        var percent: Int {
            value * 100 / max
        }

        /// The count as the page writes it.
        var numbers: String {
            "\(value) of \(max) (\(percent)%)"
        }
    }

    struct KPICard: Equatable {
        var label: String
        var value: String
        var change: Change?
        var note: String?

        /// The direction, the color class and the text of a change, drawn as an arrow and a word, never by color alone.
        struct Change: Equatable {
            var trend: Trend
            var tone: Tone
            var delta: String
        }
    }

    enum Trend: String, Equatable {
        case up
        case down
        case flat

        /// The direction a delta's sign gives: `+` up, `-` and the minus sign down, anything else flat.
        init(sign delta: String) {
            switch delta.first {
            case "+": self = .up
            case "-", "\u{2212}": self = .down
            default: self = .flat
            }
        }

        /// Up is good, down is bad, flat is neutral, unless the card says otherwise.
        var defaultTone: Tone {
            switch self {
            case .up: .good
            case .down: .bad
            case .flat: .neutral
            }
        }
    }

    enum Tone: String, Equatable {
        case good
        case bad
        case neutral
    }

    /// Dated events down a rail, already sorted by date and time (the written order holds for one moment), in the
    /// direction asked for.
    struct Timeline: Equatable {
        var descending: Bool
        var events: [Event]

        struct Event: Equatable {
            var title: String
            var date: String
            var time: String?
            var body: String?
        }

        /// The most events in a timeline.
        static let mostEvents = 200

        /// A real calendar date written `YYYY-MM-DD`.
        static func isDate(_ text: String) -> Bool {
            let parts = text.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
                  text.utf8.allSatisfy({ $0 == 0x2D || (0x30 ... 0x39).contains($0) }),
                  let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
                  year >= 1, (1 ... 12).contains(month)
            else {
                return false
            }
            return (1 ... daysIn(month: month, year: year)).contains(day)
        }

        /// A time written `HH:MM`, from 00:00 to 23:59.
        static func isTime(_ text: String) -> Bool {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
                  text.utf8.allSatisfy({ $0 == 0x3A || (0x30 ... 0x39).contains($0) }),
                  let hour = Int(parts[0]), let minute = Int(parts[1])
            else {
                return false
            }
            return (0 ... 23).contains(hour) && (0 ... 59).contains(minute)
        }

        private static func daysIn(month: Int, year: Int) -> Int {
            switch month {
            case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
            case 4, 6, 9, 11: 30
            default: 31
            }
        }
    }

    /// The most cards in a KPI row.
    static let mostCards = 12

    /// The tile a fence body describes, or the reason it cannot be drawn.
    static func parse(type: String, body: String) -> ParseResult {
        TileBlockParser.parse(type: type, body: body)
    }
}
