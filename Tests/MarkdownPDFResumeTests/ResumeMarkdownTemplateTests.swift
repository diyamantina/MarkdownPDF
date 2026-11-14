import Foundation
import MarkdownPDF
import MarkdownPDFResume
import Testing

@Suite("Resume Markdown template")
struct ResumeMarkdownTemplateTests {
    @Test("Renders structured resume Markdown")
    func rendersStructuredResumeMarkdown() throws {
        let resume = try demoResume()
        let markdown = ResumeMarkdownTemplate().markdown(for: resume)

        #expect(markdown.contains("# Alex Rivera"))
        #expect(markdown.contains("## EXPERIENCE"))
        #expect(markdown.contains("### [Northbridge Systems](https://example.com/northbridge) (Sep 2025 - Present), Senior Mobile Architect"))
        #expect(markdown.contains("#### Identity Capture Platform"))
        #expect(markdown.contains("**Technologies:** Swift, SwiftUI, UIKit, Swift Package Manager, Unit Testing"))
        #expect(markdown.contains("## SKILLS"))
        #expect(markdown.contains("**Languages:** Swift, Objective-C\n\n**Frameworks:** SwiftUI, UIKit, AppKit"))
    }

    @Test("Generated resume Markdown renders through generic PDF renderer")
    func generatedResumeMarkdownRendersThroughGenericRenderer() throws {
        let resume = try demoResume()
        let markdown = ResumeMarkdownTemplate().markdown(for: resume)
        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.hasPrefix("%PDF-1.4"))
        #expect(text.contains("/Subtype /Link"))
        #expect(text.contains("/URI (https://example.com/northbridge)"))
    }

    @Test("Escapes structured resume fields before emitting Markdown")
    func escapesStructuredResumeFieldsBeforeEmittingMarkdown() throws {
        let resume = ResumeDocument(
            basics: ResumeDocument.Basics(
                name: "# Alex [Rivera]",
                headline: "1. Lead *Architect*",
                location: "Example | City",
                email: "alex@example.com",
                links: [
                    ResumeDocument.Link(label: "Git[Hub]", url: "https://example.com/profile(1)"),
                ],
            ),
            summary: [
                "- not a list",
                "# not a heading",
            ],
            experience: [
                ResumeDocument.Experience(
                    organization: "Northbridge [Systems]",
                    url: "https://example.com/company(a)",
                    location: "> Remote",
                    title: "Senior *Architect*",
                    start: "Sep 2025",
                    end: "Present",
                    highlights: [
                        "*not emphasis*",
                        "1. not ordered",
                    ],
                    technologies: [
                        "Swift|UI",
                        "C++",
                    ],
                ),
            ],
            skills: [
                ResumeDocument.SkillGroup(
                    name: "Core|Skills",
                    items: ["A*B", "Tables | Markdown"],
                ),
            ],
            sections: [
                ResumeDocument.Section(
                    title: "Research",
                    entries: [
                        ResumeDocument.Entry(
                            title: "Open [Source]",
                            subtitle: "*Maintainer*",
                            details: ["[literal]"],
                            technologies: ["Docs|PDF"],
                        ),
                    ],
                ),
            ],
        )

        let markdown = ResumeMarkdownTemplate().markdown(for: resume)
        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let text = String(decoding: data, as: UTF8.self)

        #expect(markdown.contains("# \\# Alex \\[Rivera\\]"))
        #expect(markdown.contains("## 1\\. Lead \\*Architect\\*"))
        #expect(markdown.contains("[Northbridge \\[Systems\\]](https://example.com/company%28a%29)"))
        #expect(markdown.contains("- \\*not emphasis\\*"))
        #expect(markdown.contains("- 1\\. not ordered"))
        #expect(markdown.contains("**Core\\|Skills:** A\\*B, Tables \\| Markdown"))
        #expect(markdown.contains("### Open \\[Source\\] (\\*Maintainer\\*)"))
        #expect(markdown.contains("- \\[literal\\]"))
        #expect(markdown.contains("**Technologies:** Docs\\|PDF"))
        #expect(text.contains("/URI (https://example.com/company%28a%29)"))
        #expect(text.contains("/URI (https://example.com/profile%281%29)"))
    }

    @Test("The contact line shows the email address, linked to mailto")
    func contactLineShowsTheEmailAddress() throws {
        let plain = ResumeDocument(basics: ResumeDocument.Basics(name: "Ana", email: "ana_marija@example.com"))
        let prefixed = ResumeDocument(basics: ResumeDocument.Basics(name: "Ana", email: "mailto:ana@example.com"))

        let markdown = ResumeMarkdownTemplate().markdown(for: plain)
        #expect(markdown.contains("[ana\\_marija@example.com](mailto:ana_marija@example.com)"))
        #expect(!markdown.contains("[Email]"))
        #expect(ResumeMarkdownTemplate().markdown(for: prefixed).contains("[ana@example.com](mailto:ana@example.com)"))

        // The address is on the page and the link still opens the mail program.
        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("ana_marija@example.com) Tj"))
        #expect(text.contains("/URI (mailto:ana_marija@example.com)"))

        // The address is literal even when fields are read as Markdown.
        let inline = ResumeMarkdownTemplate(options: ResumeMarkdownTemplate.Options(fieldSyntax: .markdown)).markdown(for: plain)
        #expect(inline.contains("[ana\\_marija@example.com](mailto:ana_marija@example.com)"))
    }

    @Test("Fields are plain text unless the template is told they are Markdown")
    func fieldsArePlainTextByDefault() {
        #expect(ResumeMarkdownTemplate.Options().fieldSyntax == .plainText)
        let resume = ResumeDocument(
            basics: ResumeDocument.Basics(name: "Ana"),
            summary: ["Wrote **the** [post](https://example.com/post)."],
        )
        let markdown = ResumeMarkdownTemplate().markdown(for: resume)
        #expect(markdown.contains("Wrote \\*\\*the\\*\\* \\[post\\]\\(https://example.com/post\\)."))
    }

    @Test("Markdown fields keep links, bold, italics and code")
    func markdownFieldsKeepInlineSyntax() throws {
        let resume = ResumeDocument(
            basics: ResumeDocument.Basics(name: "Ana *Marija*", headline: "Architect, `Swift`", location: "Zagreb"),
            summary: ["Wrote **the** [post](https://example.com/post)."],
            experience: [
                ResumeDocument.Experience(
                    organization: "Northbridge",
                    title: "Lead",
                    start: "2024",
                    end: "Present",
                    summary: "Built [Cupertino](https://example.com/cupertino).",
                    highlights: ["Shipped **1.5.0** with _offline_ search"],
                    technologies: ["`SwiftUI`"],
                ),
            ],
            skills: [ResumeDocument.SkillGroup(name: "Tools", items: ["[Xcode](https://example.com/xcode)"])],
        )
        let template = ResumeMarkdownTemplate(options: ResumeMarkdownTemplate.Options(fieldSyntax: .markdown))
        let markdown = template.markdown(for: resume)

        #expect(markdown.contains("# Ana *Marija*"))
        #expect(markdown.contains("## Architect, `Swift`"))
        #expect(markdown.contains("Wrote **the** [post](https://example.com/post)."))
        #expect(markdown.contains("Built [Cupertino](https://example.com/cupertino)."))
        #expect(markdown.contains("- Shipped **1.5.0** with _offline_ search"))
        #expect(markdown.contains("**Technologies:** `SwiftUI`"))
        #expect(markdown.contains("**Tools:** [Xcode](https://example.com/xcode)"))

        // The links are real annotations, and the syntax is not on the page.
        let data = try MarkdownPDFRenderer().render(markdown: markdown)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("/URI (https://example.com/post)"))
        #expect(text.contains("/URI (https://example.com/cupertino)"))
        #expect(text.contains("/URI (https://example.com/xcode)"))
        #expect(!text.contains("**"))
        #expect(!text.contains("]\\("))
    }

    @Test("A Markdown field cannot start a block or span lines", arguments: [
        ("# not a heading", "\\# not a heading"),
        ("- not a list", "\\- not a list"),
        ("+ not a list", "\\+ not a list"),
        ("* not a list", "\\* not a list"),
        ("> not a quote", "\\> not a quote"),
        ("1. not ordered", "1\\. not ordered"),
        ("2) not ordered", "2\\) not ordered"),
        ("***", "\\***"),
        ("- - -", "\\- - -"),
        ("___", "\\___"),
        ("=== not a setext line", "\\=== not a setext line"),
        ("```swift", "\\```swift"),
        ("~~~", "\\~~~"),
        ("first\n# second", "first # second"),
        ("**bold** start", "**bold** start"),
        ("*emphasis* start", "*emphasis* start"),
        ("_emphasis_ start", "_emphasis_ start"),
        ("1.5 years", "1.5 years"),
    ])
    func markdownFieldsCannotStartABlock(field: String, expected: String) {
        let resume = ResumeDocument(basics: ResumeDocument.Basics(name: "Ana"), summary: [field])
        let template = ResumeMarkdownTemplate(options: ResumeMarkdownTemplate.Options(fieldSyntax: .markdown))
        let lines = template.markdown(for: resume).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        #expect(lines == ["# Ana", expected])
    }

    @Test("A Markdown title that already holds a link is not wrapped in a second link")
    func markdownTitleWithItsOwnLinkIsNotLinkedAgain() {
        let resume = ResumeDocument(
            basics: ResumeDocument.Basics(name: "Ana"),
            projects: [
                ResumeDocument.Project(name: "[XRay](https://example.com/xray) Viewer", url: "https://example.com/other"),
                ResumeDocument.Project(name: "**OneGraph**", url: "https://example.com/onegraph"),
            ],
        )
        let template = ResumeMarkdownTemplate(options: ResumeMarkdownTemplate.Options(fieldSyntax: .markdown))
        let markdown = template.markdown(for: resume)

        #expect(markdown.contains("### [XRay](https://example.com/xray) Viewer\n"))
        #expect(markdown.contains("### [**OneGraph**](https://example.com/onegraph)\n"))
    }

    @Test("Croatian letters pass through the template untouched")
    func diacriticsPassThrough() {
        let resume = ResumeDocument(
            basics: ResumeDocument.Basics(name: "Mihaela Mihaljević Jakić", location: "Čakovec, Šibenik, Žminj, Đakovo"),
            summary: ["ć č š ž đ Ć Č Š Ž Đ"],
        )
        for syntax in [ResumeMarkdownTemplate.Options.FieldSyntax.plainText, .markdown] {
            let markdown = ResumeMarkdownTemplate(options: ResumeMarkdownTemplate.Options(fieldSyntax: syntax)).markdown(for: resume)
            #expect(markdown.contains("# Mihaela Mihaljević Jakić"))
            #expect(markdown.contains("Čakovec, Šibenik, Žminj, Đakovo"))
            #expect(markdown.contains("ć č š ž đ Ć Č Š Ž Đ"))
        }
    }

    @Test("Decodes omitted arrays as empty values")
    func decodesOmittedArraysAsEmptyValues() throws {
        let json = """
        {
          "basics": {
            "name": "Alex Rivera"
          },
          "skills": [
            {
              "name": "Languages"
            }
          ]
        }
        """
        let resume = try JSONDecoder().decode(
            ResumeDocument.self,
            from: Data(json.utf8),
        )

        #expect(resume.summary.isEmpty)
        #expect(resume.experience.isEmpty)
        #expect(resume.basics.links.isEmpty)
        #expect(resume.skills == [ResumeDocument.SkillGroup(name: "Languages", items: [])])
        #expect(ResumeMarkdownTemplate().markdown(for: resume).contains("## SKILLS") == false)
    }

    private func demoResume() throws -> ResumeDocument {
        let testFile = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/democv.json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(ResumeDocument.self, from: data)
    }
}
