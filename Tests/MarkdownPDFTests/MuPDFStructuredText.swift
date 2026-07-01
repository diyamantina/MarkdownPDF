import Foundation

struct MuPDFStructuredText {
    struct Page {
        var number: Int
        var width: Double
        var height: Double
        var lines: [Line]
    }

    struct Line {
        var index: Int
        var box: Box
        var text: String
        var glyphs: [Glyph]
    }

    struct Glyph {
        var index: Int
        var text: String
        var box: Box

        var isWhitespace: Bool {
            text.unicodeScalars.allSatisfy {
                CharacterSet.whitespacesAndNewlines.contains($0)
            }
        }
    }

    struct Box: Equatable {
        var left: Double
        var top: Double
        var right: Double
        var bottom: Double

        var width: Double {
            right - left
        }

        var height: Double {
            bottom - top
        }

        static func minMax(_ values: [Double]) -> Box {
            Box(
                left: values[0],
                top: values[1],
                right: values[2],
                bottom: values[3],
            )
        }

        static func quad(_ values: [Double]) -> Box {
            let xs = stride(from: 0, to: values.count, by: 2).map { values[$0] }
            let ys = stride(from: 1, to: values.count, by: 2).map { values[$0] }
            return Box(
                left: xs.min() ?? 0,
                top: ys.min() ?? 0,
                right: xs.max() ?? 0,
                bottom: ys.max() ?? 0,
            )
        }
    }

    var pages: [Page]

    var glyphs: [Glyph] {
        pages.flatMap { page in
            page.lines.flatMap(\.glyphs)
        }
    }

    init(xml: String) throws {
        var parser = MuPDFStructuredTextParser()
        pages = try parser.parse(xml: xml)
    }

    func characterQuadIssues(
        tolerance: Double = 0.75,
        allowRightToLeftRuns: Bool = false,
    ) -> [String] {
        var issues: [String] = []

        for page in pages {
            if page.width <= 0 || page.height <= 0 {
                issues.append("page \(page.number) has non-positive size")
            }

            for line in page.lines {
                validateLine(
                    line,
                    page: page,
                    tolerance: tolerance,
                    allowRightToLeftRuns: allowRightToLeftRuns,
                    issues: &issues,
                )
            }
        }

        return issues
    }

    private func validateLine(
        _ line: Line,
        page: Page,
        tolerance: Double,
        allowRightToLeftRuns: Bool,
        issues: inout [String],
    ) {
        // A line made only of legitimately tiny sub/superscript glyphs (a deeply
        // nested script like a_{i,j}^{n+1} or 2^{2^{x}}) can have a zero-height
        // quad, just as those glyphs do individually. Tolerate a zero-height line
        // the same way the per-glyph check does; only a clearly negative (flipped)
        // height is a corrupt quad. Zero or negative width stays a real defect
        // (text would pile up). See #197.
        let hasVisibleGlyphs = line.glyphs.contains { !$0.isWhitespace }
        if hasVisibleGlyphs, line.box.height < -tolerance || (!allowRightToLeftRuns && line.box.width <= 0) {
            issues.append("page \(page.number) line \(line.index) has non-positive size")
        }

        var visibleRun: [Glyph] = []
        for (glyphIndex, glyph) in line.glyphs.enumerated() {
            if glyph.isWhitespace {
                validateVisibleRun(
                    visibleRun,
                    line: line,
                    page: page,
                    tolerance: tolerance,
                    allowRightToLeftRuns: allowRightToLeftRuns,
                    issues: &issues,
                )
                visibleRun = []
                continue
            }

            validateGlyph(
                glyph,
                previousGlyph: previousVisibleGlyph(in: line.glyphs, before: glyphIndex),
                nextGlyph: nextVisibleGlyph(in: line.glyphs, after: glyphIndex),
                line: line,
                page: page,
                tolerance: tolerance,
                issues: &issues,
            )
            visibleRun.append(glyph)
        }
        validateVisibleRun(
            visibleRun,
            line: line,
            page: page,
            tolerance: tolerance,
            allowRightToLeftRuns: allowRightToLeftRuns,
            issues: &issues,
        )
    }

