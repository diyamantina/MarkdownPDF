import Foundation

/// Builds a PDF file from object bodies typed out in a test, so the reader and the
/// structure check are held to files whose content is known before they see it and
/// that the engine did not write.
enum HandWrittenPDF {
    /// A stream object body. `length` overrides the true length, to write a wrong one.
    static func stream(_ body: String, entries: String = "", length: Int? = nil) -> String {
        "<< /Length \(length ?? body.utf8.count)\(entries.isEmpty ? "" : " " + entries) >>\nstream\n\(body)\nendstream"
    }

    /// The file: object `n` is `objects[n - 1]`, the catalog is object 1, and
    /// `trailer` adds entries to the trailer dictionary. `size` overrides `/Size`.
    static func file(objects: [String], trailer: String = "", size: Int? = nil) -> Data {
        var text = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = text.utf8.count
        text += "xref\n0 \(offsets.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            text += String(repeating: "0", count: 10 - String(offset).count) + "\(offset) 00000 n \n"
        }
        text += "trailer\n<< /Size \(size ?? offsets.count + 1) /Root 1 0 R\(trailer.isEmpty ? "" : " " + trailer) >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(text.utf8)
    }
}
