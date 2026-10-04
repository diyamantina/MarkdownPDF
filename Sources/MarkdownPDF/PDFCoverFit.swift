import Foundation

/// Where a cover image is drawn: the closed-form fit rule of ``PDFOptions/Cover``.
enum PDFCoverFit {
    /// Aspect ratios this close are treated as equal (0.1%): the image fills the page.
    static let aspectSnapTolerance = 0.001

    struct Rectangle: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// The rectangle, in page points with the origin at the bottom left, that an image
    /// of `imageWidth` x `imageHeight` pixels occupies on `page`.
    static func rectangle(
        imageWidth: Int,
        imageHeight: Int,
        page: PDFOptions.PageSize,
    ) -> Rectangle {
        let full = Rectangle(x: 0, y: 0, width: page.width, height: page.height)
        guard imageWidth > 0, imageHeight > 0, page.width > 0, page.height > 0 else {
            return full
        }

        let width = Double(imageWidth)
        let height = Double(imageHeight)
        let ratio = (width / height) / (page.width / page.height)
        if abs(ratio - 1) <= aspectSnapTolerance {
            return full
        }

        let scale = min(page.width / width, page.height / height)
        let drawWidth = width * scale
        let drawHeight = height * scale
        return Rectangle(
            x: (page.width - drawWidth) / 2,
            y: (page.height - drawHeight) / 2,
            width: drawWidth,
            height: drawHeight,
        )
    }
}
