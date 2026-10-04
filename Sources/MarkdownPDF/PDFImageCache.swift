import Foundation

/// Decoded images shared by the layout passes of one render.
///
/// A table of contents or index makes the renderer lay the document out several
/// times. Reading and decoding a figure is by far the costliest step, and its
/// result does not depend on the pass, so the first pass stores it here and later
/// passes reuse it. A failed load is remembered too, so a missing file is read once.
/// The cache lives for one top-level render call and is never global.
final class PDFImageCache {
    private var entries: [URL: Result<PDFImage, Error>] = [:]

    /// The image for `source`, read and decoded on first request. The returned
    /// image carries an empty resource name; the layout assigns its own.
    func image(source: String, baseURL: URL?) throws -> PDFImage {
        let url = PDFImage.resolvedURL(source: source, baseURL: baseURL)
        if let entry = entries[url] {
            return try entry.get()
        }

        let result = Result { try PDFImage.load(source: source, baseURL: baseURL, name: "") }
        entries[url] = result
        return try result.get()
    }
}
