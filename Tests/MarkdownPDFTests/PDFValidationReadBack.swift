import Foundation
@testable import MarkdownPDF
import Testing

/// Checks of a rendered PDF made with the package's own reader, `PDFDocumentReader`,
/// and the byte inspector of this test target. No program outside the package
/// takes part. The tests move onto these one group at a time; when none calls the
/// outside tools any more, the wrappers in `PDFValidation.swift` go and this file
/// is folded into it.
extension PDFValidation {
    // MARK: Structure

    /// Everything wrong with the structure of `data`, or nothing when it is sound.
    ///
    /// Two implementations that share no code look at the file. The reader's
    /// structure check reads every object the cross-reference table lists, follows
    /// every reference, decodes every stream it can, walks the page tree and reads
    /// the whole document. The byte inspector of this test target checks the
    /// cross-reference offsets and the stream lengths against the raw bytes.
    /// A `name` is put before each issue.
    static func structureIssues(_ data: some DataProtocol, name: String = "") -> [String] {
        let data = Data(data)
        let prefix = name.isEmpty ? "" : "\(name): "
        var issues = PDFDocumentReader.structureIssues(in: data).map { prefix + $0.description }
        let inspector = PDFInspector(data)
        if !inspector.hasValidXrefOffsets() {
            issues.append("\(prefix)inspector: the cross-reference table has offsets that do not point to matching objects")
        }
        if !inspector.streamLengthsMatch() {
            issues.append("\(prefix)inspector: one or more stream lengths do not match the emitted bytes")
        }
        return issues
    }

