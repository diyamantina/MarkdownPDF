import Foundation
@testable import MarkdownPDF
import Testing

@Suite("PDF document structure")
struct PDFDocumentStructureTests {
    @Test("Serializes catalog dictionary")
    func serializesCatalogDictionary() {
        let catalog = PDFDocumentCatalog(
            pages: PDFSyntax.Reference(objectNumber: 2),
            displayDocumentTitle: true,
        )

        #expect(
            catalog.pdfDictionary.serialized()
                == "<< /Type /Catalog /Pages 2 0 R /ViewerPreferences << /DisplayDocTitle true >> >>",
        )
    }

    @Test("Serializes flat page tree")
    func serializesFlatPageTree() {
        let pageTree = PDFDocumentPageTree(kids: [
            PDFSyntax.Reference(objectNumber: 5),
            PDFSyntax.Reference(objectNumber: 6),
        ])

        #expect(pageTree.pdfDictionary.serialized() == "<< /Type /Pages /Kids [5 0 R 6 0 R] /Count 2 >>")
    }

    @Test("Serializes page dictionary with canonical keys")
    func serializesPageDictionaryWithCanonicalKeys() {
        let page = PDFPageDictionary(
            parent: PDFSyntax.Reference(objectNumber: 2),
            mediaBox: PDFOptions.PageSize(width: 300, height: 400),
            resources: PDFSyntax.Dictionary([
                .init(
                    "Font",
                    .pdfDictionary([
                        .init("F1", .reference(PDFSyntax.Reference(objectNumber: 3))),
                    ]),
                ),
            ]),
            contents: PDFSyntax.Reference(objectNumber: 4),
            annotations: [PDFSyntax.Reference(objectNumber: 5)],
        )

        #expect(
            page.pdfDictionary.serialized(style: .multiline)
                == """
                << /Type /Page
                /Parent 2 0 R
                /MediaBox [0 0 300 400]
                /Resources << /Font << /F1 3 0 R >> >>
                /Contents 4 0 R
                /Annots [5 0 R] >>
                """,
        )
    }

    @Test("Omits empty annotation array")
    func omitsEmptyAnnotationArray() {
        let page = PDFPageDictionary(
            parent: PDFSyntax.Reference(objectNumber: 2),
            mediaBox: PDFOptions.PageSize(width: 300, height: 400),
            resources: PDFSyntax.Dictionary(),
            contents: PDFSyntax.Reference(objectNumber: 4),
            annotations: [],
        )

        #expect(!page.pdfDictionary.serialized(style: .multiline).contains("/Annots"))
    }

    @Test("Serializes page resources from typed entries")
    func serializesPageResourcesFromTypedEntries() {
        let resources = PDFPageResources(
            fonts: [
                PDFPageResources.Entry(name: "F2", objectRef: PDFSyntax.Reference(objectNumber: 3)),
            ],
            imageXObjects: [
                PDFXObjectResource(name: "Im1", objectRef: PDFSyntax.Reference(objectNumber: 4), kind: .image),
            ],
            formXObjects: [
                PDFXObjectResource(name: "Fm1", objectRef: PDFSyntax.Reference(objectNumber: 5), kind: .form),
            ],
            extGStates: [
                PDFPageResources.Entry(name: "GS1", objectRef: PDFSyntax.Reference(objectNumber: 6)),
            ],
            patterns: [
                PDFPageResources.Entry(name: "P1", objectRef: PDFSyntax.Reference(objectNumber: 7)),
            ],
        )

        #expect(
            resources.pdfDictionary.serialized()
                == "<< /ExtGState << /GS1 6 0 R >> /Font << /F2 3 0 R >> /XObject << /Im1 4 0 R /Fm1 5 0 R >> /Pattern << /P1 7 0 R >> >>",
        )
    }

    @Test("Omits unused resource namespaces")
    func omitsUnusedResourceNamespaces() {
        let resources = PDFPageResources(
            fonts: [
                PDFPageResources.Entry(name: "F1", objectRef: PDFSyntax.Reference(objectNumber: 3)),
            ],
        )

        #expect(resources.pdfDictionary.serialized() == "<< /Font << /F1 3 0 R >> >>")
    }

    @Test("Serializes image XObject dictionary from typed model")
    func serializesImageXObjectDictionaryFromTypedModel() {
        let image = PDFImageXObject(
            resourceName: "Im1",
            width: 24,
            height: 12,
            colorSpace: PDFSyntax.Name("DeviceRGB"),
            bitsPerComponent: 8,
            filter: PDFSyntax.Name("DCTDecode"),
            data: Data([0xFF, 0xD8, 0xFF, 0xD9]),
        )

        #expect(image.resourceName == "Im1")
        #expect(
            image.pdfDictionary.serialized()
                == "<< /Type /XObject /Subtype /Image /Width 24 /Height 12 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode >>",
        )
        #expect(image.pdfStream.serialized.contains(Data("/Length 4".utf8)))
    }

    @Test("Preserves PNG decode parameters in typed image XObject")
    func preservesPNGDecodeParametersInTypedImageXObject() {
        let image = PDFImageXObject(
            resourceName: "Im2",
            width: 10,
            height: 20,
            colorSpace: PDFSyntax.Name("DeviceGray"),
            bitsPerComponent: 8,
            filter: PDFSyntax.Name("FlateDecode"),
            decodeParms: PDFSyntax.Dictionary([
                .init("Predictor", .int(15)),
                .init("Colors", .int(1)),
                .init("BitsPerComponent", .int(8)),
                .init("Columns", .int(10)),
            ]),
            data: Data([0x00]),
        )

        #expect(
            image.pdfDictionary.serialized()
                ==
                "<< /Type /XObject /Subtype /Image /Width 10 /Height 20 /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode /DecodeParms << /Predictor 15 /Colors 1 /BitsPerComponent 8 /Columns 10 >> >>",
        )
    }

    @Test("XObject resource keeps kind for image and future form objects")
    func xObjectResourceKeepsKindForImageAndFutureFormObjects() {
        let imageResource = PDFXObjectResource(
            name: "Im1",
            objectRef: PDFSyntax.Reference(objectNumber: 4),
            kind: .image,
        )
        let formResource = PDFXObjectResource(
            name: "Fm1",
            objectRef: PDFSyntax.Reference(objectNumber: 5),
            kind: .form,
        )
        let resources = PDFPageResources(
            imageXObjects: [imageResource],
            formXObjects: [formResource],
        )

        #expect(imageResource.kind == .image)
        #expect(formResource.kind == .form)
        #expect(resources.pdfDictionary.serialized() == "<< /XObject << /Im1 4 0 R /Fm1 5 0 R >> >>")
    }

    @Test("Serializes typed text content stream operators")
    func serializesTypedTextContentStreamOperators() {
        var stream = PDFContentStream()

        stream.append([
            .beginText,
            .setFont(PDFSyntax.Name("F1"), size: 12),
            .moveText(x: 20, y: 30),
            .showText(PDFSyntax.LiteralString(#"Text (with slash \)"#)),
            .endText,
        ])

        #expect(stream.serialized == #"BT /F1 12 Tf 20 30 Td (Text \(with slash \\\)) Tj ET"# + "\n")
    }

    @Test("Serializes typed graphics content stream operators")
    func serializesTypedGraphicsContentStreamOperators() {
        var stream = PDFContentStream()

        stream.append(.setFillColor(PDFColor(red: 0.05, green: 0.24, blue: 0.62)))
        stream.append([
            .setStrokeColor(PDFColor(red: 0.35, green: 0.35, blue: 0.35)),
            .setLineWidth(0.5),
            .moveTo(x: 10, y: 12),
            .lineTo(x: 40, y: 12),
            .stroke,
        ])
        stream.append([
            .rectangle(x: 20, y: 24, width: 80, height: 30),
            .fill,
        ])
        stream.append([
            .saveGraphicsState,
            .concatenateMatrix(a: 40, b: 0, c: 0, d: 30, e: 20, f: 10),
            .drawXObject(PDFSyntax.Name("Im1")),
            .restoreGraphicsState,
        ])

        #expect(
            stream.serialized
                == """
                0.050 0.240 0.620 rg
                0.350 0.350 0.350 RG 0.500 w 10 12 m 40 12 l S
                20 24 80 30 re f
                q 40 0 0 30 20 10 cm /Im1 Do Q

                """,
        )
    }

    @Test("Serializes PDF base font object without descriptor or embedded font file")
    func serializesPDFBaseFontObjectWithoutDescriptorOrEmbeddedFontFile() {
        let font = PDFFontObject(font: .helvetica, fontSet: .pdfBase)
        let dictionary = font.pdfDictionary(fontDescriptor: nil).serialized()

        #expect(font.resourceName == "F1")
        #expect(font.fontDescriptor == nil)
        #expect(font.metrics == nil)
        #expect(dictionary == "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        #expect(!dictionary.contains("/FontDescriptor"))
        #expect(!dictionary.contains("/FontFile"))
        #expect(!dictionary.contains("/ToUnicode"))
    }

    @Test("Serializes unembedded TrueType font object from typed metrics and descriptor")
    func serializesUnembeddedTrueTypeFontObjectFromTypedMetricsAndDescriptor() throws {
        let font = PDFFontObject(font: .helveticaBold, fontSet: .appleSystem)
        let descriptor = try #require(font.fontDescriptor)
        let descriptorText = descriptor.pdfDictionary.serialized()
        let fontText = font.pdfDictionary(
            fontDescriptor: PDFSyntax.Reference(objectNumber: 8),
        ).serialized()

        #expect(font.resourceName == "F2")
        #expect(font.metrics?.firstCharacter == 32)
        #expect(font.metrics?.lastCharacter == 126)
        #expect(descriptorText.contains("/Type /FontDescriptor"))
        #expect(descriptorText.contains("/FontName /SFProText-Bold"))
        #expect(!descriptorText.contains("/FontFile"))
        #expect(fontText.contains("/Subtype /TrueType"))
        #expect(fontText.contains("/BaseFont /SFProText-Bold"))
        #expect(fontText.contains("/FirstChar 32 /LastChar 126"))
        #expect(fontText.contains("/Widths [278 333 474 556"))
        #expect(fontText.contains("/FontDescriptor 8 0 R"))
        #expect(!fontText.contains("/FontFile"))
    }

    @Test("Renderer font model keeps custom non-Type1 font sets on simple TrueType output")
    func rendererFontModelKeepsCustomNonType1FontSetsOnSimpleTrueTypeOutput() {
        let customCompositeNameSet = PDFOptions.FontSet(
            regular: "Portable-Regular",
            bold: "Portable-Bold",
            italic: "Portable-Italic",
            monospaced: "Portable-Mono",
            subtype: "Type0",
        )
        let font = PDFFontObject(font: .helvetica, fontSet: customCompositeNameSet)

        #expect(font.subtype == "TrueType")
        #expect(font.fontDescriptor != nil)
        #expect(font.metrics != nil)
        #expect(font.descendantFonts.isEmpty)
        #expect(font.toUnicodeMap == nil)
    }

    @Test("Font descriptor keeps embedded font file reference as explicit future hook")
    func fontDescriptorKeepsEmbeddedFontFileReferenceAsExplicitFutureHook() {
        let descriptor = PDFFontDescriptor(
            fontName: "PortableTrueType",
            italicAngle: 0,
            embeddedFontFile: .trueType(PDFSyntax.Reference(objectNumber: 9)),
        )

        #expect(descriptor.pdfDictionary.serialized().contains("/FontFile2 9 0 R"))
    }

    @Test("Font object keeps composite font references as explicit future hooks")
    func fontObjectKeepsCompositeFontReferencesAsExplicitFutureHooks() {
        let font = PDFFontObject(
            resourceName: "F9",
            baseName: "PortableCIDFont",
            subtype: "Type0",
            encoding: "Identity-H",
            descendantFonts: [PDFSyntax.Reference(objectNumber: 10)],
            toUnicodeMap: PDFSyntax.Reference(objectNumber: 11),
        )

        let dictionary = font.pdfDictionary(fontDescriptor: nil).serialized()

        #expect(dictionary.contains("/Subtype /Type0"))
        #expect(dictionary.contains("/Encoding /Identity-H"))
        #expect(dictionary.contains("/DescendantFonts [10 0 R]"))
        #expect(dictionary.contains("/ToUnicode 11 0 R"))
    }

    @Test("Draw commands populate typed page resource usage")
    func drawCommandsPopulateTypedPageResourceUsage() {
        let canvas = PDFPageCanvas()

        canvas.drawTextRun(
            PDFTextRun(text: "Heading", font: .helveticaBold, size: 12),
            x: 20,
            y: 100,
            fontSet: .pdfBase,
        )
        canvas.drawImage(name: "Im1", x: 20, y: 20, width: 40, height: 30)

        #expect(canvas.resourceUsage.usedFonts == [.helveticaBold])
        #expect(canvas.resourceUsage.usedImageXObjectNames == ["Im1"])
        #expect(canvas.commands.contains("/F2 12 Tf"))
        #expect(canvas.commands.contains("/Im1 Do"))
    }

    @Test("Renderer keeps deterministic document spine object order")
    func rendererKeepsDeterministicDocumentSpineObjectOrder() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Hello from MarkdownPDF.")
        let objects = PDFInspector(data).indirectObjects

        #expect(objects.map(\.number) == [1, 2, 3, 4, 5])
        let catalog = try #require(objects.first { $0.number == 1 })
        let pages = try #require(objects.first { $0.number == 2 })
        let font = try #require(objects.first { $0.number == 3 })
        let content = try #require(objects.first { $0.number == 4 })
        let page = try #require(objects.first { $0.number == 5 })

        #expect(catalog.content == "<< /Type /Catalog /Pages 2 0 R >>")
        #expect(pages.content == "<< /Type /Pages /Kids [5 0 R] /Count 1 >>")
        #expect(font.content.contains("/Type /Font"))
        #expect(content.isStream)
        #expect(page.content.contains("<< /Type /Page\n"))
    }

    @Test("Renderer keeps deterministic font resource order")
    func rendererKeepsDeterministicFontResourceOrder() throws {
        let data = try MarkdownPDFRenderer().render(markdown: "Regular **Bold** *Italic* `code`")
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("/Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R /F4 6 0 R >>"))
    }
}
