import Foundation

/// Printed page labels: the text a page number takes in a footer, the table of
/// contents, and the index.
enum PDFPageLabel {
    /// The bare label for `number`. `.ofTotal` prints plain decimal here, because
    /// its `Page 1 of N` wording belongs to the footer only.
    static func text(_ number: Int, format: PDFOptions.PageNumbers.Format) -> String {
        switch format {
        case .plain, .ofTotal:
            String(number)
        case .romanLowercase:
            roman(number) ?? String(number)
        }
    }

    /// The footer text for `number`, given the printed number of the last page.
    static func footerText(_ number: Int, last: Int, format: PDFOptions.PageNumbers.Format) -> String {
        switch format {
        case .plain, .romanLowercase:
            text(number, format: format)
        case .ofTotal:
            "Page \(number) of \(last)"
        }
    }

    /// Lowercase Roman numerals for `1 ... 3999`, nil outside that range.
    static func roman(_ number: Int) -> String? {
        guard (1 ... 3999).contains(number) else {
            return nil
        }

        let numerals: [(value: Int, symbol: String)] = [
            (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
            (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
        ]
        var remaining = number
        var result = ""
        for numeral in numerals {
            while remaining >= numeral.value {
                result += numeral.symbol
                remaining -= numeral.value
            }
        }
        return result
    }

    /// Collapses sorted, distinct physical page indices into printed references:
    /// each run of consecutive pages becomes one `(label, firstPage)` where the
    /// label is `12-14` (ASCII hyphen) and `firstPage` is the link target.
    static func references(
        forPages pages: [Int],
        label: (Int) -> String,
    ) -> [(text: String, targetPage: Int)] {
        var result: [(text: String, targetPage: Int)] = []
        var index = 0
        while index < pages.count {
            var end = index
            while end + 1 < pages.count, pages[end + 1] == pages[end] + 1 {
                end += 1
            }
            let first = label(pages[index])
            result.append((
                text: end == index ? first : "\(first)-\(label(pages[end]))",
                targetPage: pages[index],
            ))
            index = end + 1
        }
        return result
    }
}