    private func validateGlyph(
        _ glyph: Glyph,
        previousGlyph: Glyph?,
        nextGlyph: Glyph?,
        line: Line,
        page: Page,
        tolerance: Double,
        issues: inout [String],
    ) {
        // A glyph with zero height but positive width is a thin sliver: MuPDF
        // reports this for legitimately tiny math sub/superscripts, which still
        // paint at the correct size. Only a clearly negative (flipped) height
        // signals a corrupt quad. Zero or negative width stays a real defect
        // (text would pile up), except for ToUnicode-expansion continuations
        // that share a sibling glyph's position. See #197.
        if glyph.box.height < -tolerance
            || (glyph.box.width <= 0 && !isToUnicodeExpansionContinuation(
                glyph,
                previousGlyph: previousGlyph,
                nextGlyph: nextGlyph,
                tolerance: tolerance,
            ))
        {
            issues.append(glyphDescription(glyph, line: line, page: page) + " has non-positive size")
        }

        if glyph.box.left < -tolerance
            || glyph.box.top < -tolerance
            || glyph.box.right > page.width + tolerance
            || glyph.box.bottom > page.height + tolerance
        {
            issues.append(glyphDescription(glyph, line: line, page: page) + " is outside page bounds")
        }
    }

    private func previousVisibleGlyph(in glyphs: [Glyph], before index: Int) -> Glyph? {
        guard index > 0 else {
            return nil
        }
        return glyphs[..<index].last { !$0.isWhitespace }
    }

    private func nextVisibleGlyph(in glyphs: [Glyph], after index: Int) -> Glyph? {
        let nextIndex = index + 1
        guard nextIndex < glyphs.count else {
            return nil
        }
        return glyphs[nextIndex...].first { !$0.isWhitespace }
    }

    private func isToUnicodeExpansionContinuation(
        _ glyph: Glyph,
        previousGlyph: Glyph?,
        nextGlyph: Glyph?,
        tolerance: Double,
    ) -> Bool {
        guard !glyph.isWhitespace,
              abs(glyph.box.width) <= tolerance,
              glyph.box.height > 0
        else {
            return false
        }

        let touchesPrevious = previousGlyph.map { previous in
            abs(previous.box.right - glyph.box.left) <= tolerance
        } ?? false
        let touchesNext = nextGlyph.map { next in
            abs(next.box.left - glyph.box.left) <= tolerance
        } ?? false
        return touchesPrevious || touchesNext
    }

    private func validateVisibleRun(
        _ glyphs: [Glyph],
        line: Line,
        page: Page,
        tolerance: Double,
        allowRightToLeftRuns: Bool,
        issues: inout [String],
    ) {
        guard !glyphs.isEmpty else {
            return
        }

        if allowRightToLeftRuns {
            let spatialGlyphs = glyphs.sorted { left, right in
                if left.box.left == right.box.left {
                    return left.index < right.index
                }
                return left.box.left < right.box.left
            }
            validateSpatialGlyphs(spatialGlyphs, line: line, page: page, tolerance: tolerance, issues: &issues)
            return
        }

        for (left, right) in zip(glyphs, glyphs.dropFirst()) {
            if right.box.left < left.box.left - tolerance {
                issues.append(glyphDescription(right, line: line, page: page) + " moves left inside a text run")
            }

            if right.box.left < left.box.right - tolerance {
                issues.append(
                    glyphDescription(left, line: line, page: page)
                        + " overlaps "
                        + glyphDescription(right, line: line, page: page),
                )
            }
        }
    }

    private func validateSpatialGlyphs(
        _ glyphs: [Glyph],
        line: Line,
        page: Page,
        tolerance: Double,
        issues: inout [String],
    ) {
        for (left, right) in zip(glyphs, glyphs.dropFirst()) {
            if right.box.left < left.box.right - tolerance {
                issues.append(
                    glyphDescription(left, line: line, page: page)
                        + " overlaps "
                        + glyphDescription(right, line: line, page: page),
                )
            }
        }
    }

    private func glyphDescription(_ glyph: Glyph, line: Line, page: Page) -> String {
        "page \(page.number) line \(line.index) glyph \(glyph.index) '\(glyph.text)'"
    }
}

private struct MuPDFStructuredTextParser {
    private var pages: [MuPDFStructuredText.Page] = []
    private var currentPageIndex: Int?
    private var currentLineIndex: Int?

