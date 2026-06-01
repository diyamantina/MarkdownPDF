import Foundation

final class PDFPageCanvas {
    private(set) var commands: String = ""
    private(set) var linkAnnotations: [PDFLinkAnnotation] = []
    private(set) var resourceUsage = PDFPageResourceUsage()

    func drawTextRun(
        _ run: PDFTextRun,
        x: Double,
        y: Double,
        fontSet: PDFOptions.FontSet,
    ) {
        resourceUsage.useFont(run.font)
        setFillColor(run.color)
        let fontName = PDFSyntax.Name(run.font.rawValue).serialized
        let text = PDFSyntax.LiteralString(run.text).serialized
        append(
            "BT \(fontName) \(pdfNumber(run.size)) Tf \(pdfNumber(x)) \(pdfNumber(y)) Td \(text) Tj ET\n",
        )

        let width = run.width(fontSet: fontSet)
        if run.underline {
            drawLine(
                x1: x,
                y1: y - 1.5,
                x2: x + width,
                y2: y - 1.5,
                width: 0.5,
                color: run.color,
            )
        }
        if run.strikethrough {
            drawLine(
                x1: x,
                y1: y + run.size * 0.32,
                x2: x + width,
                y2: y + run.size * 0.32,
                width: 0.5,
                color: run.color,
            )
        }
        if let destination = run.linkDestination, !destination.isEmpty, width > 0 {
            linkAnnotations.append(
                PDFLinkAnnotation(
                    x: x,
                    y: y - run.size * 0.25,
                    width: width,
                    height: run.size * 1.15,
                    destination: destination,
                ),
            )
        }
    }

    func drawLine(
        x1: Double,
        y1: Double,
        x2: Double,
        y2: Double,
        width: Double,
        color: PDFColor = .black,
    ) {
        setStrokeColor(color)
        append(
            "\(pdfNumber(width)) w \(pdfNumber(x1)) \(pdfNumber(y1)) m \(pdfNumber(x2)) \(pdfNumber(y2)) l S\n",
        )
    }

    func drawRectangle(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        stroke: PDFColor? = .black,
        fill: PDFColor? = nil,
    ) {
        if let fill {
            setFillColor(fill)
            append("\(pdfNumber(x)) \(pdfNumber(y)) \(pdfNumber(width)) \(pdfNumber(height)) re f\n")
        }
        if let stroke {
            setStrokeColor(stroke)
            append("0.5 w \(pdfNumber(x)) \(pdfNumber(y)) \(pdfNumber(width)) \(pdfNumber(height)) re S\n")
        }
    }

    func drawImage(
        name: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
    ) {
        resourceUsage.useImageXObject(named: name)
        let imageName = PDFSyntax.Name(name).serialized
        append(
            "q \(pdfNumber(width)) 0 0 \(pdfNumber(height)) \(pdfNumber(x)) \(pdfNumber(y)) cm \(imageName) Do Q\n",
        )
    }

    private func setFillColor(_ color: PDFColor) {
        append("\(pdfNumber(color.red)) \(pdfNumber(color.green)) \(pdfNumber(color.blue)) rg\n")
    }

    private func setStrokeColor(_ color: PDFColor) {
        append("\(pdfNumber(color.red)) \(pdfNumber(color.green)) \(pdfNumber(color.blue)) RG\n")
    }

    private func pdfNumber(_ value: Double) -> String {
        PDFSyntax.Number(value).serialized
    }

    private func append(_ command: String) {
        commands.append(command)
    }
}
