import Foundation

struct PDFEmbeddedFontCatalog {
    struct Entry {
        var resource: PDFEmbeddedFontResource
        var mapper: TrueTypeGlyphMapper
        var shaper: OpenTypeShaper
    }

    private var entriesByFont: [StandardFont: Entry]

    init(fonts: PDFOptions.EmbeddedFonts) throws {
        var entries: [StandardFont: Entry] = [:]
        try Self.add(fonts.regular, for: .helvetica, resourceName: "EF1", to: &entries)
        try Self.add(fonts.bold, for: .helveticaBold, resourceName: "EF2", to: &entries)
        try Self.add(fonts.italic, for: .helveticaOblique, resourceName: "EF3", to: &entries)
        try Self.add(fonts.monospaced, for: .courier, resourceName: "EF4", to: &entries)
        entriesByFont = entries
    }

    func entry(for font: StandardFont) -> Entry? {
        entriesByFont[font]
    }

    func width(of run: PDFTextRun, fallbackFontSet: PDFOptions.FontSet) throws -> Double {
        guard let entry = entry(for: run.font) else {
            return run.width(fontSet: fallbackFontSet)
        }

        return try shapedMapping(for: run, entry: entry).totalAdvance
    }

    func mapping(for run: PDFTextRun, entry: Entry) throws -> TrueTypeGlyphMapper.TextMapping {
        try entry.mapper.map(text: run.text, fontSize: run.size)
    }

    func shapedMapping(for run: PDFTextRun, entry: Entry) throws -> ShapedTextMapping {
        if OpenTypeShaper.canShapeLatinIncrement(run.text) {
            return try entry.shaper.shape(text: run.text, fontSize: run.size)
        }
        if let scalar = run.text.unicodeScalars.first(where: Self.requiresExplicitShapingSupport) {
            throw PDFEmbeddedFontError.unsupportedComplexScriptScalar(scalar: scalar)
        }
        return try mapping(for: run, entry: entry).shapedText()
    }

    private static func add(
        _ source: PDFOptions.EmbeddedFontSource?,
        for font: StandardFont,
        resourceName: String,
        to entries: inout [StandardFont: Entry],
    ) throws {
        guard let source else {
            return
        }

        let metadata = try TrueTypeFontParser().parse(source.data)
        let resource = PDFEmbeddedFontResource(
            resourceName: resourceName,
            fontProgram: source.data,
            metadata: metadata,
            baseName: source.baseName,
        )
        entries[font] = Entry(
            resource: resource,
            mapper: TrueTypeGlyphMapper(data: source.data, metadata: metadata),
            shaper: OpenTypeShaper(data: source.data, metadata: metadata),
        )
    }

    private static func requiresExplicitShapingSupport(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0700 ... 0x074F, // Syriac
             0x0750 ... 0x077F, // Arabic Supplement
             0x0780 ... 0x07BF, // Thaana
             0x07C0 ... 0x07FF, // NKo
             0x08A0 ... 0x08FF, // Arabic Extended-A
             0x0900 ... 0x0D7F, // Indic script blocks used by the first roadmap fixture set.
             0x0E00 ... 0x0E7F, // Thai
             0x1780 ... 0x17FF, // Khmer
             0xFB1D ... 0xFDFF, // Hebrew and Arabic presentation forms
             0xFE70 ... 0xFEFF: // Arabic presentation forms
            true
        default:
            false
        }
    }
}
