import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The roadmap diagram gate (git-discipline Rule 1.8) for the Mermaid diagrams of
/// the README.
///
/// 1. Structural: every mermaid block is vertical (`flowchart TD`), every node an
///    edge refers to is defined, every node is assigned exactly one class, every
///    assigned class is declared in that block's `classDef`, and every `classDef`
///    is within the shared legend palette.
/// 2. Legend: the first mermaid block is the shared legend (it declares the
///    palette) and therefore precedes every status diagram.
/// 3. Coverage: every open epic appears in at least one README mermaid diagram.
///    A closed epic is removed from the roadmap once its issue closes; the work it
///    delivered is recorded in the CHANGELOG, so the diagrams stay focused on
///    remaining work.
///
/// The structural and legend checks need no network. The coverage check asks the
/// forge's issue API without a token (the repository is public); when the forge
/// cannot be reached the check is skipped with a notice, so the gate stays usable
/// offline.
enum RoadmapDiagram {
    /// The class names a diagram may declare.
    static let legend: Set<String> = ["done", "active", "review", "next", "todo"]

    /// The open epics, or why they could not be asked for.
    enum EpicQuery: Sendable, Equatable {
        case numbers([String])
        case skipped(String)
    }

    // MARK: Patterns

    /// Every match of `pattern` in `text`, as its capture groups. A group that did
    /// not take part in a match is an empty string.
    static func captures(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) throws -> [[String]] {
        let expression = try NSRegularExpression(pattern: pattern, options: options)
        let whole = NSRange(text.startIndex ..< text.endIndex, in: text)
        return expression.matches(in: text, range: whole).map { match in
            (1 ..< match.numberOfRanges).map { group in
                Range(match.range(at: group), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    /// `text` cut at every match of `pattern`, the pieces between the matches.
    static func split(_ text: String, at pattern: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        let whole = NSRange(text.startIndex ..< text.endIndex, in: text)
        var pieces: [String] = []
        var start = text.startIndex
        for match in expression.matches(in: text, range: whole) {
            guard let range = Range(match.range, in: text) else {
                continue
            }
            pieces.append(String(text[start ..< range.lowerBound]))
            start = range.upperBound
        }
        pieces.append(String(text[start...]))
        return pieces
    }

    // MARK: Structure

    /// The bodies of the mermaid blocks of `text`, in order.
    static func blocks(in text: String) throws -> [String] {
        try captures("```mermaid\\n(.*?)```", in: text, options: [.dotMatchesLineSeparators]).compactMap(\.first)
    }

    /// What is wrong with one mermaid block, or nothing.
    static func issues(inBlock block: String) throws -> [String] {
        var issues: [String] = []
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let direction = lines.first { $0.hasPrefix("flowchart") } ?? ""
        if direction != "flowchart TD" {
            issues.append("not vertical (got '\(direction.isEmpty ? "no flowchart line" : direction)')")
        }

        // A node is defined where a line starts with its name and a bracket.
        let defined = try Set(captures("^\\s*([A-Za-z0-9_]+)\\s*[\\[\\({]", in: block, options: [.anchorsMatchLines]).compactMap(\.first))

        // A node is used where it starts one side of an edge.
        var used = Set<String>()
        for line in lines where line.contains("-->") || line.contains("-.->") {
            for piece in try split(line, at: "-\\.?->") {
                if let name = try captures("\\A\\s*([A-Za-z0-9_]+)", in: piece).first?.first {
                    used.insert(name)
                }
            }
        }

        let declared = try Set(captures("classDef\\s+(\\w+)", in: block).compactMap(\.first))

        // A class is assigned by a `class A,B name;` line or by `A:::name`.
        var assigned: [String: String] = [:]
        for match in try captures("^\\s*class\\s+([A-Za-z0-9_,]+)\\s+(\\w+)\\s*;", in: block, options: [.anchorsMatchLines]) {
            for node in match[0].components(separatedBy: ",") {
                assigned[node] = match[1]
            }
        }
        for match in try captures("([A-Za-z0-9_]+)[^\\n]*?:::(\\w+)", in: block) {
            assigned[match[0]] = match[1]
        }

        let orphans = used.subtracting(defined).sorted()
        let unclassed = defined.subtracting(assigned.keys).sorted()
        let undeclared = assigned.filter { !declared.contains($0.value) }.map { "\($0.key): \($0.value)" }.sorted()
        let outsideLegend = declared.subtracting(legend).sorted()
        if !orphans.isEmpty {
            issues.append("edge nodes not defined: \(orphans)")
        }
        if !unclassed.isEmpty {
            issues.append("nodes with no class: \(unclassed)")
        }
        if !undeclared.isEmpty {
            issues.append("class not in classDef: \(undeclared)")
        }
        if !outsideLegend.isEmpty {
            issues.append("classDef outside legend palette: \(outsideLegend)")
        }
        return issues
    }

    /// Whether `block` declares the palette, as the shared legend does.
    static func declaresPalette(_ block: String) throws -> Bool {
        try !captures("(classDef\\s+done)", in: block).isEmpty
    }

    // MARK: Coverage

    /// The second level sections of `text` that hold a mermaid diagram, each from
    /// its `## ` heading to the next.
    static func mermaidSections(in text: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: "^(##\\s.*)$", options: [.anchorsMatchLines])
        let whole = NSRange(text.startIndex ..< text.endIndex, in: text)
        let headings = expression.matches(in: text, range: whole).compactMap { Range($0.range, in: text) }
        var sections: [String] = []
        for (index, heading) in headings.enumerated() {
            let end = index + 1 < headings.count ? headings[index + 1].lowerBound : text.endIndex
            sections.append(String(text[heading]) + "\n" + String(text[heading.upperBound ..< end]))
        }
        return sections.filter { $0.contains("```mermaid") }
    }

    /// Whether a section refers to the epic, as `#12` or `issues/12`, and not to a
    /// longer number that starts with the same digits.
    static func epic(_ number: String, appearsIn sections: [String]) throws -> Bool {
        let pattern = "((?:#|issues/)\(NSRegularExpression.escapedPattern(for: number))(?!\\d))"
        return try sections.contains { try !captures(pattern, in: $0).isEmpty }
    }

    /// The numbers of the open issues labelled `epic`, from the forge's issue API.
    /// The repository and the server come from `GITHUB_REPOSITORY` and
    /// `GITHUB_SERVER_URL`, as the workflows set them, or default to this project.
    static func openEpics(environment: [String: String] = ProcessInfo.processInfo.environment) async -> EpicQuery {
        let repository = environment["GITHUB_REPOSITORY"] ?? "MarkdownPdfHQ/MarkdownPDF"
        let server = environment["GITHUB_SERVER_URL"] ?? "https://codeberg.org"
        guard let url = URL(string: "\(server)/api/v1/repos/\(repository)/issues?labels=epic&state=open&type=issues&limit=200") else {
            return .skipped("issue query failed: the address is not a URL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        return await withCheckedContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                continuation.resume(returning: epics(data: data, status: (response as? HTTPURLResponse)?.statusCode, error: error))
            }.resume()
        }
    }

    /// Reads the answer of the issue API. Anything but a list of issues with
    /// numbers is a reason to skip, never a reason to fail.
    static func epics(data: Data?, status: Int?, error: (any Error)?) -> EpicQuery {
        if let error {
            return .skipped("issue query failed: \(error.localizedDescription)")
        }
        guard let status, (200 ..< 300).contains(status), let data else {
            return .skipped("issue query failed: HTTP status \(status.map(String.init) ?? "missing")")
        }
        let answer: Any
        do {
            answer = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .skipped("issue query failed: the answer is not JSON: \(error.localizedDescription)")
        }
        guard let issues = answer as? [[String: Any]] else {
            return .skipped("issue query failed: the answer is not a list of issues")
        }
        var numbers: [String] = []
        for issue in issues {
            guard let number = issue["number"] as? Int else {
                return .skipped("issue query failed: an issue has no number")
            }
            numbers.append(String(number))
        }
        return .numbers(numbers)
    }
}
