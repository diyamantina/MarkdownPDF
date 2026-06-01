import Foundation

final class PDFPageCanvas {
    private var contentStream = PDFContentStream()
    private(set) var linkAnnotations: [PDFLinkAnnotation] = []
    private(set) var headingDestinations: [PDFHeadingDestination] = []
    private(set) var resourceUsage = PDFPageResourceUsage()

    var commands: String {
        contentStream.serialized
    }

    func drawTextRun(
        _ run: PDFTextRun,
        x: Double,
        y: Double,
        fontSet: PDFOptions.FontSet,
    ) {
        resourceUsage.useFont(run.font)
        setFillColor(run.color)
        contentStream.append([
            .beginText,
            .setFont(PDFSyntax.Name(run.font.rawValue), size: run.size),
            .moveText(x: x, y: y),
            .showText(PDFSyntax.LiteralString(run.text)),
            .endText,
        ])

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

    func drawCIDText(
        mapping: TrueTypeGlyphMapper.TextMapping,
        fontResource: PDFEmbeddedFontResource,
        fontSize: Double,
        x: Double,
        y: Double,
        color: PDFColor = .black,
    ) throws {
        guard !mapping.glyphs.isEmpty else {
            return
        }

        try resourceUsage.useEmbeddedFont(fontResource, glyphs: mapping.glyphs)
        setFillColor(color)
        contentStream.append([
            .beginText,
            .setFont(PDFSyntax.Name(fontResource.resourceName), size: fontSize),
            .moveText(x: x, y: y),
            .showCIDText(mapping.glyphs.map(\.pdfCharacterCode)),
            .endText,
        ])
    }

    func addHeadingDestination(_ destination: PDFHeadingDestination) {
        headingDestinations.append(destination)
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
        contentStream.append([
            .setLineWidth(width),
            .moveTo(x: x1, y: y1),
            .lineTo(x: x2, y: y2),
            .stroke,
        ])
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
            contentStream.append([
                .rectangle(x: x, y: y, width: width, height: height),
                .fill,
            ])
        }
        if let stroke {
            setStrokeColor(stroke)
            contentStream.append([
                .setLineWidth(0.5),
                .rectangle(x: x, y: y, width: width, height: height),
                .stroke,
            ])
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
        contentStream.append([
            .saveGraphicsState,
            .concatenateMatrix(a: width, b: 0, c: 0, d: height, e: x, f: y),
            .drawXObject(PDFSyntax.Name(name)),
            .restoreGraphicsState,
        ])
    }

    private func setFillColor(_ color: PDFColor) {
        contentStream.append(.setFillColor(color))
    }

    private func setStrokeColor(_ color: PDFColor) {
        contentStream.append(.setStrokeColor(color))
    }
}