    /// Records an issue, at the caller, when the structure of `data` is not sound.
    static func expectSoundStructure(
        _ data: some DataProtocol,
        name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) {
        let issues = structureIssues(data, name: name)
        #expect(
            issues.isEmpty,
            "the PDF structure is not sound:\n\(issues.joined(separator: "\n"))",
            sourceLocation: sourceLocation,
        )
    }

    /// Stops the test, at the caller, when the structure of `data` is not sound.
    static func requireSoundStructure(
        _ data: some DataProtocol,
        name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) throws {
        let issues = structureIssues(data, name: name)
        try #require(
            issues.isEmpty,
            "the PDF structure is not sound:\n\(issues.joined(separator: "\n"))",
            sourceLocation: sourceLocation,
        )
    }

    // MARK: Text and pages

    /// The text of the document, pages separated by a form feed, lines by a line
    /// feed. With `artifact`, the text is also written as the artifact `<artifact>.txt`.
    static func text(_ data: some DataProtocol, artifact: String? = nil) throws -> String {
        let text = try PDFDocumentReader(data: Data(data)).text
        if let artifact {
            try writeTextArtifact(text, name: "\(artifact).txt")
        }
        return text
    }

    /// The text of each page.
    static func pageTexts(_ data: some DataProtocol) throws -> [String] {
        try PDFDocumentReader(data: Data(data)).pages.map(\.text)
    }

    /// Whether the document has pages and each is A4: 595.28 by 841.89 points,
    /// to the two decimals the file gives.
    static func pagesAreA4(_ document: PDFDocumentReader) -> Bool {
        !document.pages.isEmpty && document.pages.allSatisfy { page in
            abs(page.size.width - 595.28) < 0.005 && abs(page.size.height - 841.89) < 0.005
        }
    }

    /// Records an issue, at the caller, unless the first page has a size and shows
    /// text inside it. This is what can be said from the file about a page that
    /// used to be handed to an outside rasterizer to see that it draws at all.
    static func expectFirstPageHasContent(
        _ document: PDFDocumentReader,
        name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) {
        guard let page = document.pages.first else {
            Issue.record("\(name): the document has no page", sourceLocation: sourceLocation)
            return
        }
        #expect(page.size.width > 0 && page.size.height > 0, "\(name): the first page has no size", sourceLocation: sourceLocation)
        let inside = page.words.filter { word in
            word.width > 0 && word.x >= 0 && word.x + word.width <= page.size.width && word.y >= 0 && word.y <= page.size.height
        }
        #expect(!inside.isEmpty, "\(name): the first page shows no text inside its bounds", sourceLocation: sourceLocation)
    }

    // MARK: Conformance

    /// A conformance profile a document can declare.
    enum Profile: String {
        case pdfA2A = "PDF/A-2a"
        case pdfUA1 = "PDF/UA-1"
    }

    /// What a file that claims `profile` must hold and does not, as far as the
    /// reader can tell exactly from the file: the identifier in the XMP metadata,
    /// and the parts of the profile that are plain facts about the file (the
    /// output intent with its profile, every font embedded, the tagged flag and a
    /// structure tree under one Document element, a title a viewer is asked to
    /// show, a language, a description on every figure).
    ///
    /// This is not a conformance run. It cannot say a file conforms; it says which
    /// of the listed facts is missing. The full runs are tracked in
    /// `Docs/NOT-VERIFIED.md`.
    static func conformancePrerequisiteIssues(_ data: some DataProtocol, profile: Profile) throws -> [String] {
        let document = try PDFDocumentReader(data: Data(data))
        var issues: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition {
                issues.append("\(profile.rawValue): \(message)")
            }
        }
        let unembedded = document.fonts.filter { !$0.isEmbedded }.map(\.name)
        check(unembedded.isEmpty, "fonts not embedded: \(unembedded.joined(separator: ", "))")
        check(document.isTagged, "the catalog does not mark the document as tagged")
        check(document.structure.map(\.type) == ["Document"], "the structure tree is not one Document element")
        let elements = document.structure.flatMap(\.flattened)
        check(elements.contains { $0.markedContentCount > 0 }, "no structure element holds page content")
        switch profile {
        case .pdfA2A:
            check(document.pdfAConformance == "2A", "the XMP metadata declares \(document.pdfAConformance ?? "no PDF/A part"), not 2A")
            check(
                document.outputIntents.contains { $0.subtype == "GTS_PDFA1" && $0.profileComponents == 3 && $0.outputConditionIdentifier?.isEmpty == false },
                "no GTS_PDFA1 output intent with an embedded RGB profile",
            )
        case .pdfUA1:
            check(document.pdfUAPart == 1, "the XMP metadata declares \(document.pdfUAPart.map(String.init) ?? "no PDF/UA part"), not 1")
            check(document.title?.isEmpty == false, "the document has no title")
            check(document.displaysDocumentTitle, "the viewer is not asked to show the document title")
            check(document.language?.isEmpty == false, "the document has no language")
            let bareFigures = elements.count(where: { $0.type == "Figure" && ($0.alternateText ?? "").isEmpty })
            check(bareFigures == 0, "\(bareFigures) figures have no alternate description")
        }
        return issues
    }

    /// Records an issue, at the caller, for each prerequisite of each profile the file lacks.
    static func expectConformancePrerequisites(
        _ data: some DataProtocol,
        profiles: [Profile],
        sourceLocation: SourceLocation = #_sourceLocation,
    ) throws {
        for profile in profiles {
            let issues = try conformancePrerequisiteIssues(data, profile: profile)
            #expect(issues.isEmpty, "\(issues.joined(separator: "\n"))", sourceLocation: sourceLocation)
        }
    }

    // MARK: Not verified

    /// Fails a test that was enabled although nothing inside the package can check
    /// what it is about. A test that calls this is listed in `Docs/NOT-VERIFIED.md`
    /// and carries the `.disabled` trait, so it does not run; if the trait is
    /// removed before the capability exists, the test fails here and cannot pass
    /// without checking anything.
    static func notVerified(_ missing: String, sourceLocation: SourceLocation = #_sourceLocation) {
        Issue.record("not verified: \(missing), see Docs/NOT-VERIFIED.md", sourceLocation: sourceLocation)
    }
}
