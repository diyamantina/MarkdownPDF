# macOS PDF renderer research

Direction update on 2026-05-31: this note is historical macOS API research. The
current implementation focus is a pure-Swift renderer that works on Linux and
macOS without depending on Apple frameworks. Apple APIs remain possible optional
backend research, not the primary architecture.

This note records the first research pass for GitHub issues #3 and #11.
It focuses on the planned `MarkdownPDFMac` renderer for scientific and
technical articles.

## Scope

Useful findings from this epic are stored here so the durable record lives in
the repo, not only in GitHub issue comments. This file is a research note, not a
DocC catalog article, because it intentionally cites local private research
paths requested by the tracking issues.

Loaded rule inputs:

- `docs/rules/README.md` and the always-relevant repo rules.
- `/Volumes/Code/DeveloperExt/private/mihaela-agents/Rules/swift/gof-di-rules.md`
- `/Volumes/Code/DeveloperExt/private/mihaela-agents/Rules/universal/first-principles-analysis.md`

Applied constraints:

- Keep the portable `MarkdownPDF` and `MarkdownPDFLinux` path Linux-buildable.
- Keep Apple frameworks isolated to the macOS-only target.
- Do not bundle font files in this public repo.
- Do not use PDFKit, WebKit, browser drivers, LaTeX, JavaScript renderers, or C
  PDF/Markdown libraries.
- Distinguish macOS-only facts from iOS-compatible, broader Apple-platform, and
  cross-platform facts.

## Current repo state

STRUCTURAL: `Packages/Package.swift:5-25` conditionally declares
`MarkdownPDFMac` only when SwiftPM evaluates the manifest on macOS. Linux gets an
empty `macProducts`, `macTargets`, and `macTestDependencies`.

STRUCTURAL: `Packages/Sources/MarkdownPDFMac/MarkdownPDFMacRenderer.swift:1-20`
currently imports only `Foundation` and `MarkdownPDF`. It delegates to
`MarkdownPDFRenderer` and does not yet use CoreGraphics, CoreText, or ImageIO.

STRUCTURAL: `Packages/Tests/MarkdownPDFTests/MarkdownPDFRendererTests.swift:54-63`
only verifies that the mac product entry point returns the portable PDF output
shape. It currently expects `%PDF-1.4` and no embedded font files.

Implication: native Quartz generation is planned work. It is not present in this
checkout yet.

## Measurement log

MEASURED on 2026-05-31:

- Command: `wc -l` on the local book source files.
- Result:
  - `/Volumes/Code/DeveloperExt/private/mihaela-books/core-animation/Sources/Programming with Quartz (2005).md`: 3 lines.
  - `/Volumes/Code/DeveloperExt/private/mihaela-books/core-animation/Sources/Quartz 2D Graphics for Mac OS X Developers.md`: 3 lines.
  - `/Volumes/Code/DeveloperExt/private/mihaela-books/core-animation/Book/3.1 Core Graphics (Quartz 2D): The Software Workhorse.md`: 36 lines.
  - `/Volumes/Code/DeveloperExt/private/mihaela-books/core-animation/Book/3.4 Text, Media, and Specialized Rendering.md`: 39 lines.

MEASURED on 2026-05-31:

- Command: `find .../References/3.1 -type f | wc -l`
- Result: 36 reference files for the Core Graphics chapter.

MEASURED on 2026-05-31:

- Command: `find .../References/3.4 -type f | wc -l`
- Result: 32 reference files for the text/media chapter.

MEASURED on 2026-05-31:

- Command: Swift stdin script using `CGContext(consumer:mediaBox:_:)`,
  `CTFontCreateWithName`, `CTFramesetterCreateFrame`, and `CTFrameDraw`, then
  scanning the generated PDF bytes for `/FontFile`.
- Result:

| Requested font | Actual PostScript name | Bytes | `/FontFile` present |
|---|---|---:|---|
| Helvetica | Helvetica | 11621 | true |
| Times-Roman | Times-Roman | 12851 | true |
| Menlo-Regular | Menlo-Regular | 9787 | true |
| SFProText-Regular | SFProText-Regular | 1268840 | true |
| Noteworthy-Light | Noteworthy-Light | 11435 | true |

