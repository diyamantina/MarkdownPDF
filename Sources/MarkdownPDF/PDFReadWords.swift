/// Gathers the characters a content stream shows into words with their boxes, for
/// ``PDFDocumentReader``.
///
/// A character that is white space ends the word before it. A character continues
/// the open word when it sits on the same baseline and starts where the word ends:
/// no more than a tenth of the font size after it, and no more than half a point
/// before it. Anything else starts a new word, so two pieces of text drawn over
/// each other stay two words whose boxes overlap.
struct PDFReadWords {
    private(set) var words: [PDFDocumentReader.Word] = []
    /// Whether the last word can still grow.
    private var isOpen = false

    /// Ends the open word.
    mutating func close() {
        isOpen = false
    }

    /// Adds one shown character, or the text of a whole `/ActualText` span, and
    /// returns the index of the word it became part of, or nil for white space.
    @discardableResult
    mutating func add(_ text: String, x: Double, y: Double, width: Double, fontSize: Double) -> Int? {
        var visible = String(text.drop(while: \.isWhitespace))
        while visible.last?.isWhitespace == true {
            visible.removeLast()
        }
        guard !visible.isEmpty else {
            close()
            return nil
        }
        let startsWithSpace = text.first?.isWhitespace == true
        if isOpen, !startsWithSpace, let last = words.indices.last, abs(words[last].y - y) <= 0.01 {
            let gap = x - (words[last].x + words[last].width)
            if gap <= fontSize * 0.1, gap >= -0.5 {
                words[last].text += visible
                words[last].width = max(words[last].width, x + width - words[last].x)
                words[last].fontSize = max(words[last].fontSize, fontSize)
                isOpen = text.last?.isWhitespace != true
                return last
            }
        }
        words.append(PDFDocumentReader.Word(x: x, y: y, width: width, fontSize: fontSize, text: visible))
        isOpen = text.last?.isWhitespace != true
        return words.count - 1
    }

    /// Stretches a word to reach `end`, for a span whose text is drawn by several operators.
    mutating func extend(_ index: Int, to end: Double) {
        words[index].width = max(words[index].width, end - words[index].x)
    }
}
