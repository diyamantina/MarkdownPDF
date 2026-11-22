public extension MarkdownPDF.Render.Report {
    /// Why a character is not drawn from a face.
    enum Reason: Equatable, Sendable {
        /// No text face is embedded, and the bundled faces are not available either: the resource bundle that holds them is absent from the deployment
        /// (a package that left it out). Every character beyond WinAnsi is affected; the fix is to ship the bundle, or to give the faces in
        /// ``PDFOptions/embeddedFonts``.
        case bundledFacesUnavailable
        /// No text face is embedded, though the bundled faces are available (the caller gave none and the document needed none).
        case noEmbeddedFace
        /// The embedded faces and the colour face are there, and none of them has the character.
        case noFaceHasIt
    }
}