Interpretation: on this macOS environment, drawing CoreText text into a Quartz
PDF context caused font program data to appear in the generated PDF, including
for standard-looking names. This is evidence for issue #4, but it must become a
real package test before being treated as product behavior.

## Platform vocabulary

Use these labels in follow-up design docs and implementation notes:

- macOS-only: an API is documented only for macOS, or the package exposes it only
  through the macOS target.
- iOS-compatible: Apple documents the API for iOS or iPadOS as well as macOS.
- Apple-platform-compatible: Apple documents the API for multiple Apple
  platforms, for example iOS, macOS, tvOS, watchOS, and visionOS.
- Cross-platform: available to the portable Swift targets on macOS and Linux.

When an API is Apple-platform-compatible but the package exposes it only through
`MarkdownPDFMac`, say both facts.

## Apple API findings

### PDF context creation

DOCUMENTED: Cupertino read
`apple-docs://coregraphics/cgcontext/init(consumer:mediabox:_:)`.
Apple documents `CGContext(consumer:mediaBox:_:)` as creating a PDF graphics
context that writes drawing commands to a `CGDataConsumer`. Availability includes
iOS 2.0 and macOS 10.0.

Platform note: Apple-platform-compatible API. Package exposure should remain
macOS-only through `MarkdownPDFMac` unless a separate iOS product is introduced.
It is not Linux-compatible.

Implementation implication:

- Use `NSMutableData` plus `CGDataConsumer(data:)` for `render(...) -> Data`.
- Use the current `PDFOptions.PageSize` to build the media box.
- Pass metadata through the auxiliary dictionary at context creation.

### Page lifecycle

DOCUMENTED: Cupertino read
`apple-docs://coregraphics/cgcontext/beginpdfpage(_:)`.
`beginPDFPage(_:)` starts a PDF page and Apple states that `endPDFPage()` must
be called to end it. Availability includes iOS 2.0 and macOS 10.4.

DOCUMENTED: Cupertino read
`apple-archive://TP30001066/dq_pdf`.
The archived Quartz 2D guide says page-based contexts need paired begin/end page
calls and drawing outside a page boundary is ignored.

Platform note: Apple-platform-compatible API, exposed here only through the
macOS target.

Implementation implication:

- The mac renderer needs an explicit page state machine.
- "Impossible state" rule applies: avoid a renderer state where drawing can occur
  with no open page.
- Tests should cover empty documents, first block on first page, and page breaks
  during tables and figures.

### Links and destinations

DOCUMENTED: Cupertino read
`apple-docs://coregraphics/cgcontext/seturl(_:for:)`.
`setURL(_:for:)` associates a URL with a rectangle in default user space.
Availability includes iOS 2.0 and macOS 10.4.

DOCUMENTED: Cupertino read
`apple-docs://coregraphics/cgcontext/adddestination(_:at:)`.
`addDestination(_:at:)` creates a named destination at a point in the current
page. Availability includes iOS 2.0 and macOS 10.4.

DOCUMENTED: Cupertino read
`apple-docs://coregraphics/cgcontext/setdestination(_:for:)`.
`setDestination(_:for:)` associates a named destination with a rectangle.
Availability includes iOS 2.0 and macOS 10.4.

Platform note: Apple-platform-compatible API, exposed here only through the
macOS target.

Implementation implication:

- External Markdown links map to `setURL`.
- Internal ToC links should use `addDestination` and `setDestination`.
- Link rectangles must be computed after CoreText line layout, not from string
  length guesses.

### Outlines

DOCUMENTED: Cupertino read
`apple-docs://coregraphics/cgpdfcontextsetoutline(_:_:)`.
`CGPDFContextSetOutline(_:_:)` exists with availability including iOS 11.0 and
macOS 10.13.

Platform note: Apple-platform-compatible API. The exact dictionary shape still
needs a focused spike because the symbol page in Cupertino exposes the function
signature but not enough structure to implement confidently.

Implementation implication:

