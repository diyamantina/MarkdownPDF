import Foundation

enum StandardFont: String, CaseIterable {
    case helvetica = "F1"
    case helveticaBold = "F2"
    case helveticaOblique = "F3"
    case courier = "F4"

    func baseName(in fontSet: PDFOptions.FontSet) -> String {
        switch self {
        case .helvetica:
            fontSet.regular
        case .helveticaBold:
            fontSet.bold
        case .helveticaOblique:
            fontSet.italic
        case .courier:
            fontSet.monospaced
        }
    }

    func subtype(in fontSet: PDFOptions.FontSet) -> String {
        fontSet.subtype
    }

    var italicAngle: Int {
        switch self {
        case .helveticaOblique:
            -12
        default:
            0
        }
    }

    func width(
        of text: String,
        size: Double,
        fontSet: PDFOptions.FontSet,
    ) -> Double {
        let widths = widthTable(in: fontSet)

        let units = PDFTextEncoding.portableScalars(for: text).reduce(0) { partialResult, scalar in
            partialResult + widths.width(for: scalar)
        }
        return Double(units) * size / 1000
    }

    func widthsForPDF(in fontSet: PDFOptions.FontSet) -> [Int] {
        let widths = widthTable(in: fontSet)
        // Emit widths across the full WinAnsi byte range (32-255) from the AFM
        // metrics, so every WinAnsi glyph paints at its true advance.
        return (32 ... 255).map { byte in
            widths.width(for: PDFTextEncoding.winAnsiScalar(for: UInt8(byte)))
        }
    }

    private func widthTable(in fontSet: PDFOptions.FontSet) -> WidthTable {
        let baseName = baseName(in: fontSet)
        if self == .courier || baseName.hasPrefix("Courier") || baseName.hasPrefix("SFMono") {
            return FontWidths.courier
        }
        if self == .helveticaBold {
            return FontWidths.helveticaBold
        }
        return FontWidths.helvetica
    }
}

private enum FontWidths {
    static let courier = WidthTable(defaultWidth: 600, widths: [:])

    static let helvetica = WidthTable(defaultWidth: 556, widths: [
        " ": 278, "!": 278, "\"": 355, "#": 556, "$": 556, "%": 889, "&": 667, "'": 191,
        "(": 333, ")": 333, "*": 389, "+": 584, ",": 278, "-": 333, ".": 278, "/": 278,
        "0": 556, "1": 556, "2": 556, "3": 556, "4": 556, "5": 556, "6": 556, "7": 556,
        "8": 556, "9": 556, ":": 278, ";": 278, "<": 584, "=": 584, ">": 584, "?": 556,
        "@": 1015, "A": 667, "B": 667, "C": 722, "D": 722, "E": 667, "F": 611, "G": 778,
        "H": 722, "I": 278, "J": 500, "K": 667, "L": 556, "M": 833, "N": 722, "O": 778,
        "P": 667, "Q": 778, "R": 722, "S": 667, "T": 611, "U": 722, "V": 667, "W": 944,
        "X": 667, "Y": 667, "Z": 611, "[": 278, "\\": 278, "]": 278, "^": 469, "_": 556,
        "`": 333, "a": 556, "b": 556, "c": 500, "d": 556, "e": 556, "f": 278, "g": 556,
        "h": 556, "i": 222, "j": 222, "k": 500, "l": 222, "m": 833, "n": 556, "o": 556,
        "p": 556, "q": 556, "r": 333, "s": 500, "t": 278, "u": 556, "v": 500, "w": 722,
        "x": 500, "y": 500, "z": 500, "{": 334, "|": 260, "}": 334, "~": 584,
    ], highWidths: helveticaWinAnsiHigh)

    static let helveticaBold = WidthTable(defaultWidth: 556, widths: [
        " ": 278, "!": 333, "\"": 474, "#": 556, "$": 556, "%": 889, "&": 722, "'": 238,
        "(": 333, ")": 333, "*": 389, "+": 584, ",": 278, "-": 333, ".": 278, "/": 278,
        "0": 556, "1": 556, "2": 556, "3": 556, "4": 556, "5": 556, "6": 556, "7": 556,
        "8": 556, "9": 556, ":": 333, ";": 333, "<": 584, "=": 584, ">": 584, "?": 611,
        "@": 975, "A": 722, "B": 722, "C": 722, "D": 722, "E": 667, "F": 611, "G": 778,
        "H": 722, "I": 278, "J": 556, "K": 722, "L": 611, "M": 833, "N": 722, "O": 778,
        "P": 667, "Q": 778, "R": 722, "S": 667, "T": 611, "U": 722, "V": 667, "W": 944,
        "X": 667, "Y": 667, "Z": 611, "[": 333, "\\": 278, "]": 333, "^": 584, "_": 556,
        "`": 333, "a": 556, "b": 611, "c": 556, "d": 611, "e": 556, "f": 333, "g": 611,
        "h": 611, "i": 278, "j": 278, "k": 556, "l": 278, "m": 889, "n": 611, "o": 611,
        "p": 611, "q": 611, "r": 389, "s": 556, "t": 333, "u": 611, "v": 556, "w": 778,
        "x": 556, "y": 556, "z": 500, "{": 389, "|": 280, "}": 389, "~": 584,
    ], highWidths: helveticaBoldWinAnsiHigh)

