import Foundation

public struct PDFColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let black = PDFColor(red: 0, green: 0, blue: 0)
    public static let white = PDFColor(red: 1, green: 1, blue: 1)
    public static let link = PDFColor(red: 0.05, green: 0.24, blue: 0.62)
    public static let gray = PDFColor(red: 0.35, green: 0.35, blue: 0.35)
    static let sourceCodeKeyword = PDFColor(red: 0.05, green: 0.2, blue: 0.55)
    static let sourceCodeString = PDFColor(red: 0.5, green: 0.18, blue: 0.05)
    static let sourceCodeNumber = PDFColor(red: 0.34, green: 0.18, blue: 0.55)
    static let sourceCodeComment = PDFColor(red: 0.28, green: 0.38, blue: 0.28)
    static let sourceCodeOperator = PDFColor(red: 0.18, green: 0.22, blue: 0.26)
    static let sourceCodePunctuation = PDFColor(red: 0.2, green: 0.2, blue: 0.2)
}
