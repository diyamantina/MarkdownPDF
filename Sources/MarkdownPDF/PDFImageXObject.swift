import Foundation

struct PDFImageXObject {
    var resourceName: String
    var width: Int
    var height: Int
    var colorSpace: PDFSyntax.Name
    var bitsPerComponent: Int
    var filter: PDFSyntax.Name
    var decodeParms: PDFSyntax.Dictionary?
    var data: Data

    init(image: PDFImage) {
        self.init(
            resourceName: image.name,
            width: image.width,
            height: image.height,
            colorSpace: image.colorSpace,
            bitsPerComponent: image.bitsPerComponent,
            filter: image.filter,
            decodeParms: image.decodeParms,
            data: image.data,
        )
    }

    init(
        resourceName: String,
        width: Int,
        height: Int,
        colorSpace: PDFSyntax.Name,
        bitsPerComponent: Int,
        filter: PDFSyntax.Name,
        decodeParms: PDFSyntax.Dictionary? = nil,
        data: Data,
    ) {
        precondition(!resourceName.isEmpty, "PDF image XObject resource name cannot be empty")
        precondition(width > 0, "PDF image XObject width must be positive")
        precondition(height > 0, "PDF image XObject height must be positive")
        precondition(bitsPerComponent > 0, "PDF image XObject bits per component must be positive")
        precondition(!data.isEmpty, "PDF image XObject data cannot be empty")

        self.resourceName = resourceName
        self.width = width
        self.height = height
        self.colorSpace = colorSpace
        self.bitsPerComponent = bitsPerComponent
        self.filter = filter
        self.decodeParms = decodeParms
        self.data = data
    }

    var pdfDictionary: PDFSyntax.Dictionary {
        var entries: [PDFSyntax.Dictionary.Entry] = [
            .init("Type", .pdfName("XObject")),
            .init("Subtype", .pdfName("Image")),
            .init("Width", .int(width)),
            .init("Height", .int(height)),
            .init("ColorSpace", .name(colorSpace)),
            .init("BitsPerComponent", .int(bitsPerComponent)),
            .init("Filter", .name(filter)),
        ]
        if let decodeParms {
            entries.append(.init("DecodeParms", .dictionary(decodeParms)))
        }

        return PDFSyntax.Dictionary(entries)
    }

    var pdfStream: PDFSyntax.Stream {
        PDFSyntax.Stream(dictionary: pdfDictionary, data: data)
    }

    func resource(objectRef: PDFSyntax.Reference) -> PDFXObjectResource {
        PDFXObjectResource(name: resourceName, objectRef: objectRef, kind: .image)
    }
}
