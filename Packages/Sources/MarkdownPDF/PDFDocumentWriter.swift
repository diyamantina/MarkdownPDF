import Foundation

struct PDFDocumentWriter {
    var pageSize: PDFOptions.PageSize
    var fontSet: PDFOptions.FontSet
    var pages: [PDFPageCanvas]
    var images: [PDFImage]
    var title: String?

    func data() throws -> Data {
        var builder = Builder()
        let catalogRef = builder.reserve()
        let pagesRef = builder.reserve()

        let usedFonts = StandardFont.allCases.filter { font in
            pages.contains { $0.resourceUsage.usesFont(font) }
        }
        let fontResources = Dictionary(uniqueKeysWithValues: usedFonts.map { font in
            let fontObject = PDFFontObject(font: font, fontSet: fontSet)
            return (
                font,
                PDFPageResources.Entry(name: fontObject.resourceName, objectRef: builder.addFont(fontObject)),
            )
        })
        let embeddedFontUsages = try Self.mergedEmbeddedFontUsages(from: pages)
        let embeddedFontResources = try Dictionary(uniqueKeysWithValues: embeddedFontUsages.map { usage in
            try (
                usage.resource.resourceName,
                builder.addEmbeddedFont(usage),
            )
        })

        let usedImageNames = Set(pages.flatMap(\.resourceUsage.usedImageXObjectNames))
        let imageResources = Dictionary(uniqueKeysWithValues: images.filter { usedImageNames.contains($0.name) }.map { image in
            let imageXObject = PDFImageXObject(image: image)
            return (
                imageXObject.resourceName,
                imageXObject.resource(objectRef: builder.addImage(imageXObject)),
            )
        })

        func resources(for page: PDFPageCanvas) -> PDFPageResources {
            let pageFonts = page.resourceUsage.usedFonts.compactMap { font in
                fontResources[font]
            }
            let pageEmbeddedFonts = page.resourceUsage.usedEmbeddedFonts.compactMap { usage in
                embeddedFontResources[usage.resource.resourceName]
            }
            let pageXObjects = images.compactMap { image in
                page.resourceUsage.usesImageXObject(named: image.name) ? imageResources[image.name] : nil
            }
            return PDFPageResources(fonts: pageFonts + pageEmbeddedFonts, imageXObjects: pageXObjects)
        }

        let headingDestinationNames = Set(pages.flatMap { page in
            page.headingDestinations.map(\.name)
        })
        var pageRefs: [PDFSyntax.Reference] = []
        for page in pages {
            let contentData = Data(page.commands.utf8)
            let contentRef = builder.addStream(dictionary: PDFSyntax.Dictionary(), data: contentData)
            let annotationRefs = page.linkAnnotations.map {
                builder.addLinkAnnotation($0, knownDestinations: headingDestinationNames)
            }

            let pageRef = builder.addDictionary(
                PDFPageDictionary(
                    parent: pagesRef,
                    mediaBox: pageSize,
                    resources: resources(for: page).pdfDictionary,
                    contents: contentRef,
                    annotations: annotationRefs,
                ).pdfDictionary,
                style: .multiline,
            )
            pageRefs.append(pageRef)
        }

        let resolvedDestinations = pages.enumerated().flatMap { index, page in
            page.headingDestinations.map { destination in
                PDFNamedDestinations.ResolvedDestination(
                    destination: destination,
                    page: pageRefs[index],
                )
            }
        }
        let outlineRef = builder.addOutline(destinations: resolvedDestinations)
        let names = resolvedDestinations.isEmpty
            ? nil
            : PDFNamedDestinations(destinations: resolvedDestinations).pdfDictionary
        let metadata = PDFDocumentMetadata(title: title)
        let metadataRefs = metadata.isEmpty ? nil : builder.addMetadata(metadata)

        builder.set(
            pagesRef,
            .dictionary(PDFDocumentPageTree(kids: pageRefs).pdfDictionary),
        )
        builder.set(
            catalogRef,
            .dictionary(
                PDFDocumentCatalog(
                    pages: pagesRef,
                    outlines: outlineRef,
                    names: names,
                    metadata: metadataRefs?.xmp,
                    displayDocumentTitle: title?.isEmpty == false,
                ).pdfDictionary,
            ),
        )

        return builder.build(root: catalogRef, info: metadataRefs?.info)
    }