- ToC visible content can land before PDF outline support.
- Do not block ToC rendering on outlines if the outline dictionary format needs
  more research.
- Treat outline support as a separate acceptance step inside #5.

### Metadata and auxiliary dictionary

DOCUMENTED: Cupertino read
`apple-docs://coregraphics/auxiliary-dictionary-keys`.
The auxiliary dictionary supports title, author, creator, subject, keywords,
document permissions, page boxes, and output-intent keys.

DOCUMENTED: Cupertino read
`apple-docs://coregraphics/cgcontext/adddocumentmetadata(_:)`.
`addDocumentMetadata(_:)` associates XMP XML data with the PDF document.
Availability includes iOS 4.0 and macOS 10.7.

Platform note: Apple-platform-compatible API, exposed here only through the
macOS target.

Implementation implication:

- Keep `PDFOptions.title`.
- Consider adding an options value for author, subject, keywords, and creator
  only when the portable writer can accept the same public value shape.
- XMP should not be first implementation work unless scientific-article metadata
  becomes a near-term acceptance criterion.

### PDF/A and linearized PDF

DOCUMENTED: Cupertino read `apple-docs://coregraphics/kcgpdfcontextcreatepdfa`.
`kCGPDFContextCreatePDFA` exists with availability including iOS 14.0 and
macOS 11.0.

DOCUMENTED: Cupertino read
`apple-docs://coregraphics/kcgpdfcontextcreatelinearizedpdf`.
`kCGPDFContextCreateLinearizedPDF` exists with availability including iOS 14.0
and macOS 11.0.

Platform note: Apple-platform-compatible API, exposed here only through the
macOS target. The package minimum macOS platform is currently macOS 13, so the
mac target can use these without weakening the package deployment target.

Implementation implication:

- PDF/A and linearization should be opt-in flags later, not default behavior.
- Tests must verify the emitted PDF structure before claiming conformance. The
  presence of the option key alone is not enough.

### Tagged PDF

DOCUMENTED: Cupertino read
`apple-docs://coregraphics/cgpdfcontextbegintag(_:_:_:)`.
`CGPDFContextBeginTag` exists with availability including iOS 13.0 and
macOS 10.15.

DOCUMENTED: Cupertino read `apple-docs://coregraphics/cgpdftagtype`.
`CGPDFTagType` includes document, paragraph, headers, lists, links, tables,
figures, and table cell cases.

Platform note: Apple-platform-compatible API, exposed here only through the
macOS target.

Implementation implication:

- The tag vocabulary matches scientific document structure, but tagged PDF should
  come after layout stabilization.
- Tags add value only when block nesting, reading order, and link annotations are
  correct.

### CoreText layout

DOCUMENTED: Cupertino read
`apple-docs://coretext/ctframesettercreateframe(_:_:_:_:)`.
`CTFramesetterCreateFrame` lays an attributed string into a path. Availability
includes iOS 3.2 and macOS 10.5.

DOCUMENTED: Cupertino read
`apple-docs://coretext/ctframesettersuggestframesizewithconstraints(_:_:_:_:_:)`.
`CTFramesetterSuggestFrameSizeWithConstraints` measures a string range under
constraints and can return the range that fits.

DOCUMENTED: Cupertino read `apple-docs://coretext/ctframedraw(_:_:)`.
`CTFrameDraw` draws a frame into a `CGContext` and may leave the context in any
state.

Platform note: Apple-platform-compatible API, exposed here only through the
macOS target.

Implementation implication:

- CoreText is the correct starting point for macOS native text, table cells,
  captions, chart labels, and link rectangles.
- Since `CTFrameDraw` may leave the context state changed, every text draw should
  be wrapped in save/restore gstate once implementation starts.
- `fitRange` is the key primitive for table cell pagination and multi-page
  paragraphs.

### Font discovery and registration

DOCUMENTED: Cupertino read
`apple-docs://coretext/ctfontmanagercreatefontdescriptorsfromurl(_:)`.
`CTFontManagerCreateFontDescriptorsFromURL` returns font descriptors for a font
file URL. Availability includes iOS 7.0 and macOS 10.6.

