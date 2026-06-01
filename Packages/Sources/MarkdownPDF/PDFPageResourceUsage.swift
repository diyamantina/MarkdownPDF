struct PDFPageResourceUsage {
    private var fonts: Set<StandardFont> = []
    private var imageXObjectNames: Set<String> = []
    private var embeddedFontsByResourceName: [String: PDFEmbeddedFontUsage] = [:]

    var usedFonts: [StandardFont] {
        StandardFont.allCases.filter { fonts.contains($0) }
    }

    var usedEmbeddedFonts: [PDFEmbeddedFontUsage] {
        embeddedFontsByResourceName.keys.sorted().compactMap { embeddedFontsByResourceName[$0] }
    }

    var usedImageXObjectNames: Set<String> {
        imageXObjectNames
    }

    mutating func useFont(_ font: StandardFont) {
        fonts.insert(font)
    }

    mutating func useImageXObject(named name: String) {
        imageXObjectNames.insert(name)
    }

    mutating func useEmbeddedFont(
        _ resource: PDFEmbeddedFontResource,
        glyphs: [TrueTypeGlyphMapper.Glyph],
    ) throws {
        guard !StandardFont.allCases.contains(where: { $0.rawValue == resource.resourceName }) else {
            throw PDFEmbeddedFontError.reservedBaseFontResourceName(resource.resourceName)
        }
        guard !glyphs.isEmpty else {
            throw PDFEmbeddedFontError.emptyGlyphSet(resourceName: resource.resourceName)
        }

        if var usage = embeddedFontsByResourceName[resource.resourceName] {
            guard usage.resource == resource else {
                throw PDFEmbeddedFontError.conflictingFontResource(resourceName: resource.resourceName)
            }
            usage.append(glyphs: glyphs)
            embeddedFontsByResourceName[resource.resourceName] = usage
        } else {
            embeddedFontsByResourceName[resource.resourceName] = PDFEmbeddedFontUsage(
                resource: resource,
                glyphs: glyphs,
            )
        }
    }

    func usesFont(_ font: StandardFont) -> Bool {
        fonts.contains(font)
    }

    func usesImageXObject(named name: String) -> Bool {
        imageXObjectNames.contains(name)
    }
}