    static let helveticaWinAnsiHigh: [UnicodeScalar: Int] = [
        "\u{00A0}": 278, "\u{00A1}": 333, "\u{00A2}": 556, "\u{00A3}": 556, "\u{00A4}": 556, "\u{00A5}": 556,
        "\u{00A6}": 260, "\u{00A7}": 556, "\u{00A8}": 333, "\u{00A9}": 737, "\u{00AA}": 370, "\u{00AB}": 556,
        "\u{00AC}": 584, "\u{00AD}": 333, "\u{00AE}": 737, "\u{00AF}": 333, "\u{00B0}": 400, "\u{00B1}": 584,
        "\u{00B2}": 333, "\u{00B3}": 333, "\u{00B4}": 333, "\u{00B5}": 556, "\u{00B6}": 537, "\u{00B7}": 278,
        "\u{00B8}": 333, "\u{00B9}": 333, "\u{00BA}": 365, "\u{00BB}": 556, "\u{00BC}": 834, "\u{00BD}": 834,
        "\u{00BE}": 834, "\u{00BF}": 611, "\u{00C0}": 667, "\u{00C1}": 667, "\u{00C2}": 667, "\u{00C3}": 667,
        "\u{00C4}": 667, "\u{00C5}": 667, "\u{00C6}": 1000, "\u{00C7}": 722, "\u{00C8}": 667, "\u{00C9}": 667,
        "\u{00CA}": 667, "\u{00CB}": 667, "\u{00CC}": 278, "\u{00CD}": 278, "\u{00CE}": 278, "\u{00CF}": 278,
        "\u{00D0}": 722, "\u{00D1}": 722, "\u{00D2}": 778, "\u{00D3}": 778, "\u{00D4}": 778, "\u{00D5}": 778,
        "\u{00D6}": 778, "\u{00D7}": 584, "\u{00D8}": 778, "\u{00D9}": 722, "\u{00DA}": 722, "\u{00DB}": 722,
        "\u{00DC}": 722, "\u{00DD}": 667, "\u{00DE}": 667, "\u{00DF}": 611, "\u{00E0}": 556, "\u{00E1}": 556,
        "\u{00E2}": 556, "\u{00E3}": 556, "\u{00E4}": 556, "\u{00E5}": 556, "\u{00E6}": 889, "\u{00E7}": 500,
        "\u{00E8}": 556, "\u{00E9}": 556, "\u{00EA}": 556, "\u{00EB}": 556, "\u{00EC}": 278, "\u{00ED}": 278,
        "\u{00EE}": 278, "\u{00EF}": 278, "\u{00F0}": 556, "\u{00F1}": 556, "\u{00F2}": 556, "\u{00F3}": 556,
        "\u{00F4}": 556, "\u{00F5}": 556, "\u{00F6}": 556, "\u{00F7}": 584, "\u{00F8}": 611, "\u{00F9}": 556,
        "\u{00FA}": 556, "\u{00FB}": 556, "\u{00FC}": 556, "\u{00FD}": 500, "\u{00FE}": 556, "\u{00FF}": 500,
        "\u{0152}": 1000, "\u{0153}": 944, "\u{0160}": 667, "\u{0161}": 500, "\u{0178}": 667, "\u{017D}": 611,
        "\u{017E}": 500, "\u{0192}": 556, "\u{02C6}": 333, "\u{02DC}": 333, "\u{2013}": 556, "\u{2014}": 1000,
        "\u{2018}": 222, "\u{2019}": 222, "\u{201A}": 222, "\u{201C}": 333, "\u{201D}": 333, "\u{201E}": 333,
        "\u{2020}": 556, "\u{2021}": 556, "\u{2022}": 350, "\u{2026}": 1000, "\u{2030}": 1000, "\u{2039}": 333,
        "\u{203A}": 333, "\u{20AC}": 556, "\u{2122}": 1000,
    ]

