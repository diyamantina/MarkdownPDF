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

    @Test("Serializes catalog dictionary with navigation entries")
    func serializesCatalogDictionaryWithNavigationEntries() {
        let page = PDFSyntax.Reference(objectNumber: 7)
        let names = PDFNamedDestinations(destinations: [
            PDFNamedDestinations.ResolvedDestination(
                destination: PDFHeadingDestination(
                    name: "intro",
                    title: "Intro",
                    level: 1,
                    x: 54,
                    y: 720,
                ),
                page: page,
            ),
        ]).pdfDictionary
        let catalog = PDFDocumentCatalog(
            pages: PDFSyntax.Reference(objectNumber: 2),
            outlines: PDFSyntax.Reference(objectNumber: 3),
            names: names,
            metadata: PDFSyntax.Reference(objectNumber: 4),
            displayDocumentTitle: true,
        )

        #expect(
            catalog.pdfDictionary.serialized()
                ==
                "<< /Type /Catalog /Pages 2 0 R /Outlines 3 0 R /PageMode /UseOutlines /Names << /Dests << /Names [(intro) [7 0 R /XYZ 54 720 null]] >> >> /Metadata 4 0 R /ViewerPreferences << /DisplayDocTitle true >> >>",
        )
    }

    @Test("Serializes catalog dictionary with output intent")
    func serializesCatalogDictionaryWithOutputIntent() {
        let catalog = PDFDocumentCatalog(
            pages: PDFSyntax.Reference(objectNumber: 2),
            outputIntents: [
                PDFOutputIntent(
                    destinationOutputProfile: PDFSyntax.Reference(objectNumber: 9),
                    outputConditionIdentifier: "sRGB IEC61966-2.1",
                ),
            ],
            displayDocumentTitle: false,
        )

        #expect(
            catalog.pdfDictionary.serialized()
                ==
                "<< /Type /Catalog /Pages 2 0 R /OutputIntents [<< /Type /OutputIntent /S /GTS_PDFA1 /OutputCondition (sRGB IEC61966-2.1) /OutputConditionIdentifier (sRGB IEC61966-2.1) /RegistryName (http://www.color.org) /Info (sRGB IEC61966-2.1) /DestOutputProfile 9 0 R >>] >>",
        )
    }

    @Test("Serializes deterministic metadata dictionaries and XMP")
    func serializesDeterministicMetadataDictionariesAndXMP() {
        let metadata = PDFDocumentMetadata(title: "Article & Report")
        let xmp = String(decoding: metadata.xmpData, as: UTF8.self)

        #expect(!metadata.isEmpty)
        #expect(metadata.infoDictionary.serialized() == "<< /Title (Article & Report) /Producer (MarkdownPDF) >>")
        #expect(metadata.xmpDictionary.serialized() == "<< /Type /Metadata /Subtype /XML >>")
        #expect(xmp.contains("<dc:title>"))
        #expect(xmp.contains("Article &amp; Report"))
        #expect(!xmp.contains("CreationDate"))
    }

    @Test("Serializes PDF UA and PDF A identifiers in XMP")
    func serializesPDFUAAndPDFAIdentifiersInXMP() {
        let metadata = PDFDocumentMetadata(title: "Archive", conformance: .pdfUA1AndPDFA2A)
        let xmp = String(decoding: metadata.xmpData, as: UTF8.self)

        #expect(xmp.contains("xmlns:pdfuaid=\"http://www.aiim.org/pdfua/ns/id/\""))
        #expect(xmp.contains("<pdfuaid:part>1</pdfuaid:part>"))
        #expect(xmp.contains("xmlns:pdfaid=\"http://www.aiim.org/pdfa/ns/id/\""))
        #expect(xmp.contains("<pdfaid:part>2</pdfaid:part>"))
        #expect(xmp.contains("<pdfaid:conformance>A</pdfaid:conformance>"))
    }

    @Test("Serializes trailer file identifier")
    func serializesTrailerFileIdentifier() {
        let identifier = PDFSyntax.HexString(bytes: Array("MarkdownPDF-PDFA".utf8))
        let trailer = PDFSyntax.Trailer(
            size: 2,
            root: PDFSyntax.Reference(objectNumber: 1),
            info: nil,
            fileID: (original: identifier, modified: identifier),
        )

        #expect(
            trailer.serialized
                == "trailer\n<< /Size 2 /Root 1 0 R /ID [<4D61726B646F776E5044462D50444641> <4D61726B646F776E5044462D50444641>] >>",
        )
    }

    @Test("Serializes outline tree from heading destinations")
    func serializesOutlineTreeFromHeadingDestinations() throws {
        let destinations = [
            resolvedDestination(name: "intro", title: "Intro", level: 1, page: 7, y: 720),
            resolvedDestination(name: "details", title: "Details", level: 2, page: 7, y: 680),
            resolvedDestination(name: "appendix", title: "Appendix", level: 1, page: 8, y: 720),
        ]
        let objects = PDFDocumentOutline(destinations: destinations).outlineObjects(
            root: PDFSyntax.Reference(objectNumber: 10),
            itemReferences: [
                PDFSyntax.Reference(objectNumber: 11),
                PDFSyntax.Reference(objectNumber: 12),
                PDFSyntax.Reference(objectNumber: 13),
            ],
        )

        let root = try #require(objects.first { $0.reference.objectNumber == 10 })
        let intro = try #require(objects.first { $0.reference.objectNumber == 11 })
        let details = try #require(objects.first { $0.reference.objectNumber == 12 })
        let appendix = try #require(objects.first { $0.reference.objectNumber == 13 })

        #expect(root.dictionary.serialized().contains("/Count 3"))
        #expect(root.dictionary.serialized().contains("/First 11 0 R"))
        #expect(root.dictionary.serialized().contains("/Last 13 0 R"))
        #expect(intro.dictionary.serialized().contains("/Next 13 0 R"))
        #expect(intro.dictionary.serialized().contains("/First 12 0 R"))
        #expect(intro.dictionary.serialized().contains("/Count 1"))
        #expect(details.dictionary.serialized().contains("/Parent 11 0 R"))
        #expect(appendix.dictionary.serialized().contains("/Prev 11 0 R"))
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

    @Test("Serializes two-byte CID text content stream operators")
    func serializesTwoByteCIDTextContentStreamOperators() {
        var stream = PDFContentStream()

        stream.append([
            .beginText,
            .setFont(PDFSyntax.Name("EF1"), size: 14),
            .moveText(x: 40, y: 90),
            .showCIDText([1, 2, 255, 4096]),
            .endText,
        ])

        #expect(stream.serialized == "BT /EF1 14 Tf 40 90 Td <0001000200FF1000> Tj ET\n")
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

        #expect(
            descriptor.pdfDictionary.serialized()
                ==
                "<< /Type /FontDescriptor /FontName /PortableTrueType /Flags 32 /FontBBox [-200 -250 1200 1000] /ItalicAngle 0 /Ascent 900 /Descent -220 /CapHeight 700 /StemV 80 /FontFile2 9 0 R >>",
        )
    }

    @Test("Serializes Type 0 parent font for embedded TrueType profile")
    func serializesType0ParentFontForEmbeddedTrueTypeProfile() {
        let font = PDFType0FontObject(
            resourceName: "F9",
            baseName: "ABCDEF+PortableSerif",
            descendantFont: PDFSyntax.Reference(objectNumber: 10),
            toUnicodeMap: PDFSyntax.Reference(objectNumber: 11),
        )

        #expect(font.resourceName == "F9")
        #expect(
            font.pdfDictionary.serialized()
                == "<< /Type /Font /Subtype /Type0 /BaseFont /ABCDEF+PortableSerif /Encoding /Identity-H /DescendantFonts [10 0 R] /ToUnicode 11 0 R >>",
        )
    }

    @Test("Serializes CIDFontType2 descendant with system info and widths")
    func serializesCIDFontType2DescendantWithSystemInfoAndWidths() {
        let font = PDFCIDFontType2Object(
            baseName: "ABCDEF+PortableSerif",
            fontDescriptor: PDFSyntax.Reference(objectNumber: 12),
            widths: PDFCIDFontWidths(segments: [
                .array(startCID: 1, widths: [500, 610]),
                .range(startCID: 4, endCID: 6, width: 700),
            ]),
        )
        let compactCIDFont = PDFCIDFontType2Object(
            baseName: "ABCDEF+PortableSerif",
            fontDescriptor: PDFSyntax.Reference(objectNumber: 12),
            widths: PDFCIDFontWidths(segments: [
                .array(startCID: 1, widths: [500]),
            ]),
            cidToGIDMap: .stream(PDFSyntax.Reference(objectNumber: 13)),
        )

        #expect(
            font.pdfDictionary.serialized()
                ==
                "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /ABCDEF+PortableSerif /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor 12 0 R /W [1 [500 610] 4 6 700] /CIDToGIDMap /Identity >>",
        )
        #expect(compactCIDFont.pdfDictionary.serialized().contains("/CIDToGIDMap 13 0 R"))
    }

    @Test("Serializes FontFile2 stream with uncompressed length")
    func serializesFontFile2StreamWithUncompressedLength() {
        let stream = PDFFontFile2Stream(fontProgram: Data([0x00, 0x01, 0x00, 0x00])).pdfStream

        #expect(
            String(decoding: stream.serialized, as: UTF8.self)
                ==
                """
                << /Length1 4 /Length 4 >>
                stream
                \u{0}\u{1}\u{0}\u{0}
                endstream
                """,
        )
    }

    @Test("Serializes deterministic ToUnicode CMap stream")
    func serializesDeterministicToUnicodeCMapStream() {
        let cmap = PDFToUnicodeCMap(mappings: [
            PDFToUnicodeCMap.Mapping(code: 2, unicode: "B"),
            PDFToUnicodeCMap.Mapping(code: 1, unicode: "A"),
        ])
        let chunked = PDFToUnicodeCMap(mappings: (0 ..< 101).map { index in
            PDFToUnicodeCMap.Mapping(code: UInt16(index + 1), unicode: "A")
        }).serialized
        let unicode = PDFToUnicodeCMap(mappings: [
            PDFToUnicodeCMap.Mapping(code: 3, unicode: "\u{017D}"),
            PDFToUnicodeCMap.Mapping(code: 4, unicode: "\u{1F600}"),
        ]).serialized

        #expect(cmap.serialized.contains("1 beginbfrange"))
        #expect(cmap.serialized.contains("<0001> <0002> <0041>"))
        #expect(cmap.pdfStream.serialized.contains(Data("/Length ".utf8)))
        #expect(chunked.contains("100 beginbfchar"))
        #expect(chunked.contains("1 beginbfchar"))
        #expect(unicode.contains("<0003> <017D>"))
        #expect(unicode.contains("<0004> <D83DDE00>"))
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

    @Test("Writer serializes embedded CID font object graph for mapped text")
    func writerSerializesEmbeddedCIDFontObjectGraphForMappedText() throws {
        let fontData = SyntheticTrueTypeFont.data(includeGlyphOutlines: true)
        let metadata = try TrueTypeFontParser().parse(fontData)
        let mapping = try TrueTypeGlyphMapper(data: fontData, metadata: metadata).map(text: "ABBA", fontSize: 14)
        let canvas = PDFPageCanvas()

        try canvas.drawCIDText(
            mapping: mapping,
            fontResource: PDFEmbeddedFontResource(resourceName: "EF1", fontProgram: fontData, metadata: metadata),
            fontSize: 14,
            x: 40,
            y: 120,
        )
        let data = try PDFDocumentWriter(
            pageSize: PDFOptions.PageSize(width: 300, height: 200),
            fontSet: .pdfBase,
            pages: [canvas],
            images: [],
            title: nil,
        ).data()
        let text = String(decoding: data, as: UTF8.self)

        #expect(canvas.resourceUsage.usedEmbeddedFonts.map(\.resource.resourceName) == ["EF1"])
        #expect(canvas.commands.contains("/EF1 14 Tf"))
        #expect(canvas.commands.contains("<0001000200020001> Tj"))
        #expect(text.contains("/Font << /EF1"))
        #expect(text.contains("/Subtype /Type0"))
        #expect(text.contains("/Encoding /Identity-H"))
        #expect(text.contains("/Subtype /CIDFontType2"))
        #expect(text.contains("/CIDToGIDMap /Identity"))
        #expect(text.contains("/W [1 [600] 2 [600]]"))
        #expect(text.contains("/FontFile2"))
        #expect(text.contains("/ToUnicode"))
        #expect(text.contains("<0001> <0002> <0041>"))
        #expect(!text.contains("/F1 14 Tf"))
    }

    @Test("Writer serializes shaped ligature clusters with source ToUnicode")
    func writerSerializesShapedLigatureClustersWithSourceToUnicode() throws {
        let fontData = SyntheticTrueTypeFont.data(
            glyphProfile: .latinLigature,
            includeGlyphOutlines: true,
            includeGSUBLigatures: true,
        )
        let metadata = try TrueTypeFontParser().parse(fontData)
        let mapping = try OpenTypeShaper(data: fontData, metadata: metadata).shape(text: "file", fontSize: 14)
        let canvas = PDFPageCanvas()

        try canvas.drawCIDText(
            mapping: mapping,
            fontResource: PDFEmbeddedFontResource(resourceName: "EF1", fontProgram: fontData, metadata: metadata),
            fontSize: 14,
            x: 40,
            y: 120,
        )
        let data = try PDFDocumentWriter(
            pageSize: PDFOptions.PageSize(width: 300, height: 200),
            fontSet: .pdfBase,
            pages: [canvas],
            images: [],
            title: "Shaped Ligature Witness",
        ).data()
        let text = String(decoding: data, as: UTF8.self)

        #expect(canvas.commands.contains("<000600030004> Tj"))
        #expect(text.contains("/Subtype /Type0"))
        #expect(text.contains("/Subtype /CIDFontType2"))
        #expect(text.contains("/ToUnicode"))
        #expect(text.contains("<0003> <006C>"))
        #expect(text.contains("<0004> <0065>"))
        #expect(text.contains("<0006> <00660069>"))

        try PDFValidation.writeArtifact(data, name: "shaped-ligature-writer-witness.pdf")
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "shaped-ligature-writer-qpdf")
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        let extractedText = try PDFValidation.pdftotext(data: data, name: "shaped-ligature-writer-text")
        try #require(extractedText.exitCode == 0, "pdftotext failed:\n\(extractedText.output)")
        #expect(extractedText.output.contains("file"))
    }

    @Test("Writer serializes shaped ligature plus mark clusters with source ToUnicode")
    func writerSerializesShapedLigaturePlusMarkClustersWithSourceToUnicode() throws {
        let fontData = SyntheticTrueTypeFont.data(
            glyphProfile: .latinLigature,
            includeGlyphOutlines: true,
            includeGSUBLigatures: true,
        )
        let metadata = try TrueTypeFontParser().parse(fontData)
        let source = "fi\u{0301}"
        let mapping = try OpenTypeShaper(data: fontData, metadata: metadata).shape(text: source, fontSize: 14)
        let canvas = PDFPageCanvas()

        try canvas.drawCIDText(
            mapping: mapping,
            fontResource: PDFEmbeddedFontResource(resourceName: "EF1", fontProgram: fontData, metadata: metadata),
            fontSize: 14,
            x: 40,
            y: 120,
        )
        let data = try PDFDocumentWriter(
            pageSize: PDFOptions.PageSize(width: 300, height: 200),
            fontSet: .pdfBase,
            pages: [canvas],
            images: [],
            title: "Shaped Ligature Mark Witness",
        ).data()
        let text = String(decoding: data, as: UTF8.self)

        #expect(canvas.commands.contains("<00060005> Tj"))
        #expect(text.contains("<0005> <0301>"))
        #expect(text.contains("<0006> <00660069>"))

        try PDFValidation.writeArtifact(data, name: "shaped-ligature-mark-writer-witness.pdf")
        let qpdf = try PDFValidation.qpdfCheck(data: data, name: "shaped-ligature-mark-writer-qpdf")
        try #require(qpdf.exitCode == 0, "qpdf --check failed:\n\(qpdf.output)")
        let extractedText = try PDFValidation.pdftotext(data: data, name: "shaped-ligature-mark-writer-text")
        try #require(extractedText.exitCode == 0, "pdftotext failed:\n\(extractedText.output)")
        #expect(extractedText.output.contains(source))
    }

    @Test("Writer serializes subset FontFile2 length and CIDToGIDMap stream")
    func writerSerializesSubsetFontFileLengthAndCIDToGIDMapStream() throws {
        let fontData = SyntheticTrueTypeFont.data(glyphProfile: .latinWitness, includeGlyphOutlines: true)
        let metadata = try TrueTypeFontParser().parse(fontData)
        let mapping = try TrueTypeGlyphMapper(data: fontData, metadata: metadata).map(text: "WAVE", fontSize: 14)
        let subset = try TrueTypeFontSubsetter(data: fontData, metadata: metadata).subset(glyphs: mapping.glyphs)
        let canvas = PDFPageCanvas()

        try canvas.drawCIDText(
            mapping: mapping,
            fontResource: PDFEmbeddedFontResource(resourceName: "EF1", fontProgram: fontData, metadata: metadata),
            fontSize: 14,
            x: 40,
            y: 120,
        )
        let data = try PDFDocumentWriter(
            pageSize: PDFOptions.PageSize(width: 300, height: 200),
            fontSet: .pdfBase,
            pages: [canvas],
            images: [],
            title: nil,
        ).data()
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("/Length1 \(subset.fontProgram.count)"))
        #expect(text.contains("/CIDToGIDMap "))
        #expect(!text.contains("/CIDToGIDMap /Identity"))
        #expect(text.contains("/W [2 [600] 6 [600] 23 [600] 24 [900]]"))
    }

    @Test("Writer rejects conflicting CID widths before serializing PDF")
    func writerRejectsConflictingCIDWidthsBeforeSerializingPDF() throws {
        let fontData = SyntheticTrueTypeFont.data(includeGlyphOutlines: true)
        let metadata = try TrueTypeFontParser().parse(fontData)
        let canvas = PDFPageCanvas()
        let mapping = TrueTypeGlyphMapper.TextMapping(
            sourceText: "AB",
            glyphs: [
                glyph(scalar: "A", glyphID: 1, cid: 1, pdfCharacterCode: 1, advanceWidth: 600),
                glyph(scalar: "B", glyphID: 2, cid: 1, pdfCharacterCode: 2, advanceWidth: 650),
            ],
        )

        try canvas.drawCIDText(
            mapping: mapping,
            fontResource: PDFEmbeddedFontResource(resourceName: "EF1", fontProgram: fontData, metadata: metadata),
            fontSize: 12,
            x: 40,
            y: 120,
        )

        do {
            _ = try PDFDocumentWriter(
                pageSize: PDFOptions.PageSize(width: 300, height: 200),
                fontSet: .pdfBase,
                pages: [canvas],
                images: [],
                title: nil,
            ).data()
            Issue.record("Expected conflicting CID width error")
        } catch let error as PDFEmbeddedFontError {
            #expect(error == .conflictingCIDWidth(cid: 1, existing: 600, duplicate: 650))
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
        } catch {
            Issue.record("Expected PDFEmbeddedFontError, got \(error)")
        }
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

    private func resolvedDestination(
        name: String,
        title: String,
        level: Int,
        page: Int,
        y: Double,
    ) -> PDFNamedDestinations.ResolvedDestination {
        PDFNamedDestinations.ResolvedDestination(
            destination: PDFHeadingDestination(
                name: name,
                title: title,
                level: level,
                x: 54,
                y: y,
            ),
            page: PDFSyntax.Reference(objectNumber: page),
        )
    }

    private func glyph(
        scalar: UnicodeScalar,
        glyphID: UInt16,
        cid: UInt16,
        pdfCharacterCode: UInt16,
        advanceWidth: UInt16,
    ) -> TrueTypeGlyphMapper.Glyph {
        TrueTypeGlyphMapper.Glyph(
            scalar: scalar,
            glyphID: glyphID,
            cid: cid,
            pdfCharacterCode: pdfCharacterCode,
            advanceWidth: advanceWidth,
            width: Double(advanceWidth) / 1000 * 12,
        )
    }
}
