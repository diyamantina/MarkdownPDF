struct PDFPageResourceUsage {
    private var fonts: Set<StandardFont> = []
    private var imageXObjectNames: Set<String> = []

    var usedFonts: [StandardFont] {
        StandardFont.allCases.filter { fonts.contains($0) }
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

    func usesFont(_ font: StandardFont) -> Bool {
        fonts.contains(font)
    }

    func usesImageXObject(named name: String) -> Bool {
        imageXObjectNames.contains(name)
    }
}
