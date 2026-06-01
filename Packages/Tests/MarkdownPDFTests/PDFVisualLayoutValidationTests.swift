import Foundation
import MarkdownPDF
import Testing

@Suite("PDF visual layout validation")
struct PDFVisualLayoutValidationTests {
    @Test("Generated PDFs do not have overlapping Poppler word boxes")
    func generatedPDFsDoNotHaveOverlappingPopplerWordBoxes() throws {
        let data = try visualValidationPDF()
        let result = try PDFValidation.pdftotextTSV(data: data, name: "visual-layout")
        try #require(result.exitCode == 0, "pdftotext -tsv failed:\n\(result.output)")

        let layout = try PopplerTextLayout(tsv: result.output)
        let issues = layout.visualLayoutIssues()

        #expect(layout.words.count > 30)
        #expect(
            issues.isEmpty,
            "Poppler text layout has visual issues:\n\(issues.joined(separator: "\n"))",
        )
    }

    @Test("Generated PDFs do not have overlapping MuPDF character quads")
    func generatedPDFsDoNotHaveOverlappingMuPDFCharacterQuads() throws {
        let data = try visualValidationPDF()
        let result = try PDFValidation.mutoolStructuredText(data: data, name: "visual-layout-mupdf")
        try #require(result.exitCode == 0, "mutool structured text failed:\n\(result.output)")

        let layout = try MuPDFStructuredText(xml: result.output)
        let visibleGlyphCount = layout.glyphs.count(where: { !$0.isWhitespace })
        let issues = layout.characterQuadIssues()

        #expect(visibleGlyphCount > 200)
        #expect(
            issues.isEmpty,
            "MuPDF character layout has visual issues:\n\(issues.joined(separator: "\n"))",
        )
    }

    @Test("Poppler and MuPDF render comparable ink bounds")
    func popplerAndMuPDFRenderComparableInkBounds() throws {
        let data = try visualValidationPDF()
        let poppler = try PDFValidation.pdftoppmPNM(data: data, name: "visual-layout-poppler")
        let mupdf = try PDFValidation.mutoolPNM(data: data, name: "visual-layout-mupdf")
        try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed:\n\(poppler.result.output)")
        try #require(mupdf.result.exitCode == 0, "mutool PNM failed:\n\(mupdf.result.output)")

        let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURL))
        let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURL))
        let issues = rasterComparisonIssues(poppler: popplerImage, mupdf: mupdfImage)

        #expect(
            issues.isEmpty,
            "Poppler and MuPDF raster output diverged:\n\(issues.joined(separator: "\n"))",
        )
    }

    @Test("Visual layout validator rejects overlapping words")
    func visualLayoutValidatorRejectsOverlappingWords() throws {
        let layout = try PopplerTextLayout(tsv: """
        level\tpage_num\tpar_num\tblock_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
        1\t1\t0\t0\t0\t0\t0.000000\t0.000000\t200.000000\t200.000000\t-1\t###PAGE###
        4\t1\t0\t1\t0\t0\t10.000000\t20.000000\t60.000000\t10.000000\t-1\t###LINE###
        5\t1\t0\t1\t0\t0\t10.00\t20.00\t40.00\t10.00\t100\tFirst
        5\t1\t0\t1\t0\t1\t49.00\t20.00\t30.00\t10.00\t100\tSecond
        """)

        #expect(layout.visualLayoutIssues().contains { $0.contains("overlaps") })
    }

    @Test("MuPDF character quad validator rejects overlapping glyphs")
    func muPDFCharacterQuadValidatorRejectsOverlappingGlyphs() throws {
        let layout = try MuPDFStructuredText(xml: """
        <?xml version="1.0"?>
        <document filename="overlap.pdf">
        <page id="page1" width="100" height="100">
        <block bbox="10 10 40 20" justify="unknown">
        <line bbox="10 10 40 20" wmode="0" dir="1 0" flags="0" text="AB">
        <font name="Helvetica" size="12">
        <char quad="10 10 20 10 10 20 20 20" x="10" y="20" c="A"/>
        <char quad="19 10 30 10 19 20 30 20" x="19" y="20" c="B"/>
        </font>
        </line>
        </block>
        </page>
        </document>
        """)

        #expect(layout.characterQuadIssues().contains { $0.contains("overlaps") })
    }

    @Test("Raster comparison rejects divergent ink bounds")
    func rasterComparisonRejectsDivergentInkBounds() throws {
        let poppler = try PNMImage(data: pnmImage(width: 20, height: 20, inkBox: 2 ... 5))
        let mupdf = try PNMImage(data: pnmImage(width: 20, height: 20, inkBox: 16 ... 19))

        #expect(rasterComparisonIssues(poppler: poppler, mupdf: mupdf).contains { $0.contains("ink bounds differ") })
    }

    private func visualValidationPDF() throws -> Data {
        let markdown = """
        # Visual validation

        This fixture checks proportional spacing, **bold spacing**, *italic spacing*,
        and `monospaced spacing` on narrow pages.

        | Column | Description |
        |---|---|
        | Alpha | Several words should remain separated. |
        | Beta | Wide letters like WWWWWW and narrow letters like iiiiii both render. |

        The renderer should wrap text without causing adjacent words to collide.
        Another paragraph gives Poppler enough lines to expose vertical spacing
        problems if text positions are too tight.
        """

        return try MarkdownPDFRenderer(
            options: PDFOptions(
                pageSize: PDFOptions.PageSize(width: 260, height: 320),
                margins: PDFOptions.Margins(top: 24, right: 22, bottom: 24, left: 22),
                baseFontSize: 10,
            ),
        ).render(markdown: markdown)
    }

    private func rasterComparisonIssues(poppler: PNMImage, mupdf: PNMImage) -> [String] {
        var issues: [String] = []
        if poppler.width != mupdf.width || poppler.height != mupdf.height {
            issues.append(
                "image dimensions differ: Poppler \(poppler.width)x\(poppler.height), "
                    + "MuPDF \(mupdf.width)x\(mupdf.height)",
            )
        }

        let popplerInk = poppler.inkMetrics()
        let mupdfInk = mupdf.inkMetrics()
        if popplerInk.nonWhitePixelCount < 1000 {
            issues.append("Poppler rendered too little ink: \(popplerInk.nonWhitePixelCount) pixels")
        }
        if mupdfInk.nonWhitePixelCount < 1000 {
            issues.append("MuPDF rendered too little ink: \(mupdfInk.nonWhitePixelCount) pixels")
        }

        guard let popplerBox = popplerInk.box,
              let mupdfBox = mupdfInk.box
        else {
            issues.append("one renderer produced a blank page")
            return issues
        }

        let allowedDelta = 12
        if abs(popplerBox.left - mupdfBox.left) > allowedDelta
            || abs(popplerBox.top - mupdfBox.top) > allowedDelta
            || abs(popplerBox.right - mupdfBox.right) > allowedDelta
            || abs(popplerBox.bottom - mupdfBox.bottom) > allowedDelta
        {
            issues.append("ink bounds differ: Poppler \(popplerBox), MuPDF \(mupdfBox)")
        }

        let inkRatio = Double(mupdfInk.nonWhitePixelCount) / Double(popplerInk.nonWhitePixelCount)
        if inkRatio < 0.5 || inkRatio > 1.8 {
            issues.append(
                "ink coverage differs: Poppler \(popplerInk.nonWhitePixelCount), "
                    + "MuPDF \(mupdfInk.nonWhitePixelCount)",
            )
        }

        return issues
    }

    private func pnmImage(width: Int, height: Int, inkBox: ClosedRange<Int>) -> Data {
        var data = Data("P5\n\(width) \(height)\n255\n".utf8)
        for y in 0 ..< height {
            for x in 0 ..< width {
                data.append(inkBox.contains(x) && inkBox.contains(y) ? 0 : 255)
            }
        }
        return data
    }
}

