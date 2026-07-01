# ``MarkdownPDFDocumentation``

@Metadata {
    @DisplayName("MarkdownPDF")
}

Pure Swift Markdown to PDF renderer for macOS and Linux, with a hand-written parser, layout engine, and PDF byte serializer.

## Overview

MarkdownPDF parses Markdown, lays the document out, and serializes PDF bytes directly in Swift. The core renderer targets macOS and Linux and uses no PDFKit, CoreGraphics, WebKit, browser renderers, LaTeX, JavaScript, Python, shell renderers, or C Markdown/PDF libraries.

This catalog is the single source of truth for project documentation: architecture and design notes, conventions, the research record behind each feature, and the coding rules contributors and tooling follow. Every code change updates the matching article in the same pull request.

## Configure the sample code project

Build and exercise the renderer from the package root:

```sh
cd Packages
swift build
swift test
swift run markdownpdf input.md output.pdf
```

The same package builds on macOS and Linux. GitHub CI runs style, macOS, and Linux checks. Build this documentation with the Swift-DocC plugin:

```sh
cd Packages
swift package --allow-writing-to-directory ./docs-archive \
  generate-documentation --target MarkdownPDFDocumentation
```

## Architecture and design

Start with the design and conventions, then the resume template behavior.

## Research record

Every feature is backed by a research note with verified sources. The research articles capture the standards, algorithms, and witness strategy behind the parser, layout, fonts, complex-script shaping, charts, compression, accessibility, and math typesetting.

## Coding rules

The rules articles define the conventions for source layout, witness gates, cross-platform behavior, and contribution workflow.

## Topics

### Architecture and conventions

- <doc:Conventions>
- <doc:Design>
- <doc:ResumeTemplate>

### Research

- <doc:AppleAndCustomFonts>
- <doc:CJKAndDiacriticsRendering>
- <doc:CanonicalPDFDocumentStructure>
- <doc:ComplexScriptFixtureWitnessPolicy>
- <doc:ComplexScriptShapingBidiRoadmap>
- <doc:DeepPortablePDFSourceStudy>
- <doc:ExistingPDFProductsSourceStudy>
- <doc:ExistingPDFWriterAlignment>
- <doc:InternationalTextRendering>
- <doc:GFMFootnotesAndTaskLists>
- <doc:MacPDFRendererResearch>
- <doc:MarkdownpdfOutputProfile>
- <doc:MathActualTextQuadArtifact>
- <doc:NativeChartRendering>
- <doc:OpenSourcePDFLibraryPorting>
- <doc:PDFRenderingLiteratureReview>
- <doc:PDFTypeModelingPolicy>
- <doc:PDFValidationTooling>
- <doc:PDFVisualLayoutValidation>
- <doc:PortableEmbeddedFontsToUnicodePlan>
- <doc:PortableMermaidFlowcharts>
- <doc:PortableSyntaxColoring>
- <doc:PureSwiftDeflateCompression>
- <doc:PureSwiftMathTypesetting>
- <doc:RTLManuscriptHardening>
- <doc:ResearchOverview>
- <doc:SourceCodeFormattingModel>
- <doc:SourceCodeRendererAnalysis>
- <doc:SourceCodeTypesettingLiterature>
- <doc:SourceSnapshotPolicy>
- <doc:TaggedPDFPDFAAccessibility>
- <doc:VendoredAlgorithmReferences>
- <doc:ThemingStylesheetModel>

### Staged source references

- <doc:Issue122SourceReferences>
- <doc:Issue123SourceReferences>
- <doc:Issue126SourceReferences>
- <doc:Issue127SourceReferences>
- <doc:Issue128SourceReferences>
- <doc:Issue129SourceReferences>
- <doc:Issue130SourceReferences>
- <doc:Issue131SourceReferences>
- <doc:AppleAndCustomFontsReferences>
- <doc:IndexReferences>

### Coding rules

- <doc:CodeStyle>
- <doc:Colors>
- <doc:Commits>
- <doc:Components>
- <doc:Concurrency>
- <doc:CrossPlatform>
- <doc:DependencyInjection>
- <doc:Documentation>
- <doc:Engineering>
- <doc:FileNaming>
- <doc:FolderGrouping>
- <doc:Fonts>
- <doc:GitDiscipline>
- <doc:LinuxServer>
- <doc:Namespacing>
- <doc:PDFWitnessGate>
- <doc:PackageArchitecture>
- <doc:PackageImportContract>
- <doc:PackageStructure>
- <doc:RulesOverview>
- <doc:SharedProtocols>
- <doc:SystematicDebugging>
- <doc:Testing>
- <doc:TestingDiscipline>
- <doc:Verification>
- <doc:ViewModels>
- <doc:Views>
