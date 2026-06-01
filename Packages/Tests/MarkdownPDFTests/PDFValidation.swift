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

    static func pdftoppmPNM(data: some DataProtocol, name: String, resolution: Int = 96) throws -> (result: Result, pnmURL: URL) {
        let url = try temporaryPDF(name: name, data: data)
        return try pdftoppmPNM(url: url, resolution: resolution)
    }

    static func pdftoppmPNM(url: URL, resolution: Int = 96) throws -> (result: Result, pnmURL: URL) {
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
                "-r",
                "\(resolution)",
                url.path,
                outputPrefix.path,
            ],
        )
        return (result, outputPrefix.appendingPathExtension("ppm"))
    }

    static func mutoolPNM(data: some DataProtocol, name: String, resolution: Int = 96) throws -> (result: Result, pnmURL: URL) {
        let url = try temporaryPDF(name: name, data: data)
        return try mutoolPNM(url: url, resolution: resolution)
    }

    static func mutoolPNM(url: URL, resolution: Int = 96) throws -> (result: Result, pnmURL: URL) {
        let directory = try temporaryDirectory()
        let outputURL = directory.appendingPathComponent("page.pnm")
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
                "1",
            ],
        )
        return (result, outputURL)
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
}

private enum Tool {
    static func run(_ executable: String, arguments: [String]) throws -> PDFValidation.Result {
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
