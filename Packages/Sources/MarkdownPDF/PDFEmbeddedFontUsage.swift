struct PDFEmbeddedFontUsage: Equatable {
    var resource: PDFEmbeddedFontResource
    var glyphs: [TrueTypeGlyphMapper.Glyph]

    mutating func append(glyphs newGlyphs: [TrueTypeGlyphMapper.Glyph]) {
        glyphs.append(contentsOf: newGlyphs)
    }
}
