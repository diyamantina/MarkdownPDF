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
    var softMask: PDFImage.SoftMask?

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
            softMask: image.softMask,
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
        softMask: PDFImage.SoftMask? = nil,
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
        self.softMask = softMask
    }

    /// The soft-mask image stream, drawn as DeviceGray through `/SMask`.
    var softMaskStream: PDFSyntax.Stream? {
        guard let softMask else {
            return nil
        }
        return PDFSyntax.Stream(
            dictionary: PDFSyntax.Dictionary([
                .init("Type", .pdfName("XObject")),
                .init("Subtype", .pdfName("Image")),
                .init("Width", .int(softMask.width)),
                .init("Height", .int(softMask.height)),
                .init("ColorSpace", .pdfName("DeviceGray")),
                .init("BitsPerComponent", .int(softMask.bitsPerComponent)),
                .init("Filter", .pdfName("FlateDecode")),
            ]),
            data: softMask.data,
        )
    }

    /// The image dictionary. `softMaskRef` is the already-registered `/SMask`
    /// stream when the image has one.
    func pdfDictionary(softMaskRef: PDFSyntax.Reference?) -> PDFSyntax.Dictionary {
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
        if let softMaskRef {
            entries.append(.init("SMask", .reference(softMaskRef)))
        }

        return PDFSyntax.Dictionary(entries)
    }

    var pdfDictionary: PDFSyntax.Dictionary {
        pdfDictionary(softMaskRef: nil)
    }

    var pdfStream: PDFSyntax.Stream {
        pdfStream(softMaskRef: nil)
    }

    func pdfStream(softMaskRef: PDFSyntax.Reference?) -> PDFSyntax.Stream {
        PDFSyntax.Stream(dictionary: pdfDictionary(softMaskRef: softMaskRef), data: data)
    }

    func resource(objectRef: PDFSyntax.Reference) -> PDFXObjectResource {
        PDFXObjectResource(name: resourceName, objectRef: objectRef, kind: .image)
    }
}
