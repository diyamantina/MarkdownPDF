import Foundation

public enum MarkdownInline: Equatable, Sendable {
    case text(String)
    case softBreak
    case lineBreak
    case code(String)
    case inlineMath(MarkdownMath)
    case emphasis([MarkdownInline])
    case strong([MarkdownInline])
    case strikethrough([MarkdownInline])
    case link(children: [MarkdownInline], destination: String, title: String?)
    case image(alt: String, source: String, title: String?)
    case footnoteReference(label: String)
    /// An invisible `{{index: term}}` marker. It draws nothing and records the page
    /// it lands on for the back-of-book index. `term` is trimmed, non-empty, and may
    /// hold a `main > sub` pair. Produced only when
    /// ``MarkdownParser/Options/indexMarkers`` is set.
    case indexMarker(term: String)
}
