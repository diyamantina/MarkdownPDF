import Foundation

/// The parts of a file ``PDFDocumentReader`` reads beside its pages: the version,
/// the output intents, the structure tree, and whether the file as a whole is sound.
enum PDFReadStructure {
    private typealias Issue = PDFDocumentReader.StructureIssue

    /// The version the header names: what follows `%PDF-` on the first line.
    static func version(of bytes: [UInt8]) -> String {
        let rest = bytes.dropFirst(5).prefix { $0 != 0x0A && $0 != 0x0D && $0 != 0x20 }
        return String(decoding: rest, as: UTF8.self)
    }

    // MARK: Output intents

    static func outputIntents(of catalog: [String: PDFReadValue], store: PDFReadObjects) throws -> [PDFDocumentReader.OutputIntent] {
        var intents: [PDFDocumentReader.OutputIntent] = []
        for entry in try store.resolve(catalog["OutputIntents"]).array ?? [] {
            guard let intent = try store.resolve(entry).dictionary else {
                continue
            }
            var components: Int?
            if case let .stream(members, _) = try store.resolve(intent["DestOutputProfile"]) {
                components = try store.resolve(members["N"]).number.map { Int($0) } ?? 0
            }
            try intents.append(PDFDocumentReader.OutputIntent(
                subtype: store.resolve(intent["S"]).name ?? "",
                outputConditionIdentifier: store.resolve(intent["OutputConditionIdentifier"]).bytes.map(PDFDocumentReader.textString),
                profileComponents: components,
            ))
        }
        return intents
    }

    // MARK: Structure tree

    /// The structure elements directly under the root of the structure tree.
    static func elements(of catalog: [String: PDFReadValue], store: PDFReadObjects) throws -> [PDFDocumentReader.StructureElement] {
        guard let root = try store.resolve(catalog["StructTreeRoot"]).dictionary else {
            return []
        }
        var visited = Set<Int>()
        return try kids(root["K"], store: store, visited: &visited).elements
    }

    /// The kids of a structure node (`/K`): one kid or an array of them, each a
    /// structure element, a marked-content identifier, or a marked-content reference.
    private static func kids(
        _ value: PDFReadValue?,
        store: PDFReadObjects,
        visited: inout Set<Int>,
    ) throws -> (elements: [PDFDocumentReader.StructureElement], marks: Int) {
        var elements: [PDFDocumentReader.StructureElement] = []
        var marks = 0
        let direct = value ?? .null
        let list: [PDFReadValue] = if case let .array(items) = try store.resolve(direct) {
            items
        } else {
            [direct]
        }
        for item in list {
            if case let .reference(number) = item, !visited.insert(number).inserted {
                throw PDFDocumentReader.ReadError.malformed("the structure tree loops")
            }
            switch try store.resolve(item) {
            case .number:
                marks += 1
            case let .dictionary(members):
                switch members["Type"]?.name {
                case "MCR":
                    marks += 1
                case "OBJR":
                    continue
                default:
                    let under = try kids(members["K"], store: store, visited: &visited)
                    try elements.append(PDFDocumentReader.StructureElement(
                        type: store.resolve(members["S"]).name ?? "",
                        alternateText: store.resolve(members["Alt"]).bytes.map(PDFDocumentReader.textString),
                        markedContentCount: under.marks,
                        children: under.elements,
                    ))
                }
            default:
                continue
            }
        }
        return (elements, marks)
    }

    // MARK: Soundness

    static func issues(in bytes: [UInt8]) -> [PDFDocumentReader.StructureIssue] {
        let store: PDFReadObjects
        do {
            store = try PDFReadObjects(bytes: bytes)
        } catch {
            return [Issue(object: nil, message: describe(error))]
        }
        var issues: [Issue] = []

        var end = bytes.count
        while end > 0, [0x0A, 0x0D, 0x20].contains(bytes[end - 1]) {
            end -= 1
        }
        if end < 5 || Array(bytes[end - 5 ..< end]) != Array("%%EOF".utf8) {
            issues.append(Issue(object: nil, message: "the file does not end with %%EOF"))
        }

        if let size = store.trailer["Size"]?.number.map({ Int($0) }) {
            if let highest = store.offsets.keys.max(), highest >= size {
                issues.append(Issue(object: nil, message: "the trailer /Size \(size) does not cover object \(highest)"))
            }
        } else {
            issues.append(Issue(object: nil, message: "the trailer has no /Size"))
        }

        for number in store.offsets.keys.sorted() {
            issues += objectIssues(number, store: store)
        }

        do {
            let catalog = try store.dictionary(store.trailer["Root"], what: "the catalog")
            if catalog["Type"]?.name != "Catalog" {
                issues.append(Issue(object: nil, message: "the trailer /Root is not a /Catalog"))
            }
            var visited = Set<Int>()
            _ = try pageCount(under: catalog["Pages"], parent: nil, store: store, visited: &visited, issues: &issues)
            _ = try PDFDocumentReader(data: Data(bytes))
        } catch {
            issues.append(Issue(object: nil, message: describe(error)))
        }
        return issues
    }

