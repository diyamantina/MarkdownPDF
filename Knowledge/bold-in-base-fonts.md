# Bold that looks letter-spaced in an unembedded base font

With the default `fontSet` (`.pdfBase`) a document names Helvetica-Bold but does not embed it, and the text is set with
the Helvetica-Bold advances. A viewer that has no Helvetica-Bold draws a regular face at those advances, which looks
letter-spaced and not bold. The library applies no character or word spacing of its own. MEASURED on an article PDF read
with `PDFDocumentReader` (2026-11-25). A producer that needs the same look in every viewer embeds a bold face
(`BundledFonts.swift` has one).