    static let helveticaBoldWinAnsiHigh: [UnicodeScalar: Int] = [
        "\u{00A0}": 278, "\u{00A1}": 333, "\u{00A2}": 556, "\u{00A3}": 556, "\u{00A4}": 556, "\u{00A5}": 556,
        "\u{00A6}": 280, "\u{00A7}": 556, "\u{00A8}": 333, "\u{00A9}": 737, "\u{00AA}": 370, "\u{00AB}": 556,
        "\u{00AC}": 584, "\u{00AD}": 333, "\u{00AE}": 737, "\u{00AF}": 333, "\u{00B0}": 400, "\u{00B1}": 584,
        "\u{00B2}": 333, "\u{00B3}": 333, "\u{00B4}": 333, "\u{00B5}": 611, "\u{00B6}": 556, "\u{00B7}": 278,
        "\u{00B8}": 333, "\u{00B9}": 333, "\u{00BA}": 365, "\u{00BB}": 556, "\u{00BC}": 834, "\u{00BD}": 834,
        "\u{00BE}": 834, "\u{00BF}": 611, "\u{00C0}": 722, "\u{00C1}": 722, "\u{00C2}": 722, "\u{00C3}": 722,
        "\u{00C4}": 722, "\u{00C5}": 722, "\u{00C6}": 1000, "\u{00C7}": 722, "\u{00C8}": 667, "\u{00C9}": 667,
        "\u{00CA}": 667, "\u{00CB}": 667, "\u{00CC}": 278, "\u{00CD}": 278, "\u{00CE}": 278, "\u{00CF}": 278,
        "\u{00D0}": 722, "\u{00D1}": 722, "\u{00D2}": 778, "\u{00D3}": 778, "\u{00D4}": 778, "\u{00D5}": 778,
        "\u{00D6}": 778, "\u{00D7}": 584, "\u{00D8}": 778, "\u{00D9}": 722, "\u{00DA}": 722, "\u{00DB}": 722,
        "\u{00DC}": 722, "\u{00DD}": 667, "\u{00DE}": 667, "\u{00DF}": 611, "\u{00E0}": 556, "\u{00E1}": 556,
        "\u{00E2}": 556, "\u{00E3}": 556, "\u{00E4}": 556, "\u{00E5}": 556, "\u{00E6}": 889, "\u{00E7}": 556,
        "\u{00E8}": 556, "\u{00E9}": 556, "\u{00EA}": 556, "\u{00EB}": 556, "\u{00EC}": 278, "\u{00ED}": 278,
        "\u{00EE}": 278, "\u{00EF}": 278, "\u{00F0}": 611, "\u{00F1}": 611, "\u{00F2}": 611, "\u{00F3}": 611,
        "\u{00F4}": 611, "\u{00F5}": 611, "\u{00F6}": 611, "\u{00F7}": 584, "\u{00F8}": 611, "\u{00F9}": 611,
        "\u{00FA}": 611, "\u{00FB}": 611, "\u{00FC}": 611, "\u{00FD}": 556, "\u{00FE}": 611, "\u{00FF}": 556,
        "\u{0152}": 1000, "\u{0153}": 944, "\u{0160}": 667, "\u{0161}": 556, "\u{0178}": 667, "\u{017D}": 611,
        "\u{017E}": 500, "\u{0192}": 556, "\u{02C6}": 333, "\u{02DC}": 333, "\u{2013}": 556, "\u{2014}": 1000,
        "\u{2018}": 278, "\u{2019}": 278, "\u{201A}": 278, "\u{201C}": 500, "\u{201D}": 500, "\u{201E}": 500,
        "\u{2020}": 556, "\u{2021}": 556, "\u{2022}": 350, "\u{2026}": 1000, "\u{2030}": 1000, "\u{2039}": 333,
        "\u{203A}": 333, "\u{20AC}": 556, "\u{2122}": 1000,
    ]
}

private struct WidthTable {
    var defaultWidth: Int
    var widths: [UnicodeScalar: Int]

    /// Advances for every WinAnsi scalar outside ASCII, per face. Complete and
    /// exact: generated from the Adobe Core-14 AFM metrics through the WinAnsi
    /// encoding vector, not shared across faces (the bold advances differ from the
    /// regular ones at 31 code points, including the accented capitals and the
    /// curly quotes).
    var highWidths: [UnicodeScalar: Int] = [:]

    /// The advance for `scalar`, which callers pass already reduced to the WinAnsi
    /// set: `PDFTextEncoding.portableScalars` maps any scalar the base-14 fonts
    /// cannot draw to the replacement `?` before measurement, so the tables need to
    /// cover only ASCII and the WinAnsi high range.
    func width(for scalar: UnicodeScalar) -> Int {
        if let width = widths[scalar] {
            return width
        }
        if scalar.value > 0x7F {
            if let width = highWidths[scalar] {
                return width
            }
        }
        return widths["?"] ?? defaultWidth
    }
}
