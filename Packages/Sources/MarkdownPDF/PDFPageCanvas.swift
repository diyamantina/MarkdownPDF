import Foundation

final class PDFPageCanvas {
    struct Point: Equatable {
        var x: Double
        var y: Double
    }

    private var contentStream = PDFContentStream()
    private(set) var linkAnnotations: [PDFLinkAnnotation] = []
    private(set) var headingDestinations: [PDFHeadingDestination] = []
    private(set) var resourceUsage = PDFPageResourceUsage()

    var commands: String {
        contentStream.serialized
    }

    func beginMarkedContent(tag: PDFSyntax.Name, mcid: Int) {
        contentStream.append(.beginMarkedContent(tag, mcid: mcid))
    }

    func beginArtifact() {
        contentStream.append(.beginArtifact)
    }

    func endMarkedContent() {
        contentStream.append(.endMarkedContent)
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
            .showText(PDFSyntax.LiteralString(run.portableText)),
            .endText,
        ])

        let width = run.width(fontSet: fontSet)
        drawDecorations(for: run, x: x, y: y, width: width)
    }

    func drawTextRun(
        _ run: PDFTextRun,
        x: Double,
        y: Double,
        fontSet: PDFOptions.FontSet,
        embeddedFonts: PDFEmbeddedFontCatalog,
    ) throws {
        guard let entry = embeddedFonts.entry(for: run.font) else {
            drawTextRun(run, x: x, y: y, fontSet: fontSet)
            return
        }

        let mapping = try embeddedFonts.shapedMapping(for: run, entry: entry)
        try drawCIDText(
            mapping: mapping,
            fontResource: entry.resource,
            fontSize: run.size,
            x: x,
            y: y,
            color: run.color,
        )
        drawDecorations(for: run, x: x, y: y, width: mapping.totalAdvance)
    }

    func drawCIDText(
        mapping: TrueTypeGlyphMapper.TextMapping,
        fontResource: PDFEmbeddedFontResource,
        fontSize: Double,
        x: Double,
        y: Double,
        color: PDFColor = .black,
    ) throws {
        try drawCIDText(
            mapping: mapping.shapedText(),
            fontResource: fontResource,
            fontSize: fontSize,
            x: x,
            y: y,
            color: color,
        )
    }

    func drawCIDText(
        mapping: ShapedTextMapping,
        fontResource: PDFEmbeddedFontResource,
        fontSize: Double,
        x: Double,
        y: Double,
        color: PDFColor = .black,
        decorationsFor decoratedRun: PDFTextRun? = nil,
    ) throws {
        guard !mapping.glyphs.isEmpty else {
            return
        }

        try resourceUsage.useEmbeddedFont(fontResource, mapping: mapping)
        setFillColor(color)
        contentStream.append([
            .beginText,
            .setFont(PDFSyntax.Name(fontResource.resourceName), size: fontSize),
            .moveText(x: x, y: y),
            .showCIDText(mapping.clusters.flatMap(\.pdfCharacterCodes)),
            .endText,
        ])
        if let decoratedRun {
            drawDecorations(for: decoratedRun, x: x, y: y, width: mapping.totalAdvance)
        }
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

    func drawPolyline(
        points: [Point],
        width: Double,
        color: PDFColor = .black,
    ) {
        guard let first = points.first, points.count > 1 else {
            return
        }

        setStrokeColor(color)
        contentStream.append(
            [
                .setLineWidth(width),
                .moveTo(x: first.x, y: first.y),
            ] + points.dropFirst().map { .lineTo(x: $0.x, y: $0.y) } + [
                .stroke,
            ],
        )
    }

    func drawPolygon(
        points: [Point],
        stroke: PDFColor? = .black,
        fill: PDFColor? = nil,
        lineWidth: Double = 0.5,
    ) {
        guard let first = points.first, points.count > 1 else {
            return
        }

        if let fill, let stroke {
            setFillColor(fill)
            setStrokeColor(stroke)
            contentStream.append(
                [
                    .setLineWidth(lineWidth),
                    .moveTo(x: first.x, y: first.y),
                ] + points.dropFirst().map { .lineTo(x: $0.x, y: $0.y) } + [
                    .closePath,
                    .fillAndStroke,
                ],
            )
        } else if let fill {
            setFillColor(fill)
            contentStream.append(
                [
                    .moveTo(x: first.x, y: first.y),
                ] + points.dropFirst().map { .lineTo(x: $0.x, y: $0.y) } + [
                    .closePath,
                    .fill,
                ],
            )
        } else if let stroke {
            setStrokeColor(stroke)
            contentStream.append(
                [
                    .setLineWidth(lineWidth),
                    .moveTo(x: first.x, y: first.y),
                ] + points.dropFirst().map { .lineTo(x: $0.x, y: $0.y) } + [
                    .closePath,
                    .stroke,
                ],
            )
        }
    }

    func drawCircle(
        x: Double,
        y: Double,
        radius: Double,
        stroke: PDFColor? = .black,
        fill: PDFColor? = nil,
        lineWidth: Double = 0.5,
    ) {
        let kappa = 0.5522847498307936 * radius
        let operators: [PDFContentStream.Operator] = [
            .moveTo(x: x + radius, y: y),
            .curveTo(x1: x + radius, y1: y + kappa, x2: x + kappa, y2: y + radius, x3: x, y3: y + radius),
            .curveTo(x1: x - kappa, y1: y + radius, x2: x - radius, y2: y + kappa, x3: x - radius, y3: y),
            .curveTo(x1: x - radius, y1: y - kappa, x2: x - kappa, y2: y - radius, x3: x, y3: y - radius),
            .curveTo(x1: x + kappa, y1: y - radius, x2: x + radius, y2: y - kappa, x3: x + radius, y3: y),
            .closePath,
        ]
        drawPath(operators: operators, stroke: stroke, fill: fill, lineWidth: lineWidth)
    }

    func drawPieSlice(
        centerX: Double,
        centerY: Double,
        radius: Double,
        startAngle: Double,
        endAngle: Double,
        stroke: PDFColor? = .white,
        fill: PDFColor,
        lineWidth: Double = 0.5,
    ) {
        let sweep = endAngle - startAngle
        if abs(abs(sweep) - Double.pi * 2) < 0.0001 {
            drawCircle(x: centerX, y: centerY, radius: radius, stroke: stroke, fill: fill, lineWidth: lineWidth)
            return
        }

        let start = arcPoint(centerX: centerX, centerY: centerY, radius: radius, angle: startAngle)
        var operators: [PDFContentStream.Operator] = [
            .moveTo(x: centerX, y: centerY),
            .lineTo(x: start.x, y: start.y),
        ]
        operators += arcOperators(centerX: centerX, centerY: centerY, radius: radius, startAngle: startAngle, endAngle: endAngle)
        operators += [
            .lineTo(x: centerX, y: centerY),
            .closePath,
        ]
        drawPath(operators: operators, stroke: stroke, fill: fill, lineWidth: lineWidth)
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

    private func drawPath(
        operators: [PDFContentStream.Operator],
        stroke: PDFColor?,
        fill: PDFColor?,
        lineWidth: Double,
    ) {
        guard !operators.isEmpty else {
            return
        }

        if let fill, let stroke {
            setFillColor(fill)
            setStrokeColor(stroke)
            contentStream.append([.setLineWidth(lineWidth)] + operators + [.fillAndStroke])
        } else if let fill {
            setFillColor(fill)
            contentStream.append(operators + [.fill])
        } else if let stroke {
            setStrokeColor(stroke)
            contentStream.append([.setLineWidth(lineWidth)] + operators + [.stroke])
        }
    }

    private func arcOperators(
        centerX: Double,
        centerY: Double,
        radius: Double,
        startAngle: Double,
        endAngle: Double,
    ) -> [PDFContentStream.Operator] {
        let sweep = endAngle - startAngle
        guard sweep != 0 else {
            return []
        }

        let direction = sweep > 0 ? 1.0 : -1.0
        let segmentCount = max(1, Int(ceil(abs(sweep) / (Double.pi / 2))))
        let segmentSweep = sweep / Double(segmentCount)
        var angle = startAngle
        var operators: [PDFContentStream.Operator] = []

        for _ in 0 ..< segmentCount {
            let nextAngle = angle + segmentSweep
            let k = 4.0 / 3.0 * tan(abs(segmentSweep) / 4.0) * radius * direction
            let start = arcPoint(centerX: centerX, centerY: centerY, radius: radius, angle: angle)
            let end = arcPoint(centerX: centerX, centerY: centerY, radius: radius, angle: nextAngle)
            let control1 = Point(x: start.x - sin(angle) * k, y: start.y + cos(angle) * k)
            let control2 = Point(x: end.x + sin(nextAngle) * k, y: end.y - cos(nextAngle) * k)
            operators.append(.curveTo(
                x1: control1.x,
                y1: control1.y,
                x2: control2.x,
                y2: control2.y,
                x3: end.x,
                y3: end.y,
            ))
            angle = nextAngle
        }

        return operators
    }

    private func arcPoint(centerX: Double, centerY: Double, radius: Double, angle: Double) -> Point {
        Point(
            x: centerX + cos(angle) * radius,
            y: centerY + sin(angle) * radius,
        )
    }

    private func drawDecorations(
        for run: PDFTextRun,
        x: Double,
        y: Double,
        width: Double,
    ) {
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
}
