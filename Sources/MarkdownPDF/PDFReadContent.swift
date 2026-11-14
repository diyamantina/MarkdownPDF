/// Turns the content stream of a page into the text it shows, for ``PDFDocumentReader``.
enum PDFReadContent {
    /// How the bytes of a shown string become text under one font.
    struct Font {
        var name: String
        /// 2 for a composite font, 1 for a simple one.
        var bytesPerCode: Int
        /// The `/ToUnicode` map, or nil for a simple font, which is read as WinAnsi.
        var toUnicode: [Int: String]?
        /// The advance of each code in thousandths of the font size, from `/Widths` or `/W`.
        var widths: [Int: Double] = [:]
        /// The advance of a code `widths` lacks.
        var defaultWidth = 0.0
        /// Whether the font's descriptor holds a font program.
        var isEmbedded = false

        /// The advance of the string at `size`, in points.
        func width(of bytes: [UInt8], size: Double) -> Double {
            var total = 0.0
            var index = 0
            while index + bytesPerCode <= bytes.count {
                let code = bytesPerCode == 2 ? Int(bytes[index]) << 8 | Int(bytes[index + 1]) : Int(bytes[index])
                index += bytesPerCode
                total += widths[code] ?? defaultWidth
            }
            return total * size / 1000
        }

        /// Each code of the string as its text and its advance at `size`, in points.
        func characters(for bytes: [UInt8], size: Double) -> [(text: String, width: Double)] {
            stride(from: 0, to: bytes.count - bytesPerCode + 1, by: bytesPerCode).map { index in
                let code = Array(bytes[index ..< index + bytesPerCode])
                return (text(for: code), width(of: code, size: size))
            }
        }

        func text(for bytes: [UInt8]) -> String {
            var text = ""
            var index = 0
            while index + bytesPerCode <= bytes.count {
                let code = bytesPerCode == 2 ? Int(bytes[index]) << 8 | Int(bytes[index + 1]) : Int(bytes[index])
                index += bytesPerCode
                if let toUnicode {
                    // A code the map lacks has no known character.
                    text += toUnicode[code] ?? "\u{FFFD}"
                } else {
                    text.unicodeScalars.append(PDFTextEncoding.winAnsiScalar(for: UInt8(code)))
                }
            }
            return text
        }
    }

    /// The fonts of a page's resources, by resource name.
    static func fonts(in resources: [String: PDFReadValue], store: PDFReadObjects) throws -> [String: Font] {
        var fonts: [String: Font] = [:]
        for (resource, reference) in resources {
            let dictionary = try store.dictionary(reference, what: "the font /\(resource)")
            let composite = dictionary["Subtype"]?.name == "Type0"
            var toUnicode: [Int: String]?
            if case .stream = try store.resolve(dictionary["ToUnicode"]) {
                toUnicode = try characterMap(store.streamData(dictionary["ToUnicode"]))
            } else if composite {
                // A composite font with no map has no recoverable characters.
                toUnicode = [:]
            }
            var font = try Font(
                name: store.resolve(dictionary["BaseFont"]).name ?? resource,
                bytesPerCode: composite ? 2 : 1,
                toUnicode: toUnicode,
            )
            let descendants = try store.resolve(dictionary["DescendantFonts"]).array ?? []
            let descendant = try store.resolve(descendants.first).dictionary ?? [:]
            let descriptor = try store.resolve(composite ? descendant["FontDescriptor"] : dictionary["FontDescriptor"]).dictionary ?? [:]
            font.isEmbedded = ["FontFile", "FontFile2", "FontFile3"].contains { descriptor[$0] != nil }
            if composite {
                font.defaultWidth = try store.resolve(descendant["DW"]).number ?? 1000
                font.widths = try compositeWidths(store.resolve(descendant["W"]).array ?? [], store: store)
            } else if let first = try store.resolve(dictionary["FirstChar"]).number {
                for (offset, width) in try (store.resolve(dictionary["Widths"]).array ?? []).enumerated() {
                    font.widths[Int(first) + offset] = try store.resolve(width).number
                }
            } else {
                // A standard font carries no widths in the file. Its advances are the
                // engine's own tables, the ones the layout measured the text with.
                let metrics: StandardFont = if font.name.hasPrefix("Courier") || font.name.hasPrefix("SFMono") {
                    .courier
                } else if font.name.contains("Bold") {
                    .helveticaBold
                } else {
                    .helvetica
                }
                for byte in UInt8.min ... UInt8.max {
                    var character = String.UnicodeScalarView()
                    character.append(PDFTextEncoding.winAnsiScalar(for: byte))
                    font.widths[Int(byte)] = metrics.width(of: String(character), size: 1000, fontSet: .pdfBase)
                }
            }
            fonts[resource] = font
        }
        return fonts
    }

