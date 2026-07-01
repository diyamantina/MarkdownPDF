import Foundation

struct PDFObjectRegistry {
    private var objects: [RegisteredObject] = []

    var count: Int {
        objects.count
    }

    mutating func reserve() -> PDFSyntax.Reference {
        let reference = PDFSyntax.Reference(objectNumber: objects.count + 1)
        objects.append(RegisteredObject(reference: reference, body: nil))
        return reference
    }

    mutating func add(_ body: Data) -> PDFSyntax.Reference {
        let reference = reserve()
        set(reference, body: body)
        return reference
    }

    mutating func set(_ reference: PDFSyntax.Reference, body: Data) {
        objects[index(for: reference)].body = body
    }

    func serializedFile(
        root: PDFSyntax.Reference,
        info: PDFSyntax.Reference? = nil,
        fileID: (original: PDFSyntax.HexString, modified: PDFSyntax.HexString)? = nil,
    ) -> Data {
        _ = index(for: root)
        if let info {
            _ = index(for: info)
        }
        return PDFSyntax.FileEnvelope(
            objects: objects.map(\.indirectObject),
            root: root,
            info: info,
            fileID: fileID,
        ).serialized
    }

    private func index(for reference: PDFSyntax.Reference) -> Int {
        precondition(reference.generation == 0, "PDF object registry only supports generation 0")
        let index = reference.objectNumber - 1
        precondition(objects.indices.contains(index), "PDF object reference is not registered")
        return index
    }

    private struct RegisteredObject {
        var reference: PDFSyntax.Reference
        var body: Data?

        var indirectObject: PDFSyntax.IndirectObject {
            guard let body else {
                preconditionFailure("Reserved PDF object \(reference.objectNumber) was not assigned")
            }

            return PDFSyntax.IndirectObject(reference: reference, body: body)
        }
    }
}
