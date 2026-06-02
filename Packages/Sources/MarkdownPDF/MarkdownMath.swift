import Foundation

public struct MarkdownMath: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case inline
        case display
    }

    public var source: String
    public var mode: Mode

    public init(source: String, mode: Mode) {
        self.source = source
        self.mode = mode
    }

    public var delimitedSource: String {
        switch mode {
        case .inline:
            "$\(source)$"
        case .display:
            "$$\n\(source)\n$$"
        }
    }
}
