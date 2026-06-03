# Source snapshot policy

Source snapshots are allowed as research evidence. They are not implementation
dependencies and they do not change the product boundary.

## Purpose

Source snapshots help answer concrete design questions:

- How mature PDF writers structure catalog, page tree, page, resource, font,
  image, stream, outline, and metadata objects.
- How existing projects validate xref tables, trailer dictionaries, stream
  lengths, and object references.
- Which implementation ideas can be translated into Pure Swift.
- Which ideas depend on platform APIs, native libraries, or toolchains that this
  package must not depend on.

## Where the snapshots live

The full set of study-only source snapshots (33 projects) lives in the private
companion repository
[mihaelamj/MarkdownPDFResearch](https://github.com/mihaelamj/MarkdownPDFResearch),
which keeps this public repository small and correctly classified as Swift. Only
a small, high-signal subset is retained locally under `researchcode/` (currently
`pydyf`, `unicode-linebreak`, `unicode-bidi`, `libdeflate`, and `zlib`).

Citations elsewhere in these research notes that reference a
`researchcode/<project>/...` path not present in the local subset resolve to the
same relative path inside the private `MarkdownPDFResearch` repository.

## Repository boundary

- Source snapshots live under `researchcode/` (local subset) or in the private
  `MarkdownPDFResearch` repository (full set).
- Snapshots are not Swift package targets.
- Product source and tests must not import, compile, shell out to, or link
  snapshot code.
- The implementation path is to study concepts, then write native Swift that
  follows MarkdownPDF rules.
- Public source snapshots must retain upstream license files where available.
- Nested Git repositories must be removed before tracking snapshots.

## Provenance checklist

For every source snapshot batch, record:

- Upstream project name.
- Upstream URL.
- License file location.
- Snapshot date.
- Why the project is relevant to MarkdownPDF.
- Which findings were useful enough to save in `docs/research/`.

## Security and binary artifacts

- Do not add private keys, tokens, credentials, private archives, or private
  source.
- Treat signing certificates, strong-name keys, and similar files from public
  upstream tests as credential-like artifacts. Keep them only when there is a
  specific research reason and the provenance is documented.
- Do not use upstream test credentials in MarkdownPDF tests or tooling.

## Platform notes

- Portable findings must be implementable on macOS and Linux with Swift and
  Foundation.
- macOS-specific findings must be labeled macOS-specific.
- iOS support must not be implied. It requires explicit implementation and tests.

## How research becomes implementation

1. Save the useful finding in `docs/research/`.
2. Translate the idea into a small Swift design that preserves direct PDF byte
   generation.
3. Add tests that inspect generated PDF structure or validate output with open
   source tools.
4. Keep platform-specific behavior behind an explicit target or seam.
5. Update the generated output profile when behavior changes.
