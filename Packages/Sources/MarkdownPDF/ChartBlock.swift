import Foundation

struct ChartBlock: Equatable {
    var kind: Kind
    var title: String?
    var xLabel: String?
    var yLabel: String?
    var categories: [String]
    var series: [Series]

    static func parseChartFence(_ source: String) -> ParseResult {
        var parser = Parser(source: source, flavor: .chartFence)
        return parser.parseChartFence()
    }

    static func parseMermaidPie(_ source: String) -> ParseResult {
        var parser = Parser(source: source, flavor: .mermaidPie)
        return parser.parseMermaidPie()
    }

    static func isMermaidPieCandidate(_ source: String) -> Bool {
        let header = Parser(source: source, flavor: .mermaidPie)
            .firstContentLine?
            .text
            .lowercased()
        return header == "pie" || header?.hasPrefix("pie ") == true
    }

    enum Kind: Equatable {
        case pie
        case bar
        case line
        case scatter
    }

    struct Series: Equatable {
        var name: String
        var points: [Point]
    }

    struct Point: Equatable {
        var x: Double
        var y: Double
        var label: String?
    }

    enum ParseResult: Equatable {
        case chart(ChartBlock)
        case unsupported(String)
    }

    private struct SourceLine {
        var number: Int
        var text: String
    }

    private struct SeriesInput {
        var number: Int
        var name: String
        var payload: String
    }

    private struct SliceInput {
        var number: Int
        var label: String
        var value: Double
    }

    private enum ParserFlavor {
        case chartFence
        case mermaidPie
    }

    private struct Parser {
        private let flavor: ParserFlavor
        private let lines: [SourceLine]

        var firstContentLine: SourceLine? {
            lines.first
        }

        init(source: String, flavor: ParserFlavor) {
            self.flavor = flavor
            lines = source
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .compactMap { offset, line in
                    let text = String(line).trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else {
                        return nil
                    }
                    switch flavor {
                    case .chartFence:
                        guard !text.hasPrefix("#") else {
                            return nil
                        }
                    case .mermaidPie:
                        guard !text.hasPrefix("%%") else {
                            return nil
                        }
                    }
                    return SourceLine(number: offset + 1, text: text)
                }
        }

        mutating func parseMermaidPie() -> ParseResult {
            guard let header = lines.first else {
                return .unsupported("empty Mermaid pie chart")
            }

            let title: String?
            let lowercasedHeader = header.text.lowercased()
            if lowercasedHeader == "pie" {
                title = nil
            } else if lowercasedHeader.hasPrefix("pie title ") {
                title = sanitizedLabel(String(header.text.dropFirst("pie title ".count)))
            } else {
                return .unsupported("line \(header.number): expected `pie` or `pie title ...`")
            }

            var slices: [SliceInput] = []
            for line in lines.dropFirst() {
                let text = stripTrailingSemicolon(line.text)
                guard let split = splitKeyValue(text) else {
                    return .unsupported("line \(line.number): expected `label : value`")
                }
                guard let value = parseNumber(split.value), value >= 0 else {
                    return .unsupported("line \(line.number): pie slice value must be a non-negative number")
                }
                slices.append(SliceInput(number: line.number, label: sanitizedLabel(split.key), value: value))
            }

            return chartFromPie(title: title, slices: slices)
        }

        mutating func parseChartFence() -> ParseResult {
            var kind: Kind?
            var title: String?
            var xLabel: String?
            var yLabel: String?
            var categories: [String] = []
            var xValues: [Double]?
            var seriesInputs: [SeriesInput] = []
            var sliceInputs: [SliceInput] = []

            for line in lines {
                guard let split = splitKeyValue(line.text) else {
                    return .unsupported("line \(line.number): expected `key: value`")
                }

                let key = split.key.lowercased()
                switch key {
                case "type", "kind":
                    guard let parsed = parseKind(split.value) else {
                        return .unsupported("line \(line.number): unknown chart type `\(split.value)`")
                    }
                    kind = parsed
                case "title":
                    title = sanitizedLabel(split.value)
                case "x-label", "xlabel", "x label":
                    xLabel = sanitizedLabel(split.value)
                case "y-label", "ylabel", "y label":
                    yLabel = sanitizedLabel(split.value)
                case "categories", "category":
                    categories = splitList(split.value).map(sanitizedLabel)
                case "x":
                    guard let values = parseNumberList(split.value) else {
                        return .unsupported("line \(line.number): x values must be numbers")
                    }
                    xValues = values
                case "series", "points":
                    guard let input = parseSeriesInput(line: line.number, value: split.value) else {
                        return .unsupported("line \(line.number): expected `Name = values`")
                    }
                    seriesInputs.append(input)
                case "slice":
                    guard let slice = parseSliceInput(line: line.number, value: split.value) else {
                        return .unsupported("line \(line.number): expected `Label = value`")
                    }
                    sliceInputs.append(slice)
                default:
                    return .unsupported("line \(line.number): unknown chart key `\(split.key)`")
                }
            }

            guard let kind else {
                return .unsupported("chart type is required")
            }

            switch kind {
            case .pie:
                return parsePieChartFence(title: title, categories: categories, seriesInputs: seriesInputs, slices: sliceInputs)
            case .bar, .line:
                return parseValueSeriesChart(
                    kind: kind,
                    title: title,
                    xLabel: xLabel,
                    yLabel: yLabel,
                    categories: categories,
                    xValues: xValues,
                    seriesInputs: seriesInputs,
                )
            case .scatter:
                return parseScatterChart(
                    title: title,
                    xLabel: xLabel,
                    yLabel: yLabel,
                    categories: categories,
                    xValues: xValues,
                    seriesInputs: seriesInputs,
                )
            }
        }