DOCUMENTED: Cupertino read
`apple-docs://coretext/ctfontmanagerregisterfontsforurl(_:_:_:)`.
`CTFontManagerRegisterFontsForURL` registers fonts from a URL with the font
manager. Availability includes iOS 4.1 and macOS 10.6.

DOCUMENTED: Cupertino read
`apple-docs://coretext/ctfontmanagerissupportedfont(_:)`.
`CTFontManagerIsSupportedFont` is documented as macOS 10.6+ only.

Platform note:

- Descriptor creation and registration from URL are iOS-compatible and
  macOS-compatible.
- `CTFontManagerIsSupportedFont` is macOS-only in the Cupertino docs read during
  this pass.
- None of these APIs are Linux-compatible.

Implementation implication:

- Issue #4 should use user-supplied font URLs or system fonts, never bundled repo
  fonts.
- Font file validation cannot rely on `CTFontManagerIsSupportedFont` if this code
  is ever factored for iOS. For `MarkdownPDFMac`, it is acceptable.
- Font resolver should be an injected collaborator in `MarkdownPDFMacRenderer`
  rather than a singleton or process-wide font registry.

### Image loading

DOCUMENTED: Cupertino read
`apple-docs://imageio/cgimagesourcecreatewithurl(_:_:)`.
`CGImageSourceCreateWithURL` creates an image source from a URL. Availability
includes iOS 4.0 and macOS 10.4.

Platform note: Apple-platform-compatible API, exposed here only through the
macOS target. Not Linux-compatible.

Implementation implication:

- ImageIO can cover local image assets for the native mac path.
- Remote image fetching is out of scope unless an injected asset loader is added.

## Local book findings

### Core Graphics chapter

DOCUMENTED: Local path
`/Volumes/Code/DeveloperExt/private/mihaela-books/core-animation/Book/3.1 Core Graphics (Quartz 2D): The Software Workhorse.md`.

Findings:

- Core Graphics is described as a vector, floating-point drawing engine over a
  `CGContext` destination.
- The graphics state carries fill, stroke, line width, shadows, transforms, and
  clipping.
- Save/restore gstate is the normal isolation mechanism for local drawing
  changes.
- Clipping only narrows the current clip. Restoring the prior graphics state is
  the way to return to a wider clip.
- UI backing-store drawing is CPU and memory bound. That warning applies to view
  redraw loops, not directly to one-shot PDF generation, but it still argues for
  batching text measurement and avoiding duplicate drawing passes.

Platform note: The concepts are broad CoreGraphics concepts across Apple
platforms. The UI backing-store details differ between UIKit and AppKit. The
MarkdownPDF implementation path here is macOS-only because it lives in
`MarkdownPDFMac`.

Implementation implication:

- Every table cell, chart, image, and clipped figure should draw inside a local
  save/restore block.
- Table clipping must never leak into the next row, page, or block.
- Chart axes and gridlines should be vector paths, not pre-rendered bitmaps.

### Text and specialized rendering chapter

DOCUMENTED: Local path
`/Volumes/Code/DeveloperExt/private/mihaela-books/core-animation/Book/3.4 Text, Media, and Specialized Rendering.md`.

Findings:

- The chapter distinguishes low-level CoreText/CGFont values from UIKit font
  objects.
- It treats `NSAttributedString` style runs as the mechanism for mixed text
  styling.
- It warns that old Quartz-only text drawing APIs have encoding and text-matrix
  pitfalls.
- It includes iOS-era UI advice about `CATextLayer`, `UILabel`, and Retina
  `contentsScale`.

Platform note:

- `NSAttributedString` and CoreText are Apple-platform concepts.
- UIKit examples are iOS-oriented, not macOS.
- `CATextLayer.contentsScale` is relevant for screen layers, not direct PDF
  generation.
- `QTMovieLayer` material in the chapter is obsolete for this PDF renderer and
  irrelevant to scientific article PDFs.

Implementation implication:

