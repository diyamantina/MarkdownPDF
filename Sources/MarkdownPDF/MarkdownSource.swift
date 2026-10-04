import Foundation

/// One Markdown document of a merged render, with the folder its relative images
/// resolve against.
///
/// Pass an array of sources to ``MarkdownPDFRenderer/render(sources:startsEachSourceOnNewPage:)``
/// to produce a single PDF. Because every source keeps its own base, the
/// `![alt](../figures/a.png)` paths of different files need no rewriting.
public struct MarkdownSource: Equatable, Sendable {
    /// The Markdown text.
    public var markdown: String

    /// The folder relative image paths in `markdown` resolve against. When nil, the
    /// current working directory is used, as for a single-document render.
    public var assetsBaseURL: URL?

    /// A label for the source, such as its file name. It is carried for callers and
    /// diagnostics and is not drawn into the PDF.
    public var name: String?

    public init(markdown: String, assetsBaseURL: URL? = nil, name: String? = nil) {
        self.markdown = markdown
        self.assetsBaseURL = assetsBaseURL
        self.name = name
    }
}
