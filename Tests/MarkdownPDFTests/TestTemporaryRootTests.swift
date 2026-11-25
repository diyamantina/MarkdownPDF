import Foundation
import Testing

@Suite("Temporary root of the tests")
struct TestTemporaryRootTests {
    private let fallback = URL(fileURLWithPath: "/fixture-system/T", isDirectory: true)

    @Test("TMPDIR names the root, a trailing slash names the same one")
    func environmentWins() {
        #expect(TestTemporaryRoot.root(environment: ["TMPDIR": "/fixture-root/tmp"], fallback: fallback).path == "/fixture-root/tmp")
        #expect(TestTemporaryRoot.root(environment: ["TMPDIR": "/fixture-root/tmp/"], fallback: fallback).path == "/fixture-root/tmp")
    }

    @Test("a missing, empty, blank or relative TMPDIR falls back", arguments: [
        [:], ["TMPDIR": ""], ["TMPDIR": "  "], ["TMPDIR": "tmp"],
    ])
    func fallsBack(environment: [String: String]) {
        #expect(TestTemporaryRoot.root(environment: environment, fallback: fallback) == fallback)
    }

    @Test("the validation helper makes its folder under the root of this process")
    func validationFolderIsUnderTheRoot() throws {
        let directory = try PDFValidation.temporaryDirectory()
        defer {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                Issue.record("the folder could not be removed: \(error)")
            }
        }

        let root = TestTemporaryRoot.url.resolvingSymlinksInPath().path
        #expect(directory.resolvingSymlinksInPath().path.hasPrefix(root), "\(directory.path) is not under \(root)")
    }
}
