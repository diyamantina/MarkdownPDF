import Foundation

public extension PDFOptions.Index {
    /// One term-list entry with its variant forms: every form is searched for, and
    /// all of them record their pages under one ``heading``.
    ///
    /// The text form is the string used in ``PDFOptions/Index/terms``, term files and
    /// manifests: forms separated by a pipe, the first form being the heading.
    ///
    /// ```swift
    /// let term = try PDFOptions.Index.Term(parsing: "flattening|flatten|flattens|flattened")
    /// term.heading   // "flattening"
    /// term.variants  // ["flatten", "flattens", "flattened"]
    /// ```
    ///
    /// ## Rules
    ///
    /// - The first form is the heading printed in the index. Every form, the
    ///   heading included, is matched as a whole word or whole phrase, ignoring case
    ///   and diacritics, in the same places as a term without variants. A page that
    ///   holds several forms is listed once under the heading.
    /// - White space around a form is trimmed.
    /// - An empty form is an error: `a||b`, `|a`, `a|` and `|` all throw
    ///   ``MarkdownPDFError/indexTermEmptyForm(term:)``. So does a blank text
    ///   given to ``init(parsing:)``.
    /// - A form that repeats an earlier form, ignoring case, diacritics and white
    ///   space, is dropped.
    /// - A literal pipe inside a form is written `\|`. A backslash is an escape only
    ///   before a pipe; anywhere else it is an ordinary character.
    /// - A text without a pipe is one form with no variants, exactly the term it has
    ///   always been.
    /// - Only the heading may use the `main > sub` sub-entry syntax. Later forms are
    ///   the texts to search for under that same sub-entry, and a `>` in them is
    ///   ordinary text.
    /// - The same form under two different headings records under both headings.
    struct Term: Equatable, Sendable {
        /// The first form: the text printed in the index (or `main > sub`).
        public var heading: String
        /// The other forms, in order, without duplicates.
        public var variants: [String]

        public init(heading: String, variants: [String] = []) {
            self.heading = heading
            self.variants = variants
        }

        /// Parses the pipe-separated text form.
        ///
        /// - Throws: ``MarkdownPDFError/indexTermEmptyForm(term:)`` when any form is
        ///   empty after trimming.
        public init(parsing text: String) throws {
            var forms: [String] = []
            var seen = Set<String>()
            for form in Self.split(text) {
                let trimmed = form.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw MarkdownPDFError.indexTermEmptyForm(term: text)
                }
                let key = String(String.UnicodeScalarView(IndexCollation.fold(trimmed)))
                if seen.insert(key).inserted {
                    forms.append(trimmed)
                }
            }
            // `split` always returns at least one form, and the first is never dropped.
            heading = forms.first ?? ""
            variants = Array(forms.dropFirst())
        }

        /// The heading followed by the variants.
        public var forms: [String] {
            [heading] + variants
        }

        /// The text form of this term, with every literal pipe escaped, so that
        /// `Term(parsing: term.text)` gives the same term back.
        public var text: String {
            forms.map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: "|")
        }

        /// Splits at every pipe that is not escaped as `\|`, and unescapes the rest.
        private static func split(_ text: String) -> [String] {
            var forms: [String] = []
            var current = String.UnicodeScalarView()
            var iterator = text.unicodeScalars.makeIterator()
            var pending = iterator.next()
            while let scalar = pending {
                pending = iterator.next()
                if scalar == "\\", pending == "|" {
                    current.append("|")
                    pending = iterator.next()
                } else if scalar == "|" {
                    forms.append(String(current))
                    current = String.UnicodeScalarView()
                } else {
                    current.append(scalar)
                }
            }
            forms.append(String(current))
            return forms
        }
    }
}
