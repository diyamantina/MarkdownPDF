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
}