- Use attributed strings and CoreText frames for rich text in PDF pages.
- Do not use old `CGContextSelectFont` plus MacRoman text drawing.
- Do not import UIKit into the macOS target.
- Do not route PDF text through `CATextLayer`; draw directly into the PDF
  `CGContext`.

### Source stubs

MEASURED: The two requested source files under `Sources/` are 3-line pointers to
PDF filenames, not extracted book text in this checkout:

- `/Volumes/Code/DeveloperExt/private/mihaela-books/core-animation/Sources/Programming with Quartz (2005).md`
- `/Volumes/Code/DeveloperExt/private/mihaela-books/core-animation/Sources/Quartz 2D Graphics for Mac OS X Developers.md`

Implementation implication:

- Use the extracted `Book/` and `References/` material for this first pass.
- If deeper direct book extraction is needed, issue #11 should add a follow-up
  task to transcribe or extract the actual PDFs into searchable text.

## Scientific article renderer definition

For this epic, "article-grade" means the macOS renderer can handle these
document features without visual overlap or structural PDF corruption:

- Title, authors, abstract, sections, subsections, and references.
- Inline links and internal destinations.
- Tables with alignments, repeated headers, multi-line cells, and page breaks.
- Figures, captions, and local image assets.
- Native vector charts with labels and captions.
- A documented diagram path for Mermaid or pre-rendered vector assets.
- Optional ToC and PDF navigation after pagination is stable.
- Embedded fonts or a clearly documented font fallback policy.

This definition is a project requirement, not an external standards claim.

## Recommended implementation shape

### Target boundary

Keep the current manifest shape: `MarkdownPDFMac` is declared only inside the
`#if os(macOS)` manifest block. Apple imports belong only in
`Packages/Sources/MarkdownPDFMac`.

The core Markdown parser and AST can remain in `MarkdownPDF`. That keeps parsing
portable and limits the mac target to layout and drawing.

### Dependencies

Do not add a singleton font registry, image loader, or diagram converter.

Future collaborators should be constructor-injected into `MarkdownPDFMacRenderer`
or a private native renderer value:

- Font resolver for system fonts and user font URLs.
- Asset loader for local images and optional generated diagrams.
- Optional PDF inspection helper in tests.

Method parameters can still carry per-render values such as the Markdown source
and asset base URL, but any stateful collaborator should enter through `init`.

### First implementation sequence

1. Add mac-only validation fixtures from #9 before changing rendering behavior.
2. Replace the current mac facade with a private CoreGraphics renderer behind the
   existing `MarkdownPDFMacRenderer` public entry point.
3. Implement PDF context lifecycle, page state, metadata, CoreText paragraphs, and
   font embedding checks.
4. Implement table layout with CoreText measurement and `fitRange`.
5. Implement vector charts with save/restore gstate isolation.
6. Spike Mermaid conversion and vector placement.
7. Implement ToC and destinations once pagination is stable.

This order matches the revised epic order in #10.

## Validation plan

Fast tests should remain part of `swift test`:

- Portable tests continue to inspect handwritten PDF structure.
- macOS-only tests compile under `#if canImport(MarkdownPDFMac)`.
- macOS tests should generate small PDFs through `MarkdownPDFMacRenderer`.

Structural checks to add:

- Page count through `CGPDFDocument`.
- Font resources include `/FontFile` when embedded-font mode is enabled.
- Links include external URL annotations.
- Internal destinations exist for headings used by ToC.
- Outlines exist only when outline support is implemented.
- Tables do not produce text outside cell rectangles in known fixtures.
- Charts contain vector path/text output, not only image XObjects.

Do not claim PDF/A, linearization, or tagged PDF until tests verify the resulting
PDF beyond checking that an option key was passed.

## Mermaid and vector diagram notes

This pass did not prove a native SVG parser in CoreGraphics. The safe paths to
carry into #8 are:

- User-supplied PDF assets can likely be placed with `CGPDFDocument` and
  `CGContextDrawPDFPage`; this needs a focused test.
- User-supplied SVG requires either a Swift SVG subset parser or an optional
  external conversion tool. It must not introduce WebKit, JavaScript, or browser
  drivers into the package.