    /// Reads a `/W` array: `c [w1 w2 ...]` gives consecutive codes from `c` their own
    /// widths, and `first last w` gives every code of the range one width.
    private static func compositeWidths(_ entries: [PDFReadValue], store: PDFReadObjects) throws -> [Int: Double] {
        var widths: [Int: Double] = [:]
        var index = 0
        while index + 1 < entries.count {
            guard let first = try store.resolve(entries[index]).number.map({ Int($0) }) else {
                throw PDFDocumentReader.ReadError.malformed("a /W array does not start an entry with a code")
            }
            let second = try store.resolve(entries[index + 1])
            if let list = second.array {
                for (offset, width) in list.enumerated() {
                    widths[first + offset] = try store.resolve(width).number
                }
                index += 2
            } else if let last = second.number.map({ Int($0) }), index + 2 < entries.count, let width = try store.resolve(entries[index + 2]).number, first <= last {
                for code in first ... last {
                    widths[code] = width
                }
                index += 3
            } else {
                throw PDFDocumentReader.ReadError.malformed("a /W array entry is neither a list nor a range")
            }
        }
        return widths
    }

    /// Reads the `bfchar` and `bfrange` sections of a `/ToUnicode` CMap.
    static func characterMap(_ bytes: [UInt8]) throws -> [Int: String] {
        func code(_ value: PDFReadValue) -> Int? {
            value.bytes.map { $0.reduce(0) { $0 << 8 | Int($1) } }
        }
        var map: [Int: String] = [:]
        var scanner = PDFReadScanner(bytes)
        while let operation = try scanner.nextOperation() {
            let operands = operation.operands
            switch operation.operator {
            case "endbfchar":
                for pair in stride(from: 0, to: operands.count - 1, by: 2) {
                    if let source = code(operands[pair]), let target = operands[pair + 1].bytes {
                        map[source] = PDFDocumentReader.utf16BigEndian(target)
                    }
                }
            case "endbfrange":
                for triple in stride(from: 0, to: operands.count - 2, by: 3) {
                    guard let low = code(operands[triple]), let high = code(operands[triple + 1]), low <= high else {
                        continue
                    }
                    if let targets = operands[triple + 2].array {
                        for (offset, target) in targets.enumerated() where low + offset <= high {
                            map[low + offset] = target.bytes.map(PDFDocumentReader.utf16BigEndian)
                        }
                    } else if let start = operands[triple + 2].bytes, start.count >= 2 {
                        // The last UTF-16 unit of the target counts up through the range.
                        let prefix = Array(start.dropLast(2))
                        let last = Int(start[start.count - 2]) << 8 | Int(start[start.count - 1])
                        for offset in 0 ... (high - low) {
                            let unit = last + offset
                            map[low + offset] = PDFDocumentReader.utf16BigEndian(prefix + [UInt8(unit >> 8 & 0xFF), UInt8(unit & 0xFF)])
                        }
                    }
                }
            default:
                continue
            }
        }
        return map
    }

    /// One open marked-content sequence: its replacement text, when it has one, and
    /// the index of the run that text was given out as, once it has been.
    private struct MarkedContent {
        var actualText: String?
        var run: Int?
        /// The index of the word the span's text became, when it is not white space.
        var word: Int?
    }