    private static func describe(_ error: any Error) -> String {
        (error as? PDFDocumentReader.ReadError)?.description ?? "\(error)"
    }

    /// Reads one object where the cross-reference table says it is.
    private static func objectIssues(_ number: Int, store: PDFReadObjects) -> [Issue] {
        guard let offset = store.offsets[number], offset >= 0, offset < store.bytes.count else {
            return [Issue(object: number, message: "its offset is outside the file")]
        }
        var issues: [Issue] = []
        do {
            // The offset is that of the first digit of the object number, not of the space before it.
            var header = PDFReadScanner(store.bytes, at: offset)
            guard (0x30 ... 0x39).contains(store.bytes[offset]), try header.value(allowReferences: false).number == Double(number) else {
                return [Issue(object: number, message: "the cross-reference table points at something that is not this object")]
            }
            var scanner = PDFReadScanner(store.bytes, at: offset)
            let value = try scanner.indirectObject { lengthObject in
                try store.resolve(.reference(lengthObject)).number.map { Int($0) }
            }
            if case .stream = value {
                // The stream data is followed by one end of line at most, then the keyword.
                _ = scanner.consume("\r")
                _ = scanner.consume("\n")
                guard scanner.consume("endstream") else {
                    return [Issue(object: number, message: "its stream does not end where its /Length says")]
                }
                do {
                    _ = try store.streamData(.reference(number))
                } catch PDFDocumentReader.ReadError.unsupported {
                    // A filter this reader does not decode, such as an image codec, is not a fault.
                } catch {
                    issues.append(Issue(object: number, message: describe(error)))
                }
            }
            scanner.skipWhitespace()
            if !scanner.consume("endobj") {
                issues.append(Issue(object: number, message: "it does not end with endobj"))
            }
            for target in references(in: value).sorted() where store.offsets[target] == nil {
                issues.append(Issue(object: number, message: "it refers to object \(target), which the file does not hold"))
            }
        } catch {
            issues.append(Issue(object: number, message: describe(error)))
        }
        return issues
    }

    /// The numbers of the objects `value` refers to, at any depth.
    private static func references(in value: PDFReadValue) -> Set<Int> {
        switch value {
        case let .reference(number):
            [number]
        case let .array(items):
            items.reduce(into: Set<Int>()) { $0.formUnion(references(in: $1)) }
        case let .dictionary(members), let .stream(members, _):
            members.values.reduce(into: Set<Int>()) { $0.formUnion(references(in: $1)) }
        default:
            []
        }
    }

    /// Walks the page tree under `node` and returns how many pages it holds.
    private static func pageCount(
        under node: PDFReadValue?,
        parent: Int?,
        store: PDFReadObjects,
        visited: inout Set<Int>,
        issues: inout [Issue],
    ) throws -> Int {
        guard case let .reference(number)? = node else {
            issues.append(Issue(object: parent, message: "a page tree node is not given by reference"))
            return 0
        }
        guard visited.insert(number).inserted else {
            throw PDFDocumentReader.ReadError.malformed("the page tree loops")
        }
        let dictionary = try store.dictionary(node, what: "a page tree node")
        if let parent, dictionary["Parent"] != .reference(parent) {
            issues.append(Issue(object: number, message: "its /Parent is not object \(parent), the node that lists it"))
        }
        switch dictionary["Type"]?.name {
        case "Pages":
            var count = 0
            for kid in try store.resolve(dictionary["Kids"]).array ?? [] {
                count += try pageCount(under: kid, parent: number, store: store, visited: &visited, issues: &issues)
            }
            let declared = try store.resolve(dictionary["Count"]).number.map { Int($0) }
            if declared != count {
                issues.append(Issue(object: number, message: "its /Count is \(declared.map(String.init) ?? "missing") and it holds \(count) pages"))
            }
            return count
        case "Page":
            let contents = try store.resolve(dictionary["Contents"])
            for part in contents.array ?? [contents] {
                switch try store.resolve(part) {
                case .stream, .null:
                    continue
                default:
                    issues.append(Issue(object: number, message: "its /Contents is not a stream"))
                }
            }
            return 1
        default:
            issues.append(Issue(object: number, message: "a page tree node is neither /Pages nor /Page"))
            return 0
        }
    }
}