- Optional `mmdc` can be documented as a user-supplied prebuild tool, but not as
  a package dependency.

## Risks and failure modes

| Area | Failure mode | Mitigation |
|---|---|---|
| Fonts | The mac renderer embeds an unexpected substitute font. | Record actual PostScript names in tests and expose clear font resolution errors. |
| Fonts | A user font URL is unsupported or unembeddable. | Validate with CoreText APIs and return a typed error with recovery guidance. |
| Layout | CoreText drawing mutates context state. | Wrap text draws in save/restore gstate. |
| Tables | A cell spans a page and loses formatting or links. | Use `fitRange` and render continuation frames. |
| Links | Annotation rectangles are wrong after transforms. | Compute rectangles from CoreText line/run positions in default user space. |
| ToC | Page numbers change after later blocks are added. | Implement ToC after tables, charts, and diagrams stabilize pagination. |
| Mermaid | External conversion makes tests slow or non-deterministic. | Keep external tools optional and test with checked-in fixtures. |
| Linux | Apple imports leak into portable targets. | Keep imports in `MarkdownPDFMac`; retain Linux CI and package import checks. |

## Follow-up documentation issue

STRUCTURAL: `docs/DESIGN.md` and `docs/CONVENTIONS.md` still state that
CoreGraphics is disallowed everywhere and that `MarkdownPDFMac` delegates to the
portable renderer. That matches current code for delegation but no longer matches
the epic direction. Once native mac rendering lands, those docs need an explicit
exception for `MarkdownPDFMac`.

## Source index

Cupertino Apple docs and archive:

- `apple-docs://coregraphics/cgcontext/init(consumer:mediabox:_:)`
- `apple-docs://coregraphics/cgcontext/beginpdfpage(_:)`
- `apple-docs://coregraphics/cgcontext/seturl(_:for:)`
- `apple-docs://coregraphics/cgcontext/adddestination(_:at:)`
- `apple-docs://coregraphics/cgcontext/setdestination(_:for:)`
- `apple-docs://coregraphics/cgcontext/adddocumentmetadata(_:)`
- `apple-docs://coregraphics/auxiliary-dictionary-keys`
- `apple-docs://coregraphics/cgpdfcontextsetoutline(_:_:)`
- `apple-docs://coregraphics/cgpdfcontextbegintag(_:_:_:)`
- `apple-docs://coregraphics/cgpdftagtype`
- `apple-docs://coregraphics/kcgpdfcontextcreatepdfa`
- `apple-docs://coregraphics/kcgpdfcontextcreatelinearizedpdf`
- `apple-docs://coretext/ctframesettercreateframe(_:_:_:_:)`
- `apple-docs://coretext/ctframesettersuggestframesizewithconstraints(_:_:_:_:_:)`
- `apple-docs://coretext/ctframedraw(_:_:)`
- `apple-docs://coretext/ctfontmanagercreatefontdescriptorsfromurl(_:)`
- `apple-docs://coretext/ctfontmanagerregisterfontsforurl(_:_:_:)`
- `apple-docs://coretext/ctfontmanagerissupportedfont(_:)`
- `apple-docs://imageio/cgimagesourcecreatewithurl(_:_:)`
- `apple-archive://TP30001066/dq_pdf`

Local research paths:

- `/Volumes/Code/DeveloperExt/private/mihaela-books/core-animation/Book/3.1 Core Graphics (Quartz 2D): The Software Workhorse.md`
- `/Volumes/Code/DeveloperExt/private/mihaela-books/core-animation/Book/3.4 Text, Media, and Specialized Rendering.md`
- `/Volumes/Code/DeveloperExt/private/mihaela-books/core-animation/Sources/Programming with Quartz (2005).md`
- `/Volumes/Code/DeveloperExt/private/mihaela-books/core-animation/Sources/Quartz 2D Graphics for Mac OS X Developers.md`
- `/Volumes/Code/DeveloperExt/private/mihaela-books/core-animation/References/3.1/`
- `/Volumes/Code/DeveloperExt/private/mihaela-books/core-animation/References/3.4/`
