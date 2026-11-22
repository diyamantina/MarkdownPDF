import Foundation
@testable import MarkdownPDF
import Testing

/// A character that is not drawn from a face is REPORTED, never replaced silently by a wrong letter. The report names each character (as written, with its
/// code points), why it was not drawn, and how often it occurs; the option `undrawnCharacters = .fail` turns a non-empty report into a thrown error, so a
/// stripped deployment (the resource bundle with the faces left out of a package) fails loudly instead of printing `v` for a check mark.
///
/// A stripped deployment is simulated by giving the renderer no bundled faces (`bundledFaces: .disabled`), which is what its resource lookup returns when
/// the bundle is absent.
@Suite("Undrawn characters are reported, and a strict render fails")
struct UndrawnCharacterReportTests {
    private static let symbols = "```\n\u{2B07}\u{FE0F} Downloading\n\u{2713} Extracted\n\u{1F4E6} Package\n```\n"
    private static let symbolTexts = ["\u{2B07}\u{FE0F}", "\u{2713}", "\u{1F4E6}"]

    private func stripped(_ options: PDFOptions = PDFOptions(mathTypesetting: .enabled)) -> MarkdownPDFRenderer {
        MarkdownPDFRenderer(options: options, bundledFaces: .disabled)
    }

    private func bundled(_ options: PDFOptions = PDFOptions(mathTypesetting: .enabled)) -> MarkdownPDFRenderer {
        MarkdownPDFRenderer(options: options)
    }

    @Test("MEASURED in the test environment: the bundled faces are available")
    func bundledFacesAvailable() {
        #expect(MarkdownPDFRenderer.bundledFacesAreAvailable)
    }

    @Test("a stripped deployment: every symbol of the page is reported, with the reason that the bundled faces are unavailable")
    func strippedReports() throws {
        let output = try stripped().renderWithReport(markdown: Self.symbols)
        let reported = output.report.undrawn.map(\.text)
        for text in Self.symbolTexts {
            #expect(reported.contains(text), Comment(rawValue: "`\(text)` is not reported: \(reported)"))
        }
        for entry in output.report.undrawn {
            #expect(entry.reason == .bundledFacesUnavailable, Comment(rawValue: "\(entry.text): \(entry.reason)"))
            #expect(entry.count == 1)
        }
        #expect(output.report.undrawn.map(\.text) == Self.symbolTexts, "the report is in the order of first appearance, without repeats")
        #expect(output.report.undrawn.first?.codePoints == [0x2B07, 0xFE0F])
    }

    @Test("the render without a report is unchanged byte for byte, and still returns the page")
    func renderUnchanged() throws {
        let plain = try stripped().render(markdown: Self.symbols)
        let withReport = try stripped().renderWithReport(markdown: Self.symbols)
        #expect(plain == withReport.data)
        #expect(!plain.isEmpty)
    }

    @Test("a strict render of a stripped deployment throws, naming what it could not draw")
    func strictThrows() throws {
        var options = PDFOptions(mathTypesetting: .enabled)
        options.undrawnCharacters = .fail
        #expect(throws: MarkdownPDFError.self) { _ = try stripped(options).render(markdown: Self.symbols) }
        do {
            _ = try stripped(options).renderWithReport(markdown: Self.symbols)
            Issue.record("no error")
        } catch let MarkdownPDFError.undrawnCharacters(report) {
            #expect(report.undrawn.map(\.text) == Self.symbolTexts)
        } catch {
            Issue.record("another error: \(error)")
        }
    }

    @Test("with the bundled faces the same page has an empty report, and a strict render succeeds")
    func bundledIsClean() throws {
        let output = try bundled().renderWithReport(markdown: Self.symbols)
        #expect(output.report.undrawn.isEmpty, Comment(rawValue: "\(output.report.undrawn.map(\.text))"))
        var options = PDFOptions(mathTypesetting: .enabled)
        options.undrawnCharacters = .fail
        _ = try bundled(options).render(markdown: Self.symbols)
    }

    @Test("a page of ASCII and WinAnsi text has an empty report in both deployments")
    func plainIsClean() throws {
        let markdown = "# Title\n\nCaf\u{E9} \u{2014} it\u{2019}s fine.\n\n```\nlet x = 1\n```\n"
        #expect(try bundled().renderWithReport(markdown: markdown).report.undrawn.isEmpty)
        #expect(try stripped().renderWithReport(markdown: markdown).report.undrawn.isEmpty)
    }

    @Test("a character no bundled face has is reported with the reason that no face has it, and counted")
    func noFaceHasIt() throws {
        // A CJK ideograph: not in the proportional, monospaced or colour faces.
        let output = try bundled().renderWithReport(markdown: "one \u{4E2D}\n\n`\u{4E2D}` and \u{4E2D}\n")
        let entry = output.report.undrawn.first { $0.text == "\u{4E2D}" }
        #expect(entry?.reason == .noFaceHasIt, Comment(rawValue: "\(output.report.undrawn)"))
        #expect(entry?.count == 3, Comment(rawValue: "\(entry?.count ?? -1)"))
    }

    @Test("the report is the same on a second run, byte for byte")
    func deterministic() throws {
        let first = try stripped().renderWithReport(markdown: Self.symbols).report
        let second = try stripped().renderWithReport(markdown: Self.symbols).report
        #expect(first == second)
    }
}
