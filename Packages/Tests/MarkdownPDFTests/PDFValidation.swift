import Foundation

enum PDFValidation {
    struct Result {
        var exitCode: Int32
        var output: String
    }

    struct Info {
        var values: [String: String]

        subscript(_ key: String) -> String? {
            values[key]
        }
    }

    struct PNGDimensions {
        var width: Int
        var height: Int
    }

    static let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    static let artifactDirectoryEnvironmentKey = "MARKDOWNPDF_ARTIFACT_DIR"

    static func artifactDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> URL? {
        guard let path = environment[artifactDirectoryEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func writeArtifact(_ data: some DataProtocol, name: String) throws {
        try writeArtifact(data, name: name, root: artifactDirectory())
    }

    static func writeArtifact(_ data: some DataProtocol, name: String, root: URL?) throws {
        guard let root else {
            return
        }

        try ArtifactWriter.write(data: Data(data), name: name, root: root)
    }

    static func writeTextArtifact(_ text: String, name: String) throws {
        try writeTextArtifact(text, name: name, root: artifactDirectory())
    }

    static func writeTextArtifact(_ text: String, name: String, root: URL?) throws {
        try writeArtifact(Data(text.utf8), name: name, root: root)
    }

    static func copyArtifact(from url: URL, name: String) throws {
        try copyArtifact(from: url, name: name, root: artifactDirectory())
    }

    static func copyArtifact(from url: URL, name: String, root: URL?) throws {
        guard let root else {
            return
        }

        try ArtifactWriter.copy(from: url, name: name, root: root)
    }

    static func temporaryPDF(name: String, data: some DataProtocol) throws -> URL {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("\(name).pdf")
        try Data(data).write(to: url)
        return url
    }

    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownPDFValidation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func qpdfCheck(data: some DataProtocol, name: String) throws -> Result {
        let url = try temporaryPDF(name: name, data: data)
        return try qpdfCheck(url: url)
    }

    static func qpdfCheck(url: URL) throws -> Result {
        try Tool.run("qpdf", arguments: ["--check", url.path])
    }

    static func pdfinfo(data: some DataProtocol, name: String) throws -> Result {
        let url = try temporaryPDF(name: name, data: data)
        return try pdfinfo(url: url)
    }

    static func pdfinfo(url: URL) throws -> Result {
        try Tool.run("pdfinfo", arguments: [url.path])
    }

    static func parsedInfo(from result: Result) -> Info {
        let values = result.output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .reduce(into: [String: String]()) { values, line in
                guard let separator = line.firstIndex(of: ":") else {
                    return
                }
                let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = line[line.index(after: separator)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                values[key] = value
            }
        return Info(values: values)
    }

    static func pdftotext(data: some DataProtocol, name: String) throws -> Result {
        let url = try temporaryPDF(name: name, data: data)
        return try pdftotext(url: url)
    }

    static func pdftotext(url: URL) throws -> Result {
        try Tool.run("pdftotext", arguments: [url.path, "-"])
    }

    static func pdftotextRaw(url: URL) throws -> Result {
        try Tool.run("pdftotext", arguments: ["-raw", url.path, "-"])
    }

    static func pdftotextTSV(data: some DataProtocol, name: String) throws -> Result {
        let url = try temporaryPDF(name: name, data: data)
        return try pdftotextTSV(url: url)
    }

    static func pdftotextTSV(url: URL) throws -> Result {
        try Tool.run("pdftotext", arguments: ["-tsv", url.path, "-"])
    }

    static func mutoolStructuredText(data: some DataProtocol, name: String) throws -> Result {
        let url = try temporaryPDF(name: name, data: data)
        return try mutoolStructuredText(url: url)
    }

    static func mutoolStructuredText(url: URL) throws -> Result {
        try Tool.run(
            "mutool",
            arguments: [
                "draw",
                "-q",
                "-F",
                "stext",
                "-O",
                "accurate-bboxes,accurate-side-bearings",
                url.path,
            ],
        )
    }

    static func pdftoppmPNM(
        data: some DataProtocol,
        name: String,
        page: Int = 1,
        resolution: Int = 96,
    ) throws -> (result: Result, pnmURL: URL) {
        let url = try temporaryPDF(name: name, data: data)
        return try pdftoppmPNM(url: url, page: page, resolution: resolution)
    }

    static func pdftoppmPNM(
        url: URL,
        page: Int = 1,
        resolution: Int = 96,
    ) throws -> (result: Result, pnmURL: URL) {
        let directory = try temporaryDirectory()
        let outputPrefix = directory.appendingPathComponent("page-\(page)")
        let result = try Tool.run(
            "pdftoppm",
            arguments: [
                "-f",
                "\(page)",
                "-l",
                "\(page)",
                "-singlefile",
                "-r",
                "\(resolution)",
                url.path,
                outputPrefix.path,
            ],
        )
        return (result, outputPrefix.appendingPathExtension("ppm"))
    }

    static func pdftoppmPNMs(
        url: URL,
        pageCount: Int,
        resolution: Int = 96,
    ) throws -> (result: Result, pnmURLs: [URL]) {
        let directory = try temporaryDirectory()
        let outputPrefix = directory.appendingPathComponent("page")
        let result = try Tool.run(
            "pdftoppm",
            arguments: [
                "-r",
                "\(resolution)",
                url.path,
                outputPrefix.path,
            ],
        )
        return (result, numberedPageURLs(directory: directory, extension: "ppm", pageCount: pageCount))
    }

    static func mutoolPNM(
        data: some DataProtocol,
        name: String,
        page: Int = 1,
        resolution: Int = 96,
    ) throws -> (result: Result, pnmURL: URL) {
        let url = try temporaryPDF(name: name, data: data)
        return try mutoolPNM(url: url, page: page, resolution: resolution)
    }

    static func mutoolPNM(
        url: URL,
        page: Int = 1,
        resolution: Int = 96,
    ) throws -> (result: Result, pnmURL: URL) {
        let directory = try temporaryDirectory()
        let outputURL = directory.appendingPathComponent("page-\(page).pnm")
        let result = try Tool.run(
            "mutool",
            arguments: [
                "draw",
                "-q",
                "-F",
                "pnm",
                "-r",
                "\(resolution)",
                "-o",
                outputURL.path,
                url.path,
                "\(page)",
            ],
        )
        return (result, outputURL)
    }

    static func mutoolPNMs(
        url: URL,
        pageCount: Int,
        resolution: Int = 96,
    ) throws -> (result: Result, pnmURLs: [URL]) {
        let directory = try temporaryDirectory()
        let outputPath = directory.appendingPathComponent("page-%d.pnm")
        let result = try Tool.run(
            "mutool",
            arguments: [
                "draw",
                "-q",
                "-F",
                "pnm",
                "-r",
                "\(resolution)",
                "-o",
                outputPath.path,
                url.path,
            ],
        )
        return (result, numberedPageURLs(directory: directory, extension: "pnm", pageCount: pageCount))
    }

    static func pdftoppmPNG(data: some DataProtocol, name: String) throws -> (result: Result, pngURL: URL) {
        let url = try temporaryPDF(name: name, data: data)
        return try pdftoppmPNG(url: url)
    }

    static func pdftoppmPNG(url: URL) throws -> (result: Result, pngURL: URL) {
        let directory = try temporaryDirectory()
        let outputPrefix = directory.appendingPathComponent("page")
        let result = try Tool.run(
            "pdftoppm",
            arguments: [
                "-f",
                "1",
                "-l",
                "1",
                "-singlefile",
                "-png",
                url.path,
                outputPrefix.path,
            ],
        )
        return (result, outputPrefix.appendingPathExtension("png"))
    }

    static func pngDimensions(in data: Data?) -> PNGDimensions? {
        guard let bytes = data.map(Array.init),
              bytes.count >= 24,
              Array(bytes.prefix(8)) == pngSignature
        else {
            return nil
        }

        return PNGDimensions(
            width: bigEndianInt(bytes[16 ..< 20]),
            height: bigEndianInt(bytes[20 ..< 24]),
        )
    }

    private static func bigEndianInt(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { value, byte in
            (value << 8) | Int(byte)
        }
    }

    private static func numberedPageURLs(directory: URL, extension pathExtension: String, pageCount: Int) -> [URL] {
        guard pageCount > 0 else {
            return []
        }

        let paddedWidth = "\(pageCount)".count
        return (1 ... pageCount).map { page in
            let unpadded = directory
                .appendingPathComponent("page-\(page)")
                .appendingPathExtension(pathExtension)
            if FileManager.default.fileExists(atPath: unpadded.path) {
                return unpadded
            }

            let paddedPage = String(format: "%0*d", locale: serializationLocale, paddedWidth, page)
            let padded = directory
                .appendingPathComponent("page-\(paddedPage)")
                .appendingPathExtension(pathExtension)
            if FileManager.default.fileExists(atPath: padded.path) {
                return padded
            }

            return unpadded
        }
    }

    private static let serializationLocale = Locale(identifier: "en_US_POSIX")
}

private enum ArtifactWriter {
    private static let lock = NSLock()

    static func write(data: Data, name: String, root: URL) throws {
        try locked {
            let destination = try destinationURL(root: root, name: name)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try data.write(to: destination, options: .atomic)
        }
    }

    static func copy(from source: URL, name: String, root: URL) throws {
        try locked {
            let destination = try destinationURL(root: root, name: name)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private static func destinationURL(root: URL, name: String) throws -> URL {
        guard !name.isEmpty,
              !name.hasPrefix("/"),
              !name.split(separator: "/").contains(where: { $0 == ".." })
        else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        return root.appendingPathComponent(name, isDirectory: false)
    }

    private static func locked(_ body: () throws -> Void) rethrows {
        lock.lock()
        defer { lock.unlock() }
        try body()
    }
}

private enum Tool {
    private static let processLock = NSLock()

    static func run(_ executable: String, arguments: [String]) throws -> PDFValidation.Result {
        processLock.lock()
        defer { processLock.unlock() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return PDFValidation.Result(
            exitCode: process.terminationStatus,
            output: String(decoding: output, as: UTF8.self),
        )
    }
}