    /// The text runs of a content stream, in drawing order, and the same text as
    /// words. Inside an `/ActualText` span the span's text stands in for what is
    /// drawn, once, where the span starts.
    static func text(in content: [UInt8], fonts: [String: Font]) throws -> (runs: [PDFDocumentReader.TextRun], words: [PDFDocumentReader.Word]) {
        var runs: [PDFDocumentReader.TextRun] = []
        var words = PDFReadWords()
        var font: Font?
        var fontSize = 0.0
        var lineX = 0.0
        var lineY = 0.0
        var marked: [MarkedContent] = []
        var scanner = PDFReadScanner(content)

        func show(_ bytes: [UInt8]) {
            guard let font else {
                return
            }
            let width = font.width(of: bytes, size: fontSize)
            if let span = marked.lastIndex(where: { $0.actualText != nil }) {
                if let run = marked[span].run {
                    // More of the same span: its run grows to the end of this string.
                    runs[run].width = max(runs[run].width, lineX + width - runs[run].x)
                    if let word = marked[span].word {
                        words.extend(word, to: lineX + width)
                    }
                } else if let text = marked[span].actualText {
                    marked[span].run = runs.count
                    marked[span].word = words.add(text, x: lineX, y: lineY, width: width, fontSize: fontSize)
                    runs.append(PDFDocumentReader.TextRun(x: lineX, y: lineY, width: width, fontSize: fontSize, fontName: font.name, text: text))
                }
                return
            }
            var x = lineX
            for character in font.characters(for: bytes, size: fontSize) {
                words.add(character.text, x: x, y: lineY, width: character.width, fontSize: fontSize)
                x += character.width
            }
            runs.append(PDFDocumentReader.TextRun(x: lineX, y: lineY, width: width, fontSize: fontSize, fontName: font.name, text: font.text(for: bytes)))
        }

        while let operation = try scanner.nextOperation() {
            let operands = operation.operands
            switch operation.operator {
            case "BT":
                lineX = 0
                lineY = 0
            case "Tf":
                guard operands.count == 2, let name = operands[0].name, let size = operands[1].number else {
                    throw PDFDocumentReader.ReadError.malformed("Tf without a font and a size")
                }
                guard let selected = fonts[name] else {
                    throw PDFDocumentReader.ReadError.malformed("the font /\(name) is not in the page resources")
                }
                font = selected
                fontSize = size
            case "Td", "TD":
                guard operands.count == 2, let x = operands[0].number, let y = operands[1].number else {
                    throw PDFDocumentReader.ReadError.malformed("Td without two numbers")
                }
                lineX += x
                lineY += y
            case "Tm":
                guard operands.count == 6, let x = operands[4].number, let y = operands[5].number else {
                    throw PDFDocumentReader.ReadError.malformed("Tm without six numbers")
                }
                lineX = x
                lineY = y
            case "Tj":
                guard let bytes = operands.first?.bytes else {
                    throw PDFDocumentReader.ReadError.malformed("Tj without a string")
                }
                show(bytes)
            case "TJ":
                show((operands.first?.array ?? []).flatMap { $0.bytes ?? [] })
            case "'", "\"", "T*":
                throw PDFDocumentReader.ReadError.unsupported("the text operator \(operation.operator)")
            case "BMC":
                marked.append(MarkedContent())
            case "BDC":
                let text = operands.last?.dictionary?["ActualText"]?.bytes.map(PDFDocumentReader.textString)
                marked.append(MarkedContent(actualText: text))
            case "EMC":
                if let closed = marked.popLast(), closed.run == nil, let text = closed.actualText, !text.isEmpty, let font {
                    // A span that showed no text of its own still stands for its text.
                    runs.append(PDFDocumentReader.TextRun(x: lineX, y: lineY, width: 0, fontSize: fontSize, fontName: font.name, text: text))
                }
            default:
                continue
            }
        }
        return (runs, words.words)
    }
}
