import Foundation

public extension PDFOptions {
    /// How the document's own text strings are written.
    ///
    /// These are the strings a reader shows outside the page: the Info dictionary
    /// `/Title` and `/Author`, the title of every outline entry, and the alternate
    /// description of an image in a tagged PDF. Page text is not affected, and
    /// neither is the XMP packet, which is UTF-8 in both modes.
    ///
    /// The default value is ``unicode``, which keeps every character. A string made
    /// only of ASCII is written exactly as ``winAnsi`` writes it. Any other string is
    /// written as a PDF text string in UTF-16BE with a byte order mark (ISO 32000-1,
    /// 7.9.2.2), after canonical composition, so a decomposed diacritic is stored
    /// precomposed, and a heading that starts with an emoji and holds an em dash reaches the
    /// outline of a viewer whole.
    ///
    /// ``winAnsi`` is the output of versions before 0.16.0, byte for byte: a character
    /// with no WinAnsi byte is replaced by an ASCII stand-in or by `?`, so a heading
    /// such as `Mihaljević` reaches the outline as `Mihaljevi?`, and a character such as
    /// the em dash, whose byte means another letter in the encoding a reader assumes for
    /// these strings, is shown as that letter.
    enum DocumentStrings: Equatable, Sendable {
        /// WinAnsi bytes, with a stand-in for anything WinAnsi cannot hold. The
        /// output of earlier versions.
        case winAnsi

        /// ASCII strings as before, every other string as UTF-16BE.
        case unicode
    }
}
