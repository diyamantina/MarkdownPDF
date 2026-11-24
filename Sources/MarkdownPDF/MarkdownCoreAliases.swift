import ExtendedMarkdownCore

// The Markdown core moved to the package ExtendedMarkdown (the types are written ExtendedMarkdown.Core.<Name> there). These
// aliases keep every name MarkdownPDF has published working: the same types, the same nested types, initializers and cases.

/// See ``ExtendedMarkdown/Core/Parser``.
public typealias MarkdownParser = ExtendedMarkdown.Core.Parser

/// See ``ExtendedMarkdown/Core/Block``.
public typealias MarkdownBlock = ExtendedMarkdown.Core.Block

/// See ``ExtendedMarkdown/Core/Inline``.
public typealias MarkdownInline = ExtendedMarkdown.Core.Inline

/// See ``ExtendedMarkdown/Core/Document``.
public typealias MarkdownDocument = ExtendedMarkdown.Core.Document

/// See ``ExtendedMarkdown/Core/Math``.
public typealias MarkdownMath = ExtendedMarkdown.Core.Math