        private func parsePieChartFence(
            title: String?,
            categories: [String],
            seriesInputs: [SeriesInput],
            slices: [SliceInput],
        ) -> ParseResult {
            if !slices.isEmpty {
                return chartFromPie(title: title, slices: slices)
            }

            guard seriesInputs.count == 1 else {
                return .unsupported("pie charts require `slice:` entries or one value series")
            }
            guard !categories.isEmpty else {
                return .unsupported("pie value series require categories")
            }
            let input = seriesInputs[0]
            guard let values = parseNumberList(input.payload), values.count == categories.count else {
                return .unsupported("line \(input.number): pie values must match category count")
            }
            let pieSlices = zip(categories, values).map {
                SliceInput(number: input.number, label: $0.0, value: $0.1)
            }
            return chartFromPie(title: title, slices: pieSlices)
        }

        private func parseValueSeriesChart(
            kind: Kind,
            title: String?,
            xLabel: String?,
            yLabel: String?,
            categories: [String],
            xValues: [Double]?,
            seriesInputs: [SeriesInput],
        ) -> ParseResult {
            guard !seriesInputs.isEmpty else {
                return .unsupported("at least one series is required")
            }
            if kind == .bar, xValues != nil {
                return .unsupported("bar charts do not support numeric x values")
            }
            if kind == .line, !categories.isEmpty, xValues != nil {
                return .unsupported("line charts cannot combine categories and numeric x values")
            }
            guard seriesInputs.count <= ChartBlock.maximumSeriesCount else {
                return .unsupported("too many series for the portable chart profile")
            }

            var series: [Series] = []
            var expectedCount: Int?
            for input in seriesInputs {
                guard let values = parseNumberList(input.payload), !values.isEmpty else {
                    return .unsupported("line \(input.number): series values must be numbers")
                }
                if let expectedCount, values.count != expectedCount {
                    return .unsupported("line \(input.number): all series must have the same value count")
                }
                expectedCount = values.count
                guard values.count <= ChartBlock.maximumPointsPerSeries else {
                    return .unsupported("line \(input.number): too many points for the portable chart profile")
                }
                if let xValues, xValues.count != values.count {
                    return .unsupported("line \(input.number): x values must match series value count")
                }
                let points = values.enumerated().map { index, value in
                    Point(
                        x: xValues?[index] ?? Double(index),
                        y: value,
                        label: categories.indices.contains(index) ? categories[index] : nil,
                    )
                }
                series.append(Series(name: input.name, points: points))
            }

            let count = expectedCount ?? 0
            let resolvedCategories: [String]
            if categories.isEmpty {
                resolvedCategories = kind == .bar ? (1 ... max(1, count)).map(String.init) : []
            } else {
                guard categories.count == count else {
                    return .unsupported("category count must match series value count")
                }
                guard categories.count <= ChartBlock.maximumCategories else {
                    return .unsupported("too many categories for the portable chart profile")
                }
                resolvedCategories = categories
            }

            return .chart(ChartBlock(
                kind: kind,
                title: title,
                xLabel: xLabel,
                yLabel: yLabel,
                categories: resolvedCategories,
                series: series,
            ))
        }

        private func parseScatterChart(
            title: String?,
            xLabel: String?,
            yLabel: String?,
            categories: [String],
            xValues: [Double]?,
            seriesInputs: [SeriesInput],
        ) -> ParseResult {
            guard !seriesInputs.isEmpty else {
                return .unsupported("at least one point series is required")
            }
            guard categories.isEmpty, xValues == nil else {
                return .unsupported("scatter charts use point pairs instead of categories or x values")
            }
            guard seriesInputs.count <= ChartBlock.maximumSeriesCount else {
                return .unsupported("too many series for the portable chart profile")
            }

            var series: [Series] = []
            for input in seriesInputs {
                guard let points = parsePointList(input.payload), !points.isEmpty else {
                    return .unsupported("line \(input.number): scatter series must use `(x, y)` points")
                }
                guard points.count <= ChartBlock.maximumPointsPerSeries else {
                    return .unsupported("line \(input.number): too many points for the portable chart profile")
                }
                series.append(Series(name: input.name, points: points))
            }

            return .chart(ChartBlock(
                kind: .scatter,
                title: title,
                xLabel: xLabel,
                yLabel: yLabel,
                categories: [],
                series: series,
            ))
        }