private struct PopplerTextLayout {
    struct Box: Equatable {
        var level: Int
        var page: Int
        var paragraph: Int
        var block: Int
        var line: Int
        var word: Int
        var left: Double
        var top: Double
        var width: Double
        var height: Double
        var text: String

        var right: Double {
            left + width
        }

        var bottom: Double {
            top + height
        }
    }

    var boxes: [Box]

    var pages: [Box] {
        boxes.filter { $0.level == 1 }
    }

    var lines: [Box] {
        boxes.filter { $0.level == 4 }
    }

    var words: [Box] {
        boxes.filter { $0.level == 5 && !$0.text.isEmpty }
    }

    init(tsv: String) throws {
        boxes = try tsv
            .split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst()
            .map { line in
                try Self.parse(line: String(line))
            }
    }

    func visualLayoutIssues() -> [String] {
        var issues: [String] = []
        validateBoxesHavePositiveSize(issues: &issues)
        validateWordsFitPageBounds(issues: &issues)
        validateWordsDoNotOverlap(issues: &issues)
        validateLinesDoNotOverlap(issues: &issues)
        return issues
    }

    private func validateBoxesHavePositiveSize(issues: inout [String]) {
        for box in words + lines + pages where box.width <= 0 || box.height <= 0 {
            issues.append("\(boxDescription(box)) has non-positive size")
        }
    }