    mutating func parse(xml: String) throws -> [MuPDFStructuredText.Page] {
        for rawLine in xml.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("<page ") {
                try startPage(attributes: attributes(in: line))
            } else if line.hasPrefix("<line ") {
                try startLine(attributes: attributes(in: line))
            } else if line.hasPrefix("<char ") {
                try appendGlyph(attributes: attributes(in: line))
            } else if line.hasPrefix("</line") {
                currentLineIndex = nil
            } else if line.hasPrefix("</page") {
                currentLineIndex = nil
                currentPageIndex = nil
            }
        }

        return pages
    }

    private func attributes(in element: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var cursor = element.startIndex

        while let equals = element[cursor...].firstIndex(of: "=") {
            var nameStart = equals
            while nameStart > element.startIndex {
                let previous = element.index(before: nameStart)
                guard isAttributeNameCharacter(element[previous]) else {
                    break
                }
                nameStart = previous
            }

            let name = String(element[nameStart ..< equals])
            let valueStart = element.index(after: equals)
            guard valueStart < element.endIndex, element[valueStart] == "\"" else {
                cursor = valueStart
                continue
            }

            let quotedValueStart = element.index(after: valueStart)
            guard let quotedValueEnd = element[quotedValueStart...].firstIndex(of: "\"") else {
                break
            }

            attributes[name] = decodeEntities(String(element[quotedValueStart ..< quotedValueEnd]))
            cursor = element.index(after: quotedValueEnd)
        }

        return attributes
    }

    private func isAttributeNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_"
    }

    private func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private mutating func startPage(attributes: [String: String]) throws {
        let width = try doubleAttribute("width", in: attributes, element: "page")
        let height = try doubleAttribute("height", in: attributes, element: "page")
        pages.append(
            MuPDFStructuredText.Page(
                number: pages.count + 1,
                width: width,
                height: height,
                lines: [],
            ),
        )
        currentPageIndex = pages.indices.last
        currentLineIndex = nil
    }

    private mutating func startLine(attributes: [String: String]) throws {
        guard let pageIndex = currentPageIndex else {
            throw MuPDFStructuredTextError.missingParent("page")
        }

        let values = try numberListAttribute("bbox", in: attributes, element: "line", expectedCount: 4)
        let line = MuPDFStructuredText.Line(
            index: pages[pageIndex].lines.count + 1,
            box: .minMax(values),
            text: attributes["text"] ?? "",
            glyphs: [],
        )
        pages[pageIndex].lines.append(line)
        currentLineIndex = pages[pageIndex].lines.indices.last
    }

    private mutating func appendGlyph(attributes: [String: String]) throws {
        guard let pageIndex = currentPageIndex else {
            throw MuPDFStructuredTextError.missingParent("page")
        }
        guard let lineIndex = currentLineIndex else {
            throw MuPDFStructuredTextError.missingParent("line")
        }

        let values = try numberListAttribute("quad", in: attributes, element: "char", expectedCount: 8)
        let glyph = MuPDFStructuredText.Glyph(
            index: pages[pageIndex].lines[lineIndex].glyphs.count + 1,
            text: attributes["c"] ?? "",
            box: .quad(values),
        )
        pages[pageIndex].lines[lineIndex].glyphs.append(glyph)
    }

    private func doubleAttribute(
        _ name: String,
        in attributes: [String: String],
        element: String,
    ) throws -> Double {
        guard let value = attributes[name],
              let double = Double(value)
        else {
            throw MuPDFStructuredTextError.invalidAttribute(element: element, name: name)
        }
        return double
    }

    private func numberListAttribute(
        _ name: String,
        in attributes: [String: String],
        element: String,
        expectedCount: Int,
    ) throws -> [Double] {
        guard let value = attributes[name] else {
            throw MuPDFStructuredTextError.invalidAttribute(element: element, name: name)
        }

        let values = value
            .split(separator: " ", omittingEmptySubsequences: true)
            .compactMap { Double($0) }

        guard values.count == expectedCount else {
            throw MuPDFStructuredTextError.invalidNumberList(element: element, name: name, value: value)
        }

        return values
    }
}

private enum MuPDFStructuredTextError: Error {
    case invalidAttribute(element: String, name: String)
    case invalidNumberList(element: String, name: String, value: String)
    case missingParent(String)
}