        private func chartFromPie(title: String?, slices: [SliceInput]) -> ParseResult {
            guard !slices.isEmpty else {
                return .unsupported("pie chart has no slices")
            }
            guard slices.count <= ChartBlock.maximumPieSlices else {
                return .unsupported("too many pie slices for the portable chart profile")
            }
            guard slices.allSatisfy({ !$0.label.isEmpty }) else {
                return .unsupported("pie slice labels must not be empty")
            }
            let total = slices.reduce(0) { $0 + $1.value }
            guard total > 0 else {
                return .unsupported("pie chart total must be greater than zero")
            }

            return .chart(ChartBlock(
                kind: .pie,
                title: title,
                xLabel: nil,
                yLabel: nil,
                categories: slices.map(\.label),
                series: [
                    Series(
                        name: "Slices",
                        points: slices.enumerated().map { index, slice in
                            Point(x: Double(index), y: slice.value, label: slice.label)
                        },
                    ),
                ],
            ))
        }

        private func parseKind(_ text: String) -> Kind? {
            switch sanitizedLabel(text).lowercased() {
            case "pie":
                .pie
            case "bar":
                .bar
            case "line":
                .line
            case "scatter", "xy":
                .scatter
            default:
                nil
            }
        }

        private func parseSeriesInput(line: Int, value: String) -> SeriesInput? {
            guard let split = splitAssignment(value) else {
                return nil
            }
            let name = sanitizedLabel(split.key)
            guard !name.isEmpty else {
                return nil
            }
            return SeriesInput(number: line, name: name, payload: split.value.trimmingCharacters(in: .whitespaces))
        }

        private func parseSliceInput(line: Int, value: String) -> SliceInput? {
            guard let split = splitAssignment(value),
                  let number = parseNumber(split.value),
                  number >= 0
            else {
                return nil
            }
            return SliceInput(number: line, label: sanitizedLabel(split.key), value: number)
        }

        private func parsePointList(_ text: String) -> [Point]? {
            var points: [Point] = []
            for item in splitList(text) {
                let trimmed = item.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("("), trimmed.hasSuffix(")") else {
                    return nil
                }
                let inner = trimmed.dropFirst().dropLast()
                let parts = splitList(String(inner))
                guard parts.count == 2,
                      let x = parseNumber(parts[0]),
                      let y = parseNumber(parts[1])
                else {
                    return nil
                }
                points.append(Point(x: x, y: y, label: nil))
            }
            return points
        }

        private func parseNumberList(_ text: String) -> [Double]? {
            let values = splitList(text)
            guard !values.isEmpty else {
                return nil
            }
            var numbers: [Double] = []
            for value in values {
                guard let number = parseNumber(value) else {
                    return nil
                }
                numbers.append(number)
            }
            return numbers
        }

        private func parseNumber(_ text: String) -> Double? {
            guard let value = Double(text.trimmingCharacters(in: .whitespaces)),
                  value.isFinite
            else {
                return nil
            }
            return value
        }

        private func splitKeyValue(_ text: String) -> (key: String, value: String)? {
            split(text, separator: ":")
        }

        private func splitAssignment(_ text: String) -> (key: String, value: String)? {
            split(text, separator: "=") ?? split(text, separator: ":")
        }

        private func split(_ text: String, separator: Character) -> (key: String, value: String)? {
            var inQuote: Character?
            var depth = 0
            for index in text.indices {
                let character = text[index]
                if let quote = inQuote {
                    if character == quote {
                        inQuote = nil
                    }
                    continue
                }
                if character == "\"" || character == "'" {
                    inQuote = character
                    continue
                }
                if character == "(" {
                    depth += 1
                    continue
                }
                if character == ")" {
                    depth = max(0, depth - 1)
                    continue
                }
                if depth == 0, character == separator {
                    let key = sanitizedLabel(String(text[..<index]))
                    let value = String(text[text.index(after: index)...]).trimmingCharacters(in: .whitespaces)
                    guard !key.isEmpty, !value.isEmpty else {
                        return nil
                    }
                    return (key, value)
                }
            }
            return nil
        }

        private func splitList(_ text: String) -> [String] {
            var values: [String] = []
            var current = ""
            var inQuote: Character?
            var depth = 0

            for character in text {
                if let quote = inQuote {
                    current.append(character)
                    if character == quote {
                        inQuote = nil
                    }
                    continue
                }

                if character == "\"" || character == "'" {
                    inQuote = character
                    current.append(character)
                } else if character == "(" {
                    depth += 1
                    current.append(character)
                } else if character == ")" {
                    depth = max(0, depth - 1)
                    current.append(character)
                } else if character == ",", depth == 0 {
                    let value = current.trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty {
                        values.append(value)
                    }
                    current = ""
                } else {
                    current.append(character)
                }
            }

            let value = current.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty {
                values.append(value)
            }
            return values
        }

        private func sanitizedLabel(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 2,
               let first = trimmed.first,
               let last = trimmed.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'")
            {
                return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return trimmed
        }

        private func stripTrailingSemicolon(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasSuffix(";") else {
                return trimmed
            }
            return String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
        }
    }

    private static let maximumCategories = 12
    private static let maximumPieSlices = 8
    private static let maximumPointsPerSeries = 12
    private static let maximumSeriesCount = 4
}
