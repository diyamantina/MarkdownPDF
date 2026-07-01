# PDF Type Modeling Policy

Date: 2026-06-01

MarkdownPDF writes PDF bytes directly in Swift. New PDF model types must keep
that boundary explicit, portable, deterministic, and testable.

## Definition

A new PDF type is an internal Swift model for a concrete PDF structure that
MarkdownPDF emits, validates, or composes. Examples include a catalog dictionary,
a page dictionary, a link annotation, a metadata stream, an outline tree, a named
destination tree, a font descriptor, or a content stream operator.

A new PDF type is not a product split, a public renderer API, a platform target,
or a dependency wrapper. It exists to model PDF structure in Swift before the
serializer writes bytes.

## Policy

- New PDF model types are internal by default. Keep the public surface small and
  expose configuration only through `PDFOptions` or renderer APIs when users need
  it.
- Use one top-level PDF concept per file. The filename should name the PDF
  concept or invariant being modeled, such as `PDFDocumentCatalog`,
  `PDFPageDictionary`, `PDFDocumentMetadata`, or `PDFDocumentOutline`.
- Model real PDF structures, not convenience text snippets. A new type should
  emit `PDFSyntax.Dictionary`, `PDFSyntax.Array`, `PDFSyntax.Stream`, or typed
  content stream operators.
- Prefer typed PDF syntax values over raw string assembly. Raw strings are
  acceptable only for stream bytes where the stream format itself is textual.
- Keep output deterministic. Do not add current dates, random IDs,
  nondeterministic object ordering, or platform-specific metadata.
- Add a type when it removes raw PDF string assembly, makes invalid PDF states
  harder to construct, or matches an already emitted PDF object family. Do not
  add an abstraction only to reserve space for future features.
- Keep the core portable across macOS and Linux. Do not use Apple APIs, PDFKit,
  CoreGraphics, WebKit, browser renderers, JavaScript, Python, shell renderers,
  LaTeX, or C Markdown/PDF libraries in source, tests, or tooling.
- State platform scope when documenting a type. The default is portable
  macOS/Linux. Anything macOS-only must say macOS-only and must not be pulled
  into the portable core. macOS-only never implies iOS support.
- Every new emitted structure needs Swift tests that inspect the PDF structure
  and Linux-safe external validation where a standard open source tool can
  provide meaningful errors.

## Review Checklist

Before adding a new PDF type:

- Can the invalid PDF state be made harder to construct by this type?
- Does the type correspond to a named PDF structure or operator family?
- Does serialization use `PDFSyntax` values or typed content operators at the
  byte boundary?
- Is object ordering deterministic?
- Does it build without Apple-only APIs and without new non-Swift renderers or
  PDF libraries?
- Do tests fail if the emitted object is malformed, dangling, or missing?

## Current Application

Issue #26 follows this policy by adding internal typed models for deterministic
document metadata, named heading destinations, and outline objects. The visible
generated ToC remains a later layout feature tracked in #36.
