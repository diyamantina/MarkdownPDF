import Foundation
@testable import MarkdownPDF

/// The word boxes of a rendered PDF, read back with `PDFDocumentReader`, and the
/// layout checks the visual witnesses run on them.
///
/// The boxes come from the bytes of the file: where each text operator puts its
/// string and how far the widths the fonts declare advance it. That is what a
/// viewer advances by, so a wrong width table or a wrong position shows up here
/// as words that overlap or leave the page. Coordinates are in points from the
/// top left corner of the page. A word box is one em tall: three quarters of the
/// font size above the baseline and one quarter below, the line box the renderer
/// itself uses.
struct ReaderTextLayout {
    struct Box: Equatable {
        /// The page, counted from 1.
        var page: Int
        /// The position of the word among the words of its page, in drawing order, from 1.
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

        /// The baseline, a quarter of the height above the bottom of the box.
        var baseline: Double {
            top + height * 0.75
        }
    }

    /// The size of each page, in points.
    var pages: [PDFOptions.PageSize]
    var words: [Box]

    init(pages: [PDFOptions.PageSize], words: [Box]) {
        self.pages = pages
        self.words = words
    }

    init(_ document: PDFDocumentReader) {
        pages = document.pages.map(\.size)
        words = document.pages.enumerated().flatMap { pageIndex, page in
            page.words.enumerated().map { wordIndex, word in
                Box(
                    page: pageIndex + 1,
                    word: wordIndex + 1,
                    left: word.x,
                    top: page.size.height - word.y - word.fontSize * 0.75,
                    width: word.width,
                    height: word.fontSize,
                    text: word.text,
                )
            }
        }
    }

    init(data: some DataProtocol) throws {
        try self.init(PDFDocumentReader(data: Data(data)))
    }

    /// How many characters that are not white space the words hold.
    var visibleCharacterCount: Int {
        words.reduce(0) { $0 + $1.text.count(where: { !$0.isWhitespace }) }
    }

    /// The boxes as tab separated lines, for a test artifact a person can read.
    var tabSeparated: String {
        (["page\tword\tleft\ttop\twidth\theight\ttext"] + words.map { box in
            let numbers = [box.left, box.top, box.width, box.height].map { String(format: "%.3f", locale: Self.posix, $0) }
            return (["\(box.page)", "\(box.word)"] + numbers + [box.text]).joined(separator: "\t")
        }).joined(separator: "\n") + "\n"
    }

    private static let posix = Locale(identifier: "en_US_POSIX")
    private let tolerance = 0.5

    /// Everything wrong with the layout: a word with no size, a word that leaves its
    /// page, two words of one line that overlap, and two words of different lines
    /// whose boxes run into each other.
    func visualLayoutIssues() -> [String] {
        var issues: [String] = []
        for box in words where box.width <= 0 || box.height <= 0 {
            issues.append("\(description(box)) has non-positive size")
        }
        for (index, size) in pages.enumerated() where size.width <= 0 || size.height <= 0 {
            issues.append("page \(index + 1) has non-positive size")
        }
        validateWordsFitPageBounds(issues: &issues)
        for page in pages.indices {
            let onPage = words.filter { $0.page == page + 1 }.sorted { ($0.left, $0.word) < ($1.left, $1.word) }
            validateWordsDoNotOverlap(onPage, issues: &issues)
        }
        return issues
    }

    private func validateWordsFitPageBounds(issues: inout [String]) {
        for word in words {
            guard pages.indices.contains(word.page - 1) else {
                issues.append("\(description(word)) references missing page \(word.page)")
                continue
            }
            let page = pages[word.page - 1]
            if word.left < -tolerance
                || word.top < -tolerance
                || word.right > page.width + tolerance
                || word.bottom > page.height + tolerance
            {
                issues.append("\(description(word)) is outside page bounds")
            }
        }
    }

    /// `sorted` holds the words of one page from left to right. Two words that
    /// share a baseline overlap when one starts before the other ends. Two words on
    /// different baselines collide when their boxes share more than the tolerance
    /// in both directions.
    private func validateWordsDoNotOverlap(_ sorted: [Box], issues: inout [String]) {
        for leftIndex in sorted.indices {
            let left = sorted[leftIndex]
            for right in sorted.dropFirst(leftIndex + 1) {
                if right.left >= left.right - tolerance {
                    break
                }
                if abs(left.baseline - right.baseline) <= 0.01 {
                    issues.append("\(description(left)) overlaps \(description(right))")
                } else if min(left.bottom, right.bottom) > max(left.top, right.top) + tolerance {
                    let upper = left.top <= right.top ? left : right
                    let lower = left.top <= right.top ? right : left
                    issues.append("\(description(upper)) collides vertically with \(description(lower))")
                }
            }
        }
    }

    private func description(_ box: Box) -> String {
        "page \(box.page) word \(box.word) '\(box.text)'"
    }
}
