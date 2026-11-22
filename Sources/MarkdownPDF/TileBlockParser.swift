/// Reads the body of a ```` ```tile TYPE ```` fence into a ``TileBlock``, or says why it cannot.
enum TileBlockParser {
    /// One `key: value` line of a body, with the spaces around both taken off.
    private struct Line {
        var key: String
        var value: String
    }

    static func parse(type: String, body: String) -> TileBlock.ParseResult {
        do {
            let lines = try lines(of: body)
            switch type {
            case "pill": return try .tile(.pill(pill(lines)))
            case "progress": return try .tile(.progress(progress(lines)))
            case "kpi": return try .tile(.kpi(kpi(lines)))
            case "timeline": return try .tile(.timeline(timeline(lines)))
            default: throw Refusal("the tile type \(type) is not drawn in the PDF")
            }
        } catch let refusal as Refusal {
            return .unsupported(refusal.reason)
        } catch {
            return .unsupported("\(error)")
        }
    }

    private struct Refusal: Error {
        var reason: String

        init(_ reason: String) {
            self.reason = reason
        }
    }

    private static func lines(of body: String) throws -> [Line] {
        try body.components(separatedBy: "\n").compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                return nil
            }
            guard let colon = trimmed.firstIndex(of: ":") else {
                throw Refusal("the line '\(trimmed)' has no colon: write key: value")
            }
            return Line(
                key: String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces),
                value: String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces),
            )
        }
    }

    /// The value of each allowed key, once; an unknown key and a repeated key are refusals.
    private static func values(_ lines: [Line], allowed: [String], tile: String) throws -> [String: String] {
        var values: [String: String] = [:]
        for line in lines {
            guard allowed.contains(line.key) else {
                throw Refusal("the \(tile) tile has no line \(line.key): use \(allowed.joined(separator: ", "))")
            }
            guard values[line.key] == nil else {
                throw Refusal("the \(tile) tile has the line \(line.key) twice")
            }
            values[line.key] = line.value
        }
        return values
    }

    private static func status(_ word: String?, tile: String) throws -> TileBlock.Status? {
        guard let word else {
            return nil
        }
        guard let status = TileBlock.Status(rawValue: word) else {
            throw Refusal("the \(tile)'s status is \(TileBlock.Status.words), not \(word)")
        }
        return status
    }

    private static func nonEmpty(_ text: String?) -> String? {
        text?.isEmpty == false ? text : nil
    }

    private static func pill(_ lines: [Line]) throws -> TileBlock.Pill {
        let values = try values(lines, allowed: ["status", "label"], tile: "pill")
        guard let status = try status(values["status"], tile: "pill") else {
            throw Refusal("the pill tile needs a status line: \(TileBlock.Status.words)")
        }
        return .init(status: status, label: nonEmpty(values["label"]))
    }

    private static func progress(_ lines: [Line]) throws -> TileBlock.Progress {
        let values = try values(lines, allowed: ["value", "max", "label", "status"], tile: "progress")
        guard let rawValue = values["value"] else {
            throw Refusal("the progress tile needs a value line: a whole number, 0 or more")
        }
        guard let value = Int(rawValue), value >= 0 else {
            throw Refusal("the progress tile's value is a whole number, 0 or more, not \(rawValue)")
        }
        var max = 100
        if let rawMax = values["max"] {
            guard let parsed = Int(rawMax), (1 ... TileBlock.Progress.largestMax).contains(parsed) else {
                throw Refusal("the progress tile's max is a whole number from 1 to \(TileBlock.Progress.largestMax), not \(rawMax)")
            }
            max = parsed
        }
        guard value <= max else {
            throw Refusal("the progress tile's value \(value) is above its max \(max)")
        }
        return try .init(
            value: value,
            max: max,
            label: nonEmpty(values["label"]),
            status: status(values["status"], tile: "progress") ?? .running,
        )
    }

    private static let eventLines = ["date", "time", "body"]

    private static func timeline(_ lines: [Line]) throws -> TileBlock.Timeline {
        var descending = false
        var events: [(event: TileBlock.Timeline.Event, lines: [String: String])] = []
        for line in lines {
            switch line.key {
            case "order":
                guard events.isEmpty else {
                    throw Refusal("the order line comes after an event: write it before the first event")
                }
                switch line.value {
                case "ascending": descending = false
                case "descending": descending = true
                default: throw Refusal("the timeline's order is ascending or descending, not \(line.value)")
                }
            case "event":
                guard !line.value.isEmpty else {
                    throw Refusal("an event line has an empty title: write the name of the event")
                }
                events.append((.init(title: line.value, date: "", time: nil, body: nil), [:]))
            case _ where eventLines.contains(line.key):
                guard !events.isEmpty else {
                    throw Refusal("the line \(line.key) comes before any event line")
                }
                guard events[events.count - 1].lines[line.key] == nil else {
                    throw Refusal("the event \(events[events.count - 1].event.title) has the line \(line.key) twice")
                }
                events[events.count - 1].lines[line.key] = line.value
            default:
                throw Refusal("the timeline tile has no line \(line.key): use order, event, \(eventLines.joined(separator: ", "))")
            }
        }
        guard !events.isEmpty else {
            throw Refusal("the timeline has no event: start each with an event line")
        }
        guard events.count <= TileBlock.Timeline.mostEvents else {
            throw Refusal("the timeline has \(events.count) events: use \(TileBlock.Timeline.mostEvents) at most")
        }
        let checked = try events.map { try checkedEvent($0.event, lines: $0.lines) }
        let ordered = checked.enumerated().sorted { left, right in
            let (l, r) = (key(left.element), key(right.element))
            if l != r {
                return descending ? l > r : l < r
            }
            return left.offset < right.offset
        }
        return .init(descending: descending, events: ordered.map(\.element))
    }

    /// The date and time as one sortable text; an event without a time is at 00:00.
    private static func key(_ event: TileBlock.Timeline.Event) -> String {
        event.date + " " + (event.time ?? "00:00")
    }

    private static func checkedEvent(
        _ event: TileBlock.Timeline.Event,
        lines: [String: String],
    ) throws -> TileBlock.Timeline.Event {
        var event = event
        guard let date = lines["date"] else {
            throw Refusal("the event \(event.title) needs a date line, written YYYY-MM-DD")
        }
        guard TileBlock.Timeline.isDate(date) else {
            throw Refusal("the date \(date) is not a real calendar date: write YYYY-MM-DD")
        }
        event.date = date
        if let time = lines["time"] {
            guard TileBlock.Timeline.isTime(time) else {
                throw Refusal("the time \(time) is not a time from 00:00 to 23:59: write HH:MM")
            }
            event.time = time
        }
        event.body = nonEmpty(lines["body"])
        return event
    }

    private static let cardLines = ["value", "delta", "trend", "tone", "note"]

    private static func kpi(_ lines: [Line]) throws -> [TileBlock.KPICard] {
        var groups: [(label: String, lines: [Line])] = []
        for line in lines {
            if line.key == "kpi" {
                guard !line.value.isEmpty else {
                    throw Refusal("a kpi line has an empty label: write the name of the figure")
                }
                groups.append((line.value, []))
            } else if !cardLines.contains(line.key) {
                throw Refusal("the kpi tile has no line \(line.key): use kpi, \(cardLines.joined(separator: ", "))")
            } else if groups.isEmpty {
                throw Refusal("the line \(line.key) comes before any kpi line")
            } else {
                groups[groups.count - 1].lines.append(line)
            }
        }
        guard !groups.isEmpty else {
            throw Refusal("the kpi row has no card: start each with a kpi line")
        }
        guard groups.count <= TileBlock.mostCards else {
            throw Refusal("the kpi row has \(groups.count) cards: use \(TileBlock.mostCards) at most")
        }
        return try groups.map(card)
    }

    private static func card(_ group: (label: String, lines: [Line])) throws -> TileBlock.KPICard {
        var values: [String: String] = [:]
        for line in group.lines {
            guard values[line.key] == nil else {
                throw Refusal("the card \(group.label) has the line \(line.key) twice")
            }
            values[line.key] = line.value
        }
        guard let value = values["value"], !value.isEmpty else {
            throw Refusal("the card \(group.label) needs a value line")
        }
        return try .init(label: group.label, value: value, change: change(values, card: group.label), note: nonEmpty(values["note"]))
    }

    private static func change(_ values: [String: String], card: String) throws -> TileBlock.KPICard.Change? {
        guard let delta = values["delta"] else {
            if values["trend"] != nil || values["tone"] != nil {
                throw Refusal("the card \(card) has a trend or a tone but no delta")
            }
            return nil
        }
        var trend = TileBlock.Trend(sign: delta)
        if let word = values["trend"] {
            guard let explicit = TileBlock.Trend(rawValue: word) else {
                throw Refusal("the card \(card)'s trend is up, down or flat, not \(word)")
            }
            trend = explicit
        }
        var tone = trend.defaultTone
        if let word = values["tone"] {
            guard let explicit = TileBlock.Tone(rawValue: word) else {
                throw Refusal("the card \(card)'s tone is good, bad or neutral, not \(word)")
            }
            tone = explicit
        }
        return .init(trend: trend, tone: tone, delta: delta)
    }
}
