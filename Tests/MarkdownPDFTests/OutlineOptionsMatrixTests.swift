import Foundation
@testable import MarkdownPDF
import Testing

/// The two outline options against everything that also writes headings, links or destinations. The oracle is the library's own structure
/// check (`PDFInspector.canonicalStructureIssues`, which follows every outline item, every named destination and every internal link) plus the
/// closed form of what the options promise: which headings are in the outline, and where a heading's destination points.
@Suite("Outline options across features")
struct OutlineOptionsMatrixTests {
    private static let pageHeight = 540.0
    /// Three parts of two slides, a page for each slide, headings at levels one to three, and a link to a level-three heading.
    private static let deck: String = {
        var parts: [String] = []
        for part in ["One", "Two", "Three"] {
            for slide in ["A", "B"] {
                let top = slide == "A" ? "# Part \(part)\n\n" : ""
                let link = part == "One" && slide == "A" ? "\n\nSee [the line](#line-three-b).\n" : ""
                parts.append("\(top)## Slide \(part) \(slide)\n\nA paragraph of the slide.\(link)\n\n### Line \(part) \(slide)")
            }
        }
        return parts.joined(separator: "\n\n<!-- pagebreak -->\n\n") + "\n\n<!-- pagebreak -->\n\n## Slide Three B\n\n### Line Three B\n"
    }()

    /// Every heading of the deck with its level, in order.
    private static let headings: [(level: Int, title: String)] = {
        var result: [(Int, String)] = []
        for line in deck.split(separator: "\n") {
            let hashes = line.prefix { $0 == "#" }.count
            if hashes > 0, line.dropFirst(hashes).first == " " {
                result.append((hashes, String(line.dropFirst(hashes + 1))))
            }
        }
        return result
    }()

    private struct Feature: CustomStringConvertible, Sendable {
        let name: String
        let apply: @Sendable (inout PDFOptions) -> Void
        var description: String {
            name
        }
    }

    private static let features: [Feature] = [
        Feature(name: "plain") { _ in },
        Feature(name: "table of contents") { $0.tableOfContents = PDFOptions.TableOfContents(isEnabled: true, maximumDepth: 6) },
        Feature(name: "contents and page numbers") {
            $0.tableOfContents = PDFOptions.TableOfContents(isEnabled: true, maximumDepth: 3)
            $0.pageNumbers = PDFOptions.PageNumbers(isEnabled: true, format: .ofTotal)
        },
        Feature(name: "index") { $0.index = PDFOptions.Index(isEnabled: true, terms: ["paragraph", "slide"]) },
        Feature(name: "contents and index") {
            $0.tableOfContents = .enabled
            $0.index = PDFOptions.Index(isEnabled: true, terms: ["paragraph"])
        },
        Feature(name: "tagged") { $0.taggedPDF = PDFOptions.TaggedPDF(isEnabled: true, language: "en-US") },
        Feature(name: "PDF/UA-1") {
            $0.title = "Outline deck"
            $0.embeddedFonts = .dejaVu
            $0.taggedPDF = PDFOptions.TaggedPDF(isEnabled: true, language: "en-US")
            $0.conformance = .pdfUA1
        },
        Feature(name: "compressed") { $0.streamCompression = PDFOptions.StreamCompression(isEnabled: true) },
    ]

    private func options(_ feature: Feature, depth: Int, atPageTop: Bool) -> PDFOptions {
        var options = PDFOptions(
            pageSize: PDFOptions.PageSize(width: 960, height: Self.pageHeight),
            margins: PDFOptions.Margins(top: 80, right: 72, bottom: 30, left: 72),
        )
        feature.apply(&options)
        options.outlineMaxHeadingLevel = depth
        options.headingDestinationsAtPageTop = atPageTop
        return options
    }

    /// The headings the library writes itself, level one each: they are in the outline at every depth.
    private static let generatedHeadings: Set<String> = ["Table of Contents", "Index"]

    private func titles(in text: String) -> [String] {
        text.matches(of: /\/Title \(([^)]*)\)/).map { String($0.output.1) }
    }

    /// The outline titles that are the deck's own headings. The document title, written to the metadata as `/Title` too, is not an outline entry.
    private func deckTitles(in text: String, documentTitle: String? = nil) -> [String] {
        titles(in: text).filter { !Self.generatedHeadings.contains($0) && $0 != documentTitle }
    }

    private func headingDestinations(in text: String) -> [(name: String, y: Double)] {
        text.matches(of: /\(([^)]*)\) \[[0-9]+ 0 R \/XYZ [0-9.]+ ([0-9.]+) null\]/).compactMap { match in
            let name = String(match.output.1)
            return name.hasPrefix("mdpdf-") ? nil : (name, Double(match.output.2) ?? -1)
        }
    }

    @Test("every depth, with and without page-top destinations, in every feature: the structure is sound and the outline and destinations follow the options")
    func everyCombination() throws {
        var combinations = 0
        for feature in Self.features {
            for depth in 1 ... 6 {
                for atPageTop in [false, true] {
                    let built = options(feature, depth: depth, atPageTop: atPageTop)
                    let data = try MarkdownPDFRenderer(options: built).render(markdown: Self.deck)
                    let inspector = PDFInspector(data)
                    let label = "\(feature), depth \(depth), page top \(atPageTop)"
                    combinations += 1

                    // Compressed streams hide objects from the text check, so the structure is read only where it is readable.
                    if feature.name != "compressed" {
                        #expect(inspector.canonicalStructureIssues().isEmpty, "\(label): \(inspector.canonicalStructureReport())")
                    }

                    // The outline holds exactly the headings down to the depth, in order, besides the level-one headings the library writes itself.
                    if feature.name != "compressed" {
                        let expected = Self.headings.filter { $0.level <= depth }.map(\.title)
                        let outline = deckTitles(in: inspector.text, documentTitle: built.title)
                        #expect(outline == expected, "\(label): outline \(outline) expected \(expected)")
                    }

                    // Destinations: a heading below the depth is still reachable, and with the option every one is the top of its page.
                    if feature.name != "compressed" {
                        let destinations = headingDestinations(in: inspector.text)
                        #expect(destinations.count >= Self.headings.count, "\(label): \(destinations.count) heading destinations")
                        if atPageTop {
                            #expect(destinations.allSatisfy { $0.y == Self.pageHeight }, "\(label): a destination is not the page top")
                        } else {
                            #expect(destinations.contains { $0.y < Self.pageHeight }, "\(label): negative control, no destination below the top")
                        }
                    }
                }
            }
        }
        #expect(combinations == Self.features.count * 6 * 2)
    }

    @Test("with a table of contents every entry links to a heading destination that exists, also for headings left out of the outline")
    func contentsLinksResolve() throws {
        let data = try MarkdownPDFRenderer(options: options(Self.features[1], depth: 1, atPageTop: true)).render(markdown: Self.deck)
        let inspector = PDFInspector(data)
        #expect(inspector.canonicalStructureIssues().isEmpty, "\(inspector.canonicalStructureReport())")
        #expect(inspector.text.contains("/Subtype /Link"))
        #expect(deckTitles(in: inspector.text) == ["Part One", "Part Two", "Part Three"])
    }
}
