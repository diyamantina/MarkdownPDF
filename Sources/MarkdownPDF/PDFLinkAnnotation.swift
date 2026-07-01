import Foundation

struct PDFLinkAnnotation {
    enum Target: Equatable {
        case uri(String)
        case destination(name: String, fallbackURI: String)
    }

    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var target: Target

    init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        destination: String,
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        if let name = destination.internalDestinationName {
            target = .destination(name: name, fallbackURI: destination)
        } else {
            target = .uri(destination.pdfURI)
        }
    }
}

private extension String {
    var internalDestinationName: String? {
        guard hasPrefix("#"), count > 1 else {
            return nil
        }

        return PDFHeadingDestinationName.linkTargetName(for: String(dropFirst()))
    }

    var pdfURI: String {
        if contains("://") || hasPrefix("mailto:") || hasPrefix("/") || hasPrefix(".") {
            return self
        }

        if contains("@"), !contains("/") {
            return "mailto:\(self)"
        }

        return self
    }
}