    private static func mergedEmbeddedFontUsages(from pages: [PDFPageCanvas]) throws -> [PDFEmbeddedFontUsage] {
        var usagesByResourceName: [String: PDFEmbeddedFontUsage] = [:]
        for page in pages {
            for usage in page.resourceUsage.usedEmbeddedFonts {
                if var existing = usagesByResourceName[usage.resource.resourceName] {
                    guard existing.resource == usage.resource else {
                        throw PDFEmbeddedFontError.conflictingFontResource(resourceName: usage.resource.resourceName)
                    }
                    existing.append(glyphs: usage.glyphs)
                    usagesByResourceName[usage.resource.resourceName] = existing
                } else {
                    usagesByResourceName[usage.resource.resourceName] = usage
                }
            }
        }
        return usagesByResourceName.keys.sorted().compactMap { usagesByResourceName[$0] }
    }

    private struct Builder {
        private var registry = PDFObjectRegistry()

        mutating func reserve() -> PDFSyntax.Reference {
            registry.reserve()
        }

        mutating func set(_ ref: PDFSyntax.Reference, _ value: PDFSyntax.Value) {
            set(ref, Data(value.serialized.utf8))
        }

        mutating func set(_ ref: PDFSyntax.Reference, _ value: Data) {
            registry.set(ref, body: value)
        }

        mutating func addDictionary(
            _ dictionary: PDFSyntax.Dictionary,
            style: PDFSyntax.Dictionary.Style = .inline,
        ) -> PDFSyntax.Reference {
            addData(Data(dictionary.serialized(style: style).utf8))
        }

        mutating func addFont(_ fontObject: PDFFontObject) -> PDFSyntax.Reference {
            let descriptorRef = fontObject.fontDescriptor.map { descriptor in
                addDictionary(descriptor.pdfDictionary)
            }
            return addDictionary(fontObject.pdfDictionary(fontDescriptor: descriptorRef))
        }

        mutating func addEmbeddedFont(_ usage: PDFEmbeddedFontUsage) throws -> PDFPageResources.Entry {
            let resource = usage.resource
            let fontFileRef = addData(PDFFontFile2Stream(fontProgram: resource.fontProgram).pdfStream.serialized)
            let descriptorRef = addDictionary(embeddedFontDescriptor(resource, fontFile: fontFileRef).pdfDictionary)
            let descendantRef = try addDictionary(
                PDFCIDFontType2Object(
                    baseName: resource.baseName,
                    fontDescriptor: descriptorRef,
                    widths: cidFontWidths(for: usage),
                ).pdfDictionary,
            )
            let toUnicodeRef = try addData(
                PDFToUnicodeCMap(
                    name: "\(resource.baseName)-ToUnicode",
                    textMapping: TrueTypeGlyphMapper.TextMapping(sourceText: "", glyphs: usage.glyphs),
                ).pdfStream.serialized,
            )
            let fontRef = addDictionary(
                PDFType0FontObject(
                    resourceName: resource.resourceName,
                    baseName: resource.baseName,
                    descendantFont: descendantRef,
                    toUnicodeMap: toUnicodeRef,
                ).pdfDictionary,
            )
            return PDFPageResources.Entry(name: resource.resourceName, objectRef: fontRef)
        }

        mutating func addStream(dictionary: PDFSyntax.Dictionary, data: Data) -> PDFSyntax.Reference {
            addData(PDFSyntax.Stream(dictionary: dictionary, data: data).serialized)
        }

        mutating func addImage(_ image: PDFImageXObject) -> PDFSyntax.Reference {
            addData(image.pdfStream.serialized)
        }

        mutating func addMetadata(_ metadata: PDFDocumentMetadata) -> (info: PDFSyntax.Reference, xmp: PDFSyntax.Reference) {
            (
                info: addDictionary(metadata.infoDictionary),
                xmp: addStream(dictionary: metadata.xmpDictionary, data: metadata.xmpData),
            )
        }

        mutating func addOutline(destinations: [PDFNamedDestinations.ResolvedDestination]) -> PDFSyntax.Reference? {
            guard !destinations.isEmpty else {
                return nil
            }

            let root = reserve()
            let itemReferences = destinations.map { _ in reserve() }
            let objects = PDFDocumentOutline(destinations: destinations).outlineObjects(
                root: root,
                itemReferences: itemReferences,
            )
            for object in objects {
                setDictionary(object.dictionary, for: object.reference)
            }

            return root
        }

