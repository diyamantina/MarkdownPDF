import Foundation

struct PDFInspector {
    struct Stream: Equatable {
        var declaredLength: Int
        var actualLength: Int
        var body: String
    }

    struct IndirectObject: Equatable {
        var number: Int
        var content: String
        var isStream: Bool
    }

    struct ResourceDictionary: Equatable {
        var fonts: [String: Int]
        var xObjects: [String: Int]
    }

    private struct XrefEntry: Equatable {
        var objectNumber: Int
        var offset: Int
        var generation: Int
        var inUse: Bool
    }

    private let bytes: [UInt8]
    let text: String

    init(_ data: Data) {
        bytes = Array(data)
        text = String(decoding: data, as: UTF8.self)
    }

    var pageCount: Int {
        occurrences(of: "<< /Type /Page\n")
    }

    var linkAnnotationCount: Int {
        occurrences(of: "/Subtype /Link")
    }

    var outlineItemCount: Int {
        indirectObjects.count(where: { object in
            object.content.contains("/Title ") && object.content.contains("/Dest [")
        })
    }

    var namedDestinationNames: [String] {
        guard let catalog = catalogObject(),
              let names = dictionary(after: "/Names", in: catalog.content)
        else {
            return []
        }

        return namedDestinations(in: names).map(\.name)
    }

    var namedDestinationPages: [String: Int] {
        guard let catalog = catalogObject(),
              let names = dictionary(after: "/Names", in: catalog.content)
        else {
            return [:]
        }

        let pageIndexes = Dictionary(
            uniqueKeysWithValues: pageObjectNumbers.enumerated().map { index, objectNumber in
                (objectNumber, index + 1)
            },
        )
        return Dictionary(
            uniqueKeysWithValues: namedDestinations(in: names).map { destination in
                (destination.name, pageIndexes[destination.page] ?? -1)
            },
        )
    }

