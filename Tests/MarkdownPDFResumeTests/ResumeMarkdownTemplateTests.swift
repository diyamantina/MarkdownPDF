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
