# Complex script fixture and witness policy

Status: done through PR #89 on 2026-06-01.

Scope: this policy defines the fixture and validation bar before MarkdownPDF can
claim any complex-script, bidi, ligature, combining-mark, or no-space line-break
support. It is portable macOS and Linux research. It is not a macOS-only plan,
not an iOS claim, and not implementation code.

## Product boundary

The shared renderer remains Swift-only and Linux-buildable. Fixture policy may
describe external tools used by tests, but implementation must still generate
PDF bytes directly in Swift and must not depend on CoreText, CoreGraphics,
AppKit, UIKit, PDFKit, WebKit, browser renderers, LaTeX, JavaScript, Python,
shell renderers, HarfBuzz, or C PDF/Markdown/shaping libraries.

macOS-only measurements can be kept as adapter research, but they are not
portable evidence. macOS results do not imply Linux behavior and do not imply
iOS support. iOS support remains unclaimed until an explicit iOS target and
witness suite exist.

## Fixture principles

Every future behavior issue must name the script and feature it claims. A broad
"Unicode shaping" claim is not acceptable.

Fixtures must be small, deterministic, and repository-safe:

- Do not commit font binaries.
- Prefer generated Swift fixture data for synthetic fonts and tiny documents.
- For smoke tests that need real open fonts, read font paths from environment
  variables or CI-installed system fonts.
- Keep source text expectations separate from visual ordering expectations.
- Keep unsupported inputs as fixtures too, because visible fallback and typed
  errors are part of the product behavior.

## Required fixture groups

| Group | Feature pressure | Required expected data | Minimum future support claim |
|---|---|---|---|
| Latin combining marks | Multiple scalars can share one positioned cluster. | Source scalar sequence, expected extraction text, character quad policy. | Combining sequence preserves source extraction and does not overlap quads. |
| Latin ligatures | Multiple scalars can map to one glyph. | Source scalar sequence, glyph cluster expectation, ToUnicode sequence. | Ligature glyph extracts as the original scalar sequence. |
| Arabic or equivalent joining script | Contextual joining, direction, marks, and mixed numbers. | Logical source text, expected visual run order, extraction policy, unsupported-control policy. | Supported subset renders only after bidi and shaping witnesses pass on macOS and Linux. |
| Hebrew or equivalent RTL script | RTL runs mixed with LTR words, punctuation, and numbers. | Logical source text, expected visual order, extraction policy, number policy. | Visual order and extraction expectations are explicit and witnessed. |
| Indic script | Reordering, conjuncts, matras, and combining behavior. | Cluster mapping cases for many-to-one, one-to-many, and many-to-many mappings. | Shaped cluster model proves mappings before PDF emission. |
| Thai or Khmer | No-space line-break opportunities. | Legal break positions, illegal break positions, line selection expectations. | UAX #14 break opportunities are tested before layout changes. |
| Unsupported controls, missing glyphs, shaping features, or fonts | Inputs outside the supported profile. | Expected typed error, replacement-glyph profile, or visible fallback marker. | Unsupported input never silently renders as broken text. |

Fixture text may be stored later as escaped Unicode scalar sequences when that
keeps source review precise. This policy intentionally does not add those
fixtures yet.

## Witness stack

Each future fixture that changes generated PDF output needs evidence matching
the claim:

- `qpdf` validates structure with no warnings.
- Swift structural checks validate object graph invariants, resources, stream
  lengths, page dictionaries, fonts, images, and annotations.
- Poppler `pdftotext` validates extracted text.
- Poppler `pdftotext -tsv` validates word and line geometry where the output has
  word-like units.
- MuPDF structured text validates character quads and glyph positioning.
- Poppler and MuPDF raster comparison validates comparable ink bounds.
- macOS and Linux both run the same portable witness suite for shared renderer
  claims.

Visual order and extraction order are separate facts. A fixture can require a
visual run order for drawing while still requiring source-faithful extraction
through ToUnicode. Future issues must state both expectations before code
changes.

## Failure policy

Unsupported scripts, bidi controls, missing glyphs, OpenType shaping features,
and font formats must not become quietly bad PDFs. Future implementation issues
must choose one of these behaviors per input class:

- Throw a typed error with an actionable recovery suggestion.
- Render an explicit visible fallback marker that extraction can also witness.
- Keep the text in the existing replacement-glyph profile if that profile is
  intentionally documented for the input.

Silent broken shaping, missing marks, invalid bidi order, overlapped glyphs, or
lost source extraction are not acceptable fallback behaviors.

## Artifact policy

Rendered PDFs, TSV output, structured text, raster outputs, and comparison
reports should remain test artifacts unless the repo explicitly adds a small
fixture file. Generated artifacts should be reproducible from Swift tests and
should not be hand-edited.

When a future issue stores artifact snapshots, the snapshot must state:

- Which tool produced it.
- Which platform produced it.
- Whether it is portable evidence or platform-specific research.
- Which exact behavior claim it proves.

## Next implementation gate

#82 may start modeling shaped clusters only after this policy is treated as the
minimum witness contract. If a future feature cannot meet this bar, the feature
must stay unsupported or visibly fallback.
