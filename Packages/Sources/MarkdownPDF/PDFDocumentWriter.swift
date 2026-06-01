import Foundation

struct PDFDocumentWriter {
    var pageSize: PDFOptions.PageSize
    var fontSet: PDFOptions.FontSet
    var pages: [PDFPageCanvas]
    var images: [PDFImage]
    var title: String?

    func data() -> Data {
        var builder = Builder()
        let catalogRef = builder.reserve()
        let pagesRef = builder.reserve()

        let usedFonts = StandardFont.allCases.filter { font in
            pages.contains { $0.usedFonts.contains(font) }
        }
        let fontResources = Dictionary(uniqueKeysWithValues: usedFonts.map { font in
            (
                font,
                PageResources.Entry(name: font.rawValue, objectRef: builder.addFont(font, fontSet: fontSet))
            )
        })

        let usedImageNames = Set(pages.flatMap(\.usedImageNames))
        let imageResources = Dictionary(uniqueKeysWithValues: images.filter { usedImageNames.contains($0.name) }.map { image in
            (
                image.name,
                PageResources.Entry(name: image.name, objectRef: builder.addImage(image))
            )
        })

        func resources(for page: PDFPageCanvas) -> PageResources {
            let pageFonts = StandardFont.allCases.compactMap { font in
                page.usedFonts.contains(font) ? fontResources[font] : nil
            }
            let pageXObjects = images.compactMap { image in
                page.usedImageNames.contains(image.name) ? imageResources[image.name] : nil
            }
            return PageResources(fonts: pageFonts, xObjects: pageXObjects)
        }

        var pageRefs: [PDFSyntax.Reference] = []
        for page in pages {
            let contentData = Data(page.commands.utf8)
            let contentRef = builder.addStream(dictionary: PDFSyntax.Dictionary(), data: contentData)
            let annotationRefs = page.linkAnnotations.map { builder.addLinkAnnotation($0) }

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

        builder.set(
            pagesRef,
            .dictionary(PDFDocumentPageTree(kids: pageRefs).pdfDictionary),
        )
        builder.set(
            catalogRef,
            .dictionary(
                PDFDocumentCatalog(
                    pages: pagesRef,
                    displayDocumentTitle: title?.isEmpty == false,
                ).pdfDictionary,
            ),
        )

        return builder.build(root: catalogRef)
    }

    private struct PageResources {
        var fonts: [Entry]
        var xObjects: [Entry]

        var pdfDictionary: PDFSyntax.Dictionary {
            var entries: [PDFSyntax.Dictionary.Entry] = []
            if !fonts.isEmpty {
                entries.append(
                    .init(
                        "Font",
                        .dictionary(PDFSyntax.Dictionary(fonts.map(\.pdfEntry))),
                    ),
                )
            }
            if !xObjects.isEmpty {
                entries.append(
                    .init(
                        "XObject",
                        .dictionary(PDFSyntax.Dictionary(xObjects.map(\.pdfEntry))),
                    ),
                )
            }
            return PDFSyntax.Dictionary(entries)
        }

        struct Entry {
            var name: String
            var objectRef: PDFSyntax.Reference

            var pdfEntry: PDFSyntax.Dictionary.Entry {
                .init(name, .reference(objectRef))
            }
        }
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

        mutating func addFont(
            _ font: StandardFont,
            fontSet: PDFOptions.FontSet,
        ) -> PDFSyntax.Reference {
            let baseName = font.baseName(in: fontSet)
            if font.subtype(in: fontSet) == "Type1" {
                return addDictionary(PDFSyntax.Dictionary([
                    .init("Type", .pdfName("Font")),
                    .init("Subtype", .pdfName("Type1")),
                    .init("BaseFont", .pdfName(baseName)),
                    .init("Encoding", .pdfName("WinAnsiEncoding")),
                ]))
            }

            let descriptorRef = addDictionary(PDFSyntax.Dictionary([
                .init("Type", .pdfName("FontDescriptor")),
                .init("FontName", .pdfName(baseName)),
                .init("Flags", .int(32)),
                .init(
                    "FontBBox",
                    .pdfArray([
                        .int(-200),
                        .int(-250),
                        .int(1200),
                        .int(1000),
                    ]),
                ),
                .init("ItalicAngle", .int(font.italicAngle)),
                .init("Ascent", .int(900)),
                .init("Descent", .int(-220)),
                .init("CapHeight", .int(700)),
                .init("StemV", .int(80)),
            ]))
            return addDictionary(PDFSyntax.Dictionary([
                .init("Type", .pdfName("Font")),
                .init("Subtype", .pdfName("TrueType")),
                .init("BaseFont", .pdfName(baseName)),
                .init("Encoding", .pdfName("WinAnsiEncoding")),
                .init("FirstChar", .int(32)),
                .init("LastChar", .int(126)),
                .init("Widths", .pdfArray(font.widthsForPDF(in: fontSet).map { .int($0) })),
                .init("FontDescriptor", .reference(descriptorRef)),
            ]))
        }

        mutating func addStream(dictionary: PDFSyntax.Dictionary, data: Data) -> PDFSyntax.Reference {
            addData(PDFSyntax.Stream(dictionary: dictionary, data: data).serialized)
        }

        mutating func addImage(_ image: PDFImage) -> PDFSyntax.Reference {
            var entries: [PDFSyntax.Dictionary.Entry] = [
                .init("Type", .pdfName("XObject")),
                .init("Subtype", .pdfName("Image")),
                .init("Width", .int(image.width)),
                .init("Height", .int(image.height)),
                .init("ColorSpace", .name(image.colorSpace)),
                .init("BitsPerComponent", .int(image.bitsPerComponent)),
                .init("Filter", .name(image.filter)),
            ]
            if let decodeParms = image.decodeParms {
                entries.append(.init("DecodeParms", .dictionary(decodeParms)))
            }

            return addStream(dictionary: PDFSyntax.Dictionary(entries), data: image.data)
        }

        mutating func addLinkAnnotation(_ annotation: PDFLinkAnnotation) -> PDFSyntax.Reference {
            let minX = annotation.x
            let minY = annotation.y
            let maxX = annotation.x + annotation.width
            let maxY = annotation.y + annotation.height
            return addDictionary(
                PDFSyntax.Dictionary([
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
                    .init(
                        "A",
                        .pdfDictionary([
                            .init("S", .pdfName("URI")),
                            .init("URI", .pdfString(annotation.destination.pdfURI)),
                        ]),
                    ),
                ]),
                style: .multiline,
            )
        }

        func build(root: PDFSyntax.Reference) -> Data {
            registry.serializedFile(root: root)
        }

        private mutating func addData(_ data: Data) -> PDFSyntax.Reference {
            registry.add(data)
        }
    }
}

private extension String {
    var pdfURI: String {
        if contains("://") || hasPrefix("mailto:") || hasPrefix("#") || hasPrefix("/") || hasPrefix(".") {
            return self
        }

        if contains("@"), !contains("/") {
            return "mailto:\(self)"
        }

        return self
    }
}