    var internalLinkDestinationNames: [String] {
        indirectObjects.flatMap { object -> [String] in
            guard object.content.contains("/Subtype /Link") else {
                return []
            }

            return regexMatches(#"/Dest \(([^)]*)\)"#, in: object.content).compactMap(\.first)
        }
    }

    var hasDocumentMetadata: Bool {
        guard let objects = indirectObjectDictionary(),
              let trailer = trailerDictionary(),
              let infoRef = reference(after: "/Info", in: trailer),
              let info = objects[infoRef],
              let catalog = catalogObject(),
              let metadataRef = reference(after: "/Metadata", in: catalog.content),
              let metadata = objects[metadataRef]
        else {
            return false
        }

        return info.content.contains("/Producer ")
            && metadata.isStream
            && metadata.content.contains("/Type /Metadata")
            && metadata.content.contains("/Subtype /XML")
    }

    var indirectObjectCount: Int {
        occurrences(of: " 0 obj\n")
    }

    var pageObjectNumbers: [Int] {
        guard let objects = indirectObjectDictionary(),
              let catalog = catalogObject(),
              let pagesRef = reference(after: "/Pages", in: catalog.content),
              let pages = objects[pagesRef]
        else {
            return []
        }

        return references(inArrayAfter: "/Kids", in: pages.content)
    }

    var streams: [Stream] {
        let streamMarker = Array("stream\n".utf8)
        let endMarker = Array("\nendstream".utf8)
        var result: [Stream] = []
        var searchStart = 0

        while let streamRange = range(of: streamMarker, from: searchStart),
              let endRange = range(of: endMarker, from: streamRange.upperBound)
        {
            let bodyBytes = bytes[streamRange.upperBound ..< endRange.lowerBound]
            result.append(
                Stream(
                    declaredLength: declaredLength(before: streamRange.lowerBound) ?? -1,
                    actualLength: bodyBytes.count,
                    body: String(decoding: bodyBytes, as: UTF8.self),
                ),
            )
            searchStart = endRange.upperBound
        }

        return result
    }

    func hasValidXrefOffsets() -> Bool {
        guard let entries = xrefEntries(), entries.contains(where: \.inUse) else {
            return false
        }

        for entry in entries where entry.inUse {
            guard hasBytes(Array("\(entry.objectNumber) 0 obj\n".utf8), at: entry.offset) else {
                return false
            }
        }

        return true
    }

    func streamLengthsMatch() -> Bool {
        let streams = streams
        return !streams.isEmpty && streams.allSatisfy { $0.declaredLength == $0.actualLength }
    }

    var indirectObjects: [IndirectObject] {
        guard let entries = xrefEntries() else {
            return []
        }

        return entries.compactMap { entry in
            guard entry.inUse else {
                return nil
            }

            let objectMarker = Array("\(entry.objectNumber) 0 obj\n".utf8)
            guard hasBytes(objectMarker, at: entry.offset),
                  let endRange = range(of: Array("\nendobj".utf8), from: entry.offset + objectMarker.count)
            else {
                return nil
            }

            let contentBytes = bytes[(entry.offset + objectMarker.count) ..< endRange.lowerBound]
            let content = String(decoding: contentBytes, as: UTF8.self)
            return IndirectObject(
                number: entry.objectNumber,
                content: content,
                isStream: content.contains("\nstream\n"),
            )
        }
    }

    private func indirectObjectDictionary() -> [Int: IndirectObject]? {
        let objects = Dictionary(uniqueKeysWithValues: indirectObjects.map { ($0.number, $0) })
        return objects.isEmpty ? nil : objects
    }

    private func catalogObject() -> IndirectObject? {
        guard let objects = indirectObjectDictionary(),
              let trailer = trailerDictionary(),
              let rootRef = reference(after: "/Root", in: trailer)
        else {
            return nil
        }

        return objects[rootRef]
    }

    func canonicalStructureIssues() -> [String] {
        var issues: [String] = []
        if !text.hasPrefix("%PDF-1.4\n%") {
            issues.append("header is not the expected PDF 1.4 header")
        }
        if !text.hasSuffix("%%EOF") {
            issues.append("file does not end with %%EOF")
        }
        if !streamLengthsMatch() {
            issues.append("one or more stream lengths do not match emitted bytes")
        }
        if !hasValidXrefOffsets() {
            issues.append("xref table has offsets that do not point to matching objects")
        }

        guard let entries = xrefEntries() else {
            issues.append("xref table is missing or malformed")
            return issues
        }
        validateXrefEntries(entries, issues: &issues)

        if let startXref = startXrefOffset() {
            if !hasBytes(Array("xref\n".utf8), at: startXref) {
                issues.append("startxref does not point to the xref table")
            }
        } else {
            issues.append("startxref is missing or malformed")
        }

        let objects = indirectObjectDictionary() ?? [:]
        let objectCount = entries.filter(\.inUse).count
        if objects.count != objectCount {
            issues.append("parsed object count \(objects.count) does not match xref in-use count \(objectCount)")
        }

        guard let trailer = trailerDictionary() else {
            issues.append("trailer dictionary is missing")
            return issues
        }

        if integer(after: "/Size", in: trailer) != entries.count {
            issues.append("trailer /Size does not match xref entry count")
        }
        if let infoRef = reference(after: "/Info", in: trailer) {
            validateInfo(ref: infoRef, objects: objects, issues: &issues)
        }

        guard let rootRef = reference(after: "/Root", in: trailer) else {
            issues.append("trailer /Root reference is missing")
            return issues
        }
        guard let catalog = objects[rootRef] else {
            issues.append("trailer /Root object \(rootRef) is missing")
            return issues
        }
        validateCatalog(catalog, objects: objects, issues: &issues)

        return issues
    }

    func canonicalStructureReport() -> String {
        canonicalStructureIssues().joined(separator: "\n")
    }

    private func validateCatalog(
        _ catalog: IndirectObject,
        objects: [Int: IndirectObject],
        issues: inout [String],
    ) {
        if !hasName("/Type", value: "Catalog", in: catalog.content) {
            issues.append("root object \(catalog.number) is not a catalog")
        }

        guard let pagesRef = reference(after: "/Pages", in: catalog.content) else {
            issues.append("catalog is missing /Pages")
            return
        }
        guard let pages = objects[pagesRef] else {
            issues.append("catalog /Pages object \(pagesRef) is missing")
            return
        }

        validatePages(pages, objects: objects, issues: &issues)

        if let metadataRef = reference(after: "/Metadata", in: catalog.content) {
            validateMetadata(ref: metadataRef, objects: objects, issues: &issues)
        }
        if let outlinesRef = reference(after: "/Outlines", in: catalog.content) {
            validateOutlines(ref: outlinesRef, objects: objects, issues: &issues)
        }
        let names = dictionary(after: "/Names", in: catalog.content)
        if let names {
            validateNamedDestinations(names, objects: objects, issues: &issues)
        }
        validateInternalLinkDestinations(objects: objects, names: names, issues: &issues)
    }

    private func validatePages(
        _ pages: IndirectObject,
        objects: [Int: IndirectObject],
        issues: inout [String],
    ) {
        if !hasName("/Type", value: "Pages", in: pages.content) {
            issues.append("pages object \(pages.number) is missing /Type /Pages")
        }

        let kids = references(inArrayAfter: "/Kids", in: pages.content)
        if kids.isEmpty {
            issues.append("pages object \(pages.number) has no /Kids")
        }
        if integer(after: "/Count", in: pages.content) != kids.count {
            issues.append("pages object \(pages.number) /Count does not match /Kids")
        }

        for pageRef in kids {
            guard let page = objects[pageRef] else {
                issues.append("page object \(pageRef) is missing")
                continue
            }
            validatePage(page, parentRef: pages.number, objects: objects, issues: &issues)
        }
    }

    private func validatePage(
        _ page: IndirectObject,
        parentRef: Int,
        objects: [Int: IndirectObject],
        issues: inout [String],
    ) {
        if !hasName("/Type", value: "Page", in: page.content) {
            issues.append("page object \(page.number) is missing /Type /Page")
        }
        for key in requiredPageKeys() where !page.content.contains(key) {
            issues.append("page object \(page.number) is missing \(key)")
        }
        if reference(after: "/Parent", in: page.content) != parentRef {
            issues.append("page object \(page.number) has an invalid /Parent")
        }

        let resources = resourceDictionary(in: page.content) ?? ResourceDictionary(fonts: [:], xObjects: [:])
        validateResources(resources, objects: objects, issues: &issues)

        if let contentRef = reference(after: "/Contents", in: page.content) {
            guard let content = objects[contentRef] else {
                issues.append("page object \(page.number) references missing content object \(contentRef)")
                return
            }
            guard content.isStream, let body = streamBody(in: content.content) else {
                issues.append("content object \(contentRef) is not a stream")
                return
            }
            validateResourceUsage(
                body,
                resources: resources,
                pageNumber: page.number,
                issues: &issues,
            )
        }

        for annotationRef in references(inArrayAfter: "/Annots", in: page.content) {
            guard let annotation = objects[annotationRef] else {
                issues.append("page object \(page.number) references missing annotation object \(annotationRef)")
                continue
            }
            validateAnnotation(annotation, issues: &issues)
        }
    }

    private func validateResources(
        _ resources: ResourceDictionary,
        objects: [Int: IndirectObject],
        issues: inout [String],
    ) {
        for (name, ref) in resources.fonts {
            guard let font = objects[ref] else {
                issues.append("font resource /\(name) references missing object \(ref)")
                continue
            }
            if !hasName("/Type", value: "Font", in: font.content) {
                issues.append("font resource /\(name) object \(ref) is not a font")
            }
        }

        for (name, ref) in resources.xObjects {
            guard let xObject = objects[ref] else {
                issues.append("XObject resource /\(name) references missing object \(ref)")
                continue
            }
            if !hasName("/Type", value: "XObject", in: xObject.content)
                || !hasName("/Subtype", value: "Image", in: xObject.content)
            {
                issues.append("XObject resource /\(name) object \(ref) is not an image XObject")
            }
        }
    }

    private func validateResourceUsage(
        _ streamBody: String,
        resources: ResourceDictionary,
        pageNumber: Int,
        issues: inout [String],
    ) {
        for name in usedFonts(in: streamBody) where resources.fonts[name] == nil {
            issues.append("page object \(pageNumber) uses undeclared font /\(name)")
        }
        for name in usedXObjects(in: streamBody) where resources.xObjects[name] == nil {
            issues.append("page object \(pageNumber) uses undeclared XObject /\(name)")
        }
    }

    private func validateAnnotation(_ annotation: IndirectObject, issues: inout [String]) {
        let required = ["/Type /Annot", "/Subtype /Link", "/Rect ["]
        for key in required where !annotation.content.contains(key) {
            issues.append("annotation object \(annotation.number) is missing \(key)")
        }
        let hasURIAction = annotation.content.contains("/A <<")
            && annotation.content.contains("/S /URI")
            && annotation.content.contains("/URI ")
        let hasDestination = annotation.content.contains("/Dest ")
        if !hasURIAction, !hasDestination {
            issues.append("annotation object \(annotation.number) is missing URI action or destination")
        }
    }

    private func validateInfo(
        ref: Int,
        objects: [Int: IndirectObject],
        issues: inout [String],
    ) {
        guard let info = objects[ref] else {
            issues.append("trailer /Info object \(ref) is missing")
            return
        }
        if !info.content.contains("/Producer ") {
            issues.append("info object \(ref) is missing /Producer")
        }
    }

    private func validateMetadata(
        ref: Int,
        objects: [Int: IndirectObject],
        issues: inout [String],
    ) {
        guard let metadata = objects[ref] else {
            issues.append("catalog /Metadata object \(ref) is missing")
            return
        }
        if !metadata.isStream {
            issues.append("metadata object \(ref) is not a stream")
        }
        for key in ["/Type /Metadata", "/Subtype /XML"] where !metadata.content.contains(key) {
            issues.append("metadata object \(ref) is missing \(key)")
        }
    }

    private func validateOutlines(
        ref: Int,
        objects: [Int: IndirectObject],
        issues: inout [String],
    ) {
        guard let outline = objects[ref] else {
            issues.append("catalog /Outlines object \(ref) is missing")
            return
        }
        if !hasName("/Type", value: "Outlines", in: outline.content) {
            issues.append("outline object \(ref) is missing /Type /Outlines")
        }

        var visited: Set<Int> = []
        visitOutlineItems(parent: outline, objects: objects, visited: &visited, issues: &issues)
        if integer(after: "/Count", in: outline.content) != visited.count {
            issues.append("outline object \(ref) /Count does not match reachable items")
        }
    }

    private func visitOutlineItems(
        parent: IndirectObject,
        objects: [Int: IndirectObject],
        visited: inout Set<Int>,
        issues: inout [String],
    ) {
        var nextRef = reference(after: "/First", in: parent.content)
        while let itemRef = nextRef {
            guard !visited.contains(itemRef) else {
                issues.append("outline item \(itemRef) is linked more than once")
                return
            }
            guard let item = objects[itemRef] else {
                issues.append("outline item object \(itemRef) is missing")
                return
            }
            visited.insert(itemRef)
            validateOutlineItem(item, objects: objects, issues: &issues)
            visitOutlineItems(parent: item, objects: objects, visited: &visited, issues: &issues)
            nextRef = reference(after: "/Next", in: item.content)
        }
    }

    private func validateOutlineItem(
        _ item: IndirectObject,
        objects: [Int: IndirectObject],
        issues: inout [String],
    ) {
        for key in ["/Title ", "/Parent ", "/Dest ["] where !item.content.contains(key) {
            issues.append("outline item \(item.number) is missing \(key)")
        }
        guard let pageRef = references(inArrayAfter: "/Dest", in: item.content).first,
              let page = objects[pageRef],
              hasName("/Type", value: "Page", in: page.content)
        else {
            issues.append("outline item \(item.number) does not point at a valid page destination")
            return
        }
    }

    private func validateNamedDestinations(
        _ names: String,
        objects: [Int: IndirectObject],
        issues: inout [String],
    ) {
        let destinations = namedDestinations(in: names)
        if destinations.isEmpty {
            issues.append("catalog /Names dictionary has no named destinations")
        }

        for destination in destinations {
            guard let page = objects[destination.page],
                  hasName("/Type", value: "Page", in: page.content)
            else {
                issues.append("named destination \(destination.name) points at missing page object \(destination.page)")
                continue
            }
        }
    }

    private func validateInternalLinkDestinations(
        objects: [Int: IndirectObject],
        names: String?,
        issues: inout [String],
    ) {
        let linkNames = objects.values.flatMap { object in
            guard object.content.contains("/Subtype /Link") else {
                return [String]()
            }

            return regexMatches(#"/Dest\s+\(([^)]*)\)"#, in: object.content).compactMap(\.first)
        }
        guard !linkNames.isEmpty else {
            return
        }
        guard let names else {
            for linkName in linkNames {
                issues.append("link annotation points at destination \(linkName) but catalog /Names is missing")
            }
            return
        }

        let destinationNames = Set(namedDestinations(in: names).map(\.name))
        for linkName in linkNames where !destinationNames.contains(linkName) {
            issues.append("link annotation points at unknown destination \(linkName)")
        }
    }

    private func validateXrefEntries(_ entries: [XrefEntry], issues: inout [String]) {
        if entries.first != XrefEntry(objectNumber: 0, offset: 0, generation: 65535, inUse: false) {
            issues.append("xref table is missing canonical free object 0")
        }

        let expectedObjectNumbers = Array(0 ..< entries.count)
        let actualObjectNumbers = entries.map(\.objectNumber)
        if actualObjectNumbers != expectedObjectNumbers {
            issues.append("xref table object numbers are not consecutive from 0")
        }
    }

    private func xrefEntries() -> [XrefEntry]? {
        let lines = text.components(separatedBy: "\n")
        guard let xrefIndex = lines.firstIndex(of: "xref"),
              xrefIndex + 2 < lines.count
        else {
            return nil
        }

        let header = lines[xrefIndex + 1].split(separator: " ")
        guard header.count == 2,
              let firstObject = Int(header[0]),
              let objectCount = Int(header[1])
        else {
            return nil
        }

        let firstEntryIndex = xrefIndex + 2
        guard firstEntryIndex + objectCount <= lines.count else {
            return nil
        }

        var entries: [XrefEntry] = []
        for relativeIndex in 0 ..< objectCount {
            let fields = lines[firstEntryIndex + relativeIndex].split(separator: " ")
            guard fields.count >= 3,
                  let offset = Int(fields[0]),
                  let generation = Int(fields[1]),
                  ["f", "n"].contains(fields[2])
            else {
                return nil
            }

            entries.append(
                XrefEntry(
                    objectNumber: firstObject + relativeIndex,
                    offset: offset,
                    generation: generation,
                    inUse: fields[2] == "n",
                ),
            )
        }

        return entries
    }

    private func trailerDictionary() -> String? {
        guard let trailerRange = text.range(of: "trailer\n"),
              let startXrefRange = text.range(
                  of: "\nstartxref",
                  range: trailerRange.upperBound ..< text.endIndex,
              )
        else {
            return nil
        }

        return String(text[trailerRange.upperBound ..< startXrefRange.lowerBound])
    }

    private func startXrefOffset() -> Int? {
        guard let range = text.range(of: "startxref\n") else {
            return nil
        }

        let digits = text[range.upperBound...].prefix(while: \.isNumber)
        return Int(digits)
    }

    private func resourceDictionary(in page: String) -> ResourceDictionary? {
        guard let resources = dictionary(after: "/Resources", in: page) else {
            return nil
        }

        return ResourceDictionary(
            fonts: namedReferences(in: dictionary(after: "/Font", in: resources) ?? ""),
            xObjects: namedReferences(in: dictionary(after: "/XObject", in: resources) ?? ""),
        )
    }

    private func dictionary(after marker: String, in text: String) -> String? {
        guard let markerRange = text.range(of: marker) else {
            return nil
        }

        var index = markerRange.upperBound
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }

        guard text[index...].hasPrefix("<<") else {
            return nil
        }

        return balancedDictionary(in: text, from: index)
    }

    private func balancedDictionary(in text: String, from start: String.Index) -> String? {
        var depth = 0
        var index = start

        while index < text.endIndex {
            if text[index...].hasPrefix("<<") {
                depth += 1
                index = text.index(index, offsetBy: 2)
            } else if text[index...].hasPrefix(">>") {
                depth -= 1
                index = text.index(index, offsetBy: 2)
                if depth == 0 {
                    return String(text[start ..< index])
                }
            } else {
                index = text.index(after: index)
            }
        }

        return nil
    }

    private func integer(after marker: String, in text: String) -> Int? {
        guard let markerRange = text.range(of: marker) else {
            return nil
        }

        let suffix = text[markerRange.upperBound...].drop(while: \.isWhitespace)
        return Int(suffix.prefix(while: \.isNumber))
    }

    private func reference(after marker: String, in text: String) -> Int? {
        guard let markerRange = text.range(of: marker) else {
            return nil
        }

        let fields = text[markerRange.upperBound...]
            .split(whereSeparator: \.isWhitespace)
        guard fields.count >= 3, fields[1] == "0", fields[2] == "R" else {
            return nil
        }
        return Int(fields[0])
    }

    private func references(inArrayAfter marker: String, in text: String) -> [Int] {
        guard let markerRange = text.range(of: marker),
              let open = text[markerRange.upperBound...].firstIndex(of: "["),
              let close = text[open...].firstIndex(of: "]")
        else {
            return []
        }

        return referenceNumbers(in: String(text[open ... close]))
    }

    private func namedReferences(in text: String) -> [String: Int] {
        regexMatches(#"/([A-Za-z][A-Za-z0-9]*)\s+(\d+)\s+0\s+R"#, in: text)
            .reduce(into: [String: Int]()) { values, groups in
                guard groups.count == 2, let ref = Int(groups[1]) else {
                    return
                }
                values[groups[0]] = ref
            }
    }

    private func namedDestinations(in text: String) -> [(name: String, page: Int)] {
        regexMatches(#"\(([^)]*)\)\s+\[(\d+)\s+0\s+R\s+/XYZ"#, in: text).compactMap { groups in
            guard groups.count == 2, let page = Int(groups[1]) else {
                return nil
            }

            return (name: groups[0], page: page)
        }
    }

    private func referenceNumbers(in text: String) -> [Int] {
        regexMatches(#"(\d+)\s+0\s+R"#, in: text).compactMap { groups in
            groups.first.flatMap(Int.init)
        }
    }

    private func usedFonts(in text: String) -> Set<String> {
        Set(regexMatches(#"/([A-Za-z][A-Za-z0-9]*)\s+[-+]?\d+(?:\.\d+)?\s+Tf"#, in: text).compactMap(\.first))
    }

    private func usedXObjects(in text: String) -> Set<String> {
        Set(regexMatches(#"/([A-Za-z][A-Za-z0-9]*)\s+Do\b"#, in: text).compactMap(\.first))
    }

    private func hasName(_ name: String, value: String, in text: String) -> Bool {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))\\s+/\(NSRegularExpression.escapedPattern(for: value))(?![A-Za-z0-9])"
        return !regexMatches(pattern, in: text).isEmpty
    }

    private func regexMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (1 ..< match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else {
                    return nil
                }
                return String(text[range])
            }
        }
    }

    private func streamBody(in text: String) -> String? {
        guard let streamRange = text.range(of: "stream\n"),
              let endRange = text.range(of: "\nendstream", range: streamRange.upperBound ..< text.endIndex)
        else {
            return nil
        }

        return String(text[streamRange.upperBound ..< endRange.lowerBound])
    }

    private func requiredPageKeys() -> [String] {
        ["/Parent ", "/MediaBox [", "/Resources ", "/Contents "]
    }

    private func declaredLength(before byteIndex: Int) -> Int? {
        let prefix = String(decoding: bytes[..<byteIndex], as: UTF8.self)
        guard let lengthRange = prefix.range(of: "/Length ", options: .backwards) else {
            return nil
        }

        let digits = prefix[lengthRange.upperBound...].prefix(while: \.isNumber)
        return Int(digits)
    }

    private func occurrences(of needle: String) -> Int {
        var count = 0
        var searchRange = text.startIndex ..< text.endIndex

        while let match = text.range(of: needle, range: searchRange) {
            count += 1
            searchRange = match.upperBound ..< text.endIndex
        }

        return count
    }

    private func range(of needle: [UInt8], from start: Int) -> Range<Int>? {
        guard !needle.isEmpty, start <= bytes.count - needle.count else {
            return nil
        }

        var index = start
        while index <= bytes.count - needle.count {
            let candidate = bytes[index ..< index + needle.count]
            if candidate.elementsEqual(needle) {
                return index ..< index + needle.count
            }
            index += 1
        }

        return nil
    }

    private func hasBytes(_ expected: [UInt8], at offset: Int) -> Bool {
        guard offset >= 0, offset + expected.count <= bytes.count else {
            return false
        }

        return bytes[offset ..< offset + expected.count].elementsEqual(expected)
    }
}