        mutating func addLinkAnnotation(
            _ annotation: PDFLinkAnnotation,
            knownDestinations: Set<String>,
        ) -> PDFSyntax.Reference {
            let minX = annotation.x
            let minY = annotation.y
            let maxX = annotation.x + annotation.width
            let maxY = annotation.y + annotation.height
            var entries: [PDFSyntax.Dictionary.Entry] = [
                .init("Type", .pdfName("Annot")),
                .init("Subtype", .pdfName("Link")),
                .init(
                    "Rect",
                    .pdfArray([
                        .number(minX),
                        .number(minY),
                        .number(maxX),
                        .number(maxY),
                    ]),
                ),
                .init(
                    "Border",
                    .pdfArray([
                        .int(0),
                        .int(0),
                        .int(0),
                    ]),
                ),
            ]
            switch annotation.target {
            case let .uri(uri):
                entries.append(uriAction(uri))
            case let .destination(destination, fallbackURI):
                if knownDestinations.contains(destination) {
                    entries.append(.init("Dest", .pdfString(destination)))
                } else {
                    entries.append(uriAction(fallbackURI))
                }
            }

            return addDictionary(
                PDFSyntax.Dictionary(entries),
                style: .multiline,
            )
        }

        private func uriAction(_ uri: String) -> PDFSyntax.Dictionary.Entry {
            PDFSyntax.Dictionary.Entry(
                "A",
                .pdfDictionary([
                    .init("S", .pdfName("URI")),
                    .init("URI", .pdfString(uri)),
                ]),
            )
        }

        func build(root: PDFSyntax.Reference, info: PDFSyntax.Reference?) -> Data {
            registry.serializedFile(root: root, info: info)
        }

        private mutating func setDictionary(_ dictionary: PDFSyntax.Dictionary, for ref: PDFSyntax.Reference) {
            set(ref, Data(dictionary.serialized(style: .multiline).utf8))
        }

        private mutating func addData(_ data: Data) -> PDFSyntax.Reference {
            registry.add(data)
        }

        private func embeddedFontDescriptor(
            _ resource: PDFEmbeddedFontResource,
            fontFile: PDFSyntax.Reference,
        ) -> PDFFontDescriptor {
            let metadata = resource.metadata
            let boundingBox = metadata.head.boundingBox
            return PDFFontDescriptor(
                fontName: resource.baseName,
                flags: 32,
                fontBoundingBox: [
                    Int(boundingBox.xMin),
                    Int(boundingBox.yMin),
                    Int(boundingBox.xMax),
                    Int(boundingBox.yMax),
                ],
                italicAngle: Int(metadata.post.italicAngle.rounded()),
                ascent: Int(metadata.hhea.ascender),
                descent: Int(metadata.hhea.descender),
                capHeight: Int(metadata.hhea.ascender),
                stemV: 80,
                embeddedFontFile: .trueType(fontFile),
            )
        }

        private func cidFontWidths(for usage: PDFEmbeddedFontUsage) throws -> PDFCIDFontWidths {
            var widthsByCID: [UInt16: UInt16] = [:]
            for glyph in usage.glyphs {
                if let existing = widthsByCID[glyph.cid] {
                    guard existing == glyph.advanceWidth else {
                        throw PDFEmbeddedFontError.conflictingCIDWidth(
                            cid: glyph.cid,
                            existing: existing,
                            duplicate: glyph.advanceWidth,
                        )
                    }
                } else {
                    widthsByCID[glyph.cid] = glyph.advanceWidth
                }
            }
            guard !widthsByCID.isEmpty else {
                throw PDFEmbeddedFontError.emptyGlyphSet(resourceName: usage.resource.resourceName)
            }
            let segments = widthsByCID.keys.sorted().compactMap { cid -> PDFCIDFontWidths.Segment? in
                guard let width = widthsByCID[cid] else {
                    return nil
                }
                return .array(startCID: Int(cid), widths: [Int(width)])
            }
            return PDFCIDFontWidths(segments: segments)
        }
    }
}
