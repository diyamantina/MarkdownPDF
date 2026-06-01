struct PDFContentStream {
    private var lines: [Line] = []

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
        case moveTo(x: Double, y: Double)
        case lineTo(x: Double, y: Double)
        case rectangle(x: Double, y: Double, width: Double, height: Double)
        case stroke
        case fill
        case saveGraphicsState
        case restoreGraphicsState
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
            case let .moveTo(x, y):
                "\(pdfNumber(x)) \(pdfNumber(y)) m"
            case let .lineTo(x, y):
                "\(pdfNumber(x)) \(pdfNumber(y)) l"
            case let .rectangle(x, y, width, height):
                "\(pdfNumber(x)) \(pdfNumber(y)) \(pdfNumber(width)) \(pdfNumber(height)) re"
            case .stroke:
                "S"
            case .fill:
                "f"
            case .saveGraphicsState:
                "q"
            case .restoreGraphicsState:
                "Q"
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
