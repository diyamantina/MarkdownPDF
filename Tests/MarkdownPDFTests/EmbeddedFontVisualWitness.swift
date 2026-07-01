import Foundation
@testable import MarkdownPDF
import Testing

/// Full visual witness battery for embedded-font renders.
///
/// Extraction (`pdftotext`) and MuPDF structured text read the font program and
/// ToUnicode map directly, so they are blind to a wrong CID `/W` width array. A
/// real viewer advances glyphs from `/W`, which is what garbles text when the
/// widths are wrong (see #194). This helper therefore never relies on a single
/// tool: it runs `qpdf`, `pdftotext`, the Poppler `pdftotext -tsv` word-box
/// geometry, the MuPDF character quads, and a Poppler-vs-MuPDF raster
/// comparison, so the width class of bug fails the build (see #195).
func assertEmbeddedFontVisualWitness(
    _ data: Data,
    name: String,
    expectedSubstrings: [String],
    minWords: Int = 1,
) throws {
    let url = try PDFValidation.temporaryPDF(name: name, data: data)
    try PDFValidation.writeArtifact(data, name: "\(name).pdf")
    let pageCount = PDFInspector(data).pageCount
    try #require(pageCount >= 1, "\(name): rendered no pages")

    // 1. Structural validity.
    let qpdf = try PDFValidation.qpdfCheck(url: url)
    try #require(qpdf.exitCode == 0, "qpdf --check failed for \(name):\n\(qpdf.output)")

    // 2. Content extraction.
    let textResult = try PDFValidation.pdftotext(url: url)
    try #require(textResult.exitCode == 0, "pdftotext failed for \(name):\n\(textResult.output)")
    try PDFValidation.writeTextArtifact(textResult.output, name: "\(name)/text.txt")
    let extracted = textResult.output.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    for substring in expectedSubstrings {
        #expect(
            extracted.contains(substring),
            "\(name): expected extracted text to contain \"\(substring)\":\n\(textResult.output)",
        )
    }

    // 3. Poppler word-box geometry. Viewers advance glyphs from the CID `/W`
    //    array, so a wrong width shows here as same-line word overlap or words
    //    outside the page bounds (text falling out of tables). This is the
    //    check that catches #194.
    let tsvResult = try PDFValidation.pdftotextTSV(url: url)
    try #require(tsvResult.exitCode == 0, "pdftotext -tsv failed for \(name):\n\(tsvResult.output)")
    try PDFValidation.writeTextArtifact(tsvResult.output, name: "\(name)/poppler.tsv")
    let layout = try PopplerTextLayout(tsv: tsvResult.output)
    let layoutIssues = layout.visualLayoutIssues()
    #expect(
        layout.words.count >= minWords,
        "\(name): expected at least \(minWords) Poppler words, got \(layout.words.count)",
    )
    #expect(
        layoutIssues.isEmpty,
        "\(name): Poppler word-box layout issues:\n\(layoutIssues.joined(separator: "\n"))",
    )

    // 4. MuPDF character quads: independent same-line glyph overlap / size check.
    let stext = try PDFValidation.mutoolStructuredText(url: url)
    try #require(stext.exitCode == 0, "mutool structured text failed for \(name):\n\(stext.output)")
    try PDFValidation.writeTextArtifact(stext.output, name: "\(name)/mupdf-stext.xml")
    let structuredText = try MuPDFStructuredText(xml: stext.output)
    let quadIssues = structuredText.characterQuadIssues()
    #expect(
        quadIssues.isEmpty,
        "\(name): MuPDF character quad issues:\n\(quadIssues.joined(separator: "\n"))",
    )

    // 5. Cross-renderer raster. A wrong `/W` array makes Poppler spread glyphs
    //    while MuPDF (reading the font program) does not, so their ink bounds
    //    diverge. Agreement here is the final guard.
    let poppler = try PDFValidation.pdftoppmPNMs(url: url, pageCount: pageCount)
    let mupdf = try PDFValidation.mutoolPNMs(url: url, pageCount: pageCount)
    try #require(poppler.result.exitCode == 0, "pdftoppm PNM failed for \(name):\n\(poppler.result.output)")
    try #require(mupdf.result.exitCode == 0, "mutool PNM failed for \(name):\n\(mupdf.result.output)")
    var rasterIssues: [String] = []
    for page in 1 ... pageCount {
        let popplerImage = try PNMImage(data: Data(contentsOf: poppler.pnmURLs[page - 1]))
        let mupdfImage = try PNMImage(data: Data(contentsOf: mupdf.pnmURLs[page - 1]))
        rasterIssues += embeddedFontRasterIssues(poppler: popplerImage, mupdf: mupdfImage)
            .map { "page \(page): \($0)" }
    }
    #expect(
        rasterIssues.isEmpty,
        "\(name): Poppler and MuPDF raster output diverged:\n\(rasterIssues.joined(separator: "\n"))",
    )
}

/// Shared raster comparison for both the embedded-font witness above and the
/// `PDFVisualLayoutValidationTests` suite. Reports dimension mismatches,
/// under-rendered (near-blank) pages, fully blank pages, and diverging ink
/// bounds. A near-blank page is the failure mode of a badly scaled font, so the
/// `nonWhitePixelCount` floor must stay here.
func embeddedFontRasterIssues(poppler: PNMImage, mupdf: PNMImage) -> [String] {
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

    guard let popplerBox = popplerInk.box, let mupdfBox = mupdfInk.box else {
        issues.append("one renderer produced a blank page")
        return issues
    }

    let overlap = inkOverlapRatio(popplerBox, mupdfBox)
    if overlap < 0.85 {
        issues.append("ink bounds differ: Poppler \(popplerBox), MuPDF \(mupdfBox)")
    }

    return issues
}

func inkOverlapRatio(_ left: PNMImage.InkBox, _ right: PNMImage.InkBox) -> Double {
    let intersectionLeft = max(left.left, right.left)
    let intersectionTop = max(left.top, right.top)
    let intersectionRight = min(left.right, right.right)
    let intersectionBottom = min(left.bottom, right.bottom)
    guard intersectionLeft <= intersectionRight, intersectionTop <= intersectionBottom else {
        return 0
    }

    let intersectionArea = (intersectionRight - intersectionLeft + 1) * (intersectionBottom - intersectionTop + 1)
    let smallerArea = min(left.width * left.height, right.width * right.height)
    return Double(intersectionArea) / Double(smallerArea)
}
