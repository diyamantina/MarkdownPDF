struct PDFContentStream {
    private var lines: [Line] = []

    /// Where page content begins, after whatever the page background drew.
    ///
    /// Marks are appended in paint order, so anything that must sit *under* text
    /// already emitted has to be inserted, not appended. A block quote's background
    /// is the case: its height is unknown until its blocks have rendered.
    private var contentStartIndex = 0

    var serialized: String {
        lines.map(\.serialized).joined()
    }

    mutating func append(_ contentOperator: Operator) {
        append([contentOperator])
    }

    mutating func append(_ operators: [Operator]) {
        guard !operators.isEmpty else {
            return
        }

        lines.append(Line(operators: operators))
    }

    /// Records that everything appended from here on is page content, so a later
    /// insert lands above the page background and below the content.
    mutating func markContentStart() {
        contentStartIndex = lines.count
    }

    /// Inserts one line of operators immediately after the page background.
    ///
    /// Successive inserts stack in reverse: the last one inserted is drawn first.
    /// Nested block quotes rely on that, so an inner quote's background paints over
    /// its outer quote's rather than under it.
    mutating func insertAtContentStart(_ operators: [Operator]) {
        guard !operators.isEmpty else {
            return
        }

        lines.insert(Line(operators: operators), at: min(contentStartIndex, lines.count))
    }

    struct Line {
        var operators: [Operator]

        var serialized: String {
            operators.map(\.serialized).joined(separator: " ") + "\n"
        }
    }

    enum Operator: Equatable {
        case beginText
        case setFont(PDFSyntax.Name, size: Double)
        case moveText(x: Double, y: Double)
        case showText(PDFSyntax.LiteralString)
        case showCIDText([UInt16])
        case endText
        case setFillColor(PDFColor)
        case setStrokeColor(PDFColor)
        case setLineWidth(Double)
        case setDash(lengths: [Double], phase: Double)
        case moveTo(x: Double, y: Double)
        case lineTo(x: Double, y: Double)
        case curveTo(x1: Double, y1: Double, x2: Double, y2: Double, x3: Double, y3: Double)
        case rectangle(x: Double, y: Double, width: Double, height: Double)
        case closePath
        case stroke
        case fill
        case fillAndStroke
        case saveGraphicsState
        case restoreGraphicsState
        case beginMarkedContent(PDFSyntax.Name, mcid: Int)
        case beginActualText(PDFSyntax.LiteralString)
        /// `/ActualText` as a UTF-16BE hex string (with BOM), for text a WinAnsi
        /// literal cannot carry (Arabic, Hebrew, and any non-Latin extraction override).
        case beginActualTextUTF16(PDFSyntax.HexString)
        case beginArtifact
        case endMarkedContent
        case concatenateMatrix(
            a: Double,
            b: Double,
            c: Double,
            d: Double,
            e: Double,
            f: Double,
        )
        case drawXObject(PDFSyntax.Name)

        var serialized: String {
            switch self {
            case .beginText:
                "BT"
            case let .setFont(name, size):
                "\(name.serialized) \(pdfNumber(size)) Tf"
            case let .moveText(x, y):
                "\(pdfNumber(x)) \(pdfNumber(y)) Td"
            case let .showText(text):
                "\(text.serialized) Tj"
            case let .showCIDText(codes):
                "\(PDFSyntax.HexString(twoByteCodes: codes).serialized) Tj"
            case .endText:
                "ET"
            case let .setFillColor(color):
                "\(pdfNumber(color.red)) \(pdfNumber(color.green)) \(pdfNumber(color.blue)) rg"
            case let .setStrokeColor(color):
                "\(pdfNumber(color.red)) \(pdfNumber(color.green)) \(pdfNumber(color.blue)) RG"
            case let .setLineWidth(width):
                "\(pdfNumber(width)) w"
            case let .setDash(lengths, phase):
                "[\(lengths.map { pdfNumber($0) }.joined(separator: " "))] \(pdfNumber(phase)) d"
            case let .moveTo(x, y):
                "\(pdfNumber(x)) \(pdfNumber(y)) m"
            case let .lineTo(x, y):
                "\(pdfNumber(x)) \(pdfNumber(y)) l"
            case let .curveTo(x1, y1, x2, y2, x3, y3):
                "\(pdfNumber(x1)) \(pdfNumber(y1)) \(pdfNumber(x2)) \(pdfNumber(y2)) \(pdfNumber(x3)) \(pdfNumber(y3)) c"
            case let .rectangle(x, y, width, height):
                "\(pdfNumber(x)) \(pdfNumber(y)) \(pdfNumber(width)) \(pdfNumber(height)) re"
            case .closePath:
                "h"
            case .stroke:
                "S"
            case .fill:
                "f"
            case .fillAndStroke:
                "B"
            case .saveGraphicsState:
                "q"
            case .restoreGraphicsState:
                "Q"
            case let .beginMarkedContent(tag, mcid):
                "\(tag.serialized) << /MCID \(mcid) >> BDC"
            case let .beginActualText(text):
                "/Span << /ActualText \(text.serialized) >> BDC"
            case let .beginActualTextUTF16(hex):
                "/Span << /ActualText \(hex.serialized) >> BDC"
            case .beginArtifact:
                "/Artifact BMC"
            case .endMarkedContent:
                "EMC"
            case let .concatenateMatrix(a, b, c, d, e, f):
                "\(pdfNumber(a)) \(pdfNumber(b)) \(pdfNumber(c)) \(pdfNumber(d)) \(pdfNumber(e)) \(pdfNumber(f)) cm"
            case let .drawXObject(name):
                "\(name.serialized) Do"
            }
        }

        private func pdfNumber(_ value: Double) -> String {
            PDFSyntax.Number(value).serialized
        }
    }
}