    private func validateWordsFitPageBounds(issues: inout [String]) {
        let pagesByNumber = Dictionary(uniqueKeysWithValues: pages.map { ($0.page, $0) })
        for word in words {
            guard let page = pagesByNumber[word.page] else {
                issues.append("\(boxDescription(word)) references missing page \(word.page)")
                continue
            }

            if word.left < page.left - tolerance
                || word.top < page.top - tolerance
                || word.right > page.right + tolerance
                || word.bottom > page.bottom + tolerance
            {
                issues.append("\(boxDescription(word)) is outside page bounds")
            }
        }
    }

    private func validateWordsDoNotOverlap(issues: inout [String]) {
        for group in groupedWordsByLine() {
            let sortedWords = group.sorted { left, right in
                if left.left == right.left {
                    return left.word < right.word
                }
                return left.left < right.left
            }

            for (left, right) in zip(sortedWords, sortedWords.dropFirst()) {
                if right.left < left.right - tolerance {
                    issues.append("\(boxDescription(left)) overlaps \(boxDescription(right))")
                }
            }
        }
    }

    private func validateLinesDoNotOverlap(issues: inout [String]) {
        for group in groupedLinesByBlock() {
            let sortedLines = group.sorted { left, right in
                if left.top == right.top {
                    return left.line < right.line
                }
                return left.top < right.top
            }

            for (top, bottom) in zip(sortedLines, sortedLines.dropFirst()) {
                if bottom.top < top.bottom - tolerance {
                    issues.append("\(boxDescription(top)) collides vertically with \(boxDescription(bottom))")
                }
            }
        }
    }

    private func groupedWordsByLine() -> [[Box]] {
        Dictionary(grouping: words) { box in
            "\(box.page):\(box.paragraph):\(box.block):\(box.line)"
        }.values.map(Array.init)
    }

    private func groupedLinesByBlock() -> [[Box]] {
        Dictionary(grouping: lines) { box in
            "\(box.page):\(box.paragraph):\(box.block)"
        }.values.map(Array.init)
    }

    private func boxDescription(_ box: Box) -> String {
        "page \(box.page) paragraph \(box.paragraph) block \(box.block) line \(box.line) word \(box.word) '\(box.text)'"
    }

    private static func parse(line: String) throws -> Box {
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard columns.count >= 12,
              let level = Int(columns[0]),
              let page = Int(columns[1]),
              let paragraph = Int(columns[2]),
              let block = Int(columns[3]),
              let lineNumber = Int(columns[4]),
              let word = Int(columns[5]),
              let left = Double(columns[6]),
              let top = Double(columns[7]),
              let width = Double(columns[8]),
              let height = Double(columns[9])
        else {
            throw PDFVisualLayoutValidationError.invalidTSVLine(line)
        }

        return Box(
            level: level,
            page: page,
            paragraph: paragraph,
            block: block,
            line: lineNumber,
            word: word,
            left: left,
            top: top,
            width: width,
            height: height,
            text: columns[11...].joined(separator: "\t"),
        )
    }

    private let tolerance = 0.5
}

private enum PDFVisualLayoutValidationError: Error {
    case invalidTSVLine(String)
}
