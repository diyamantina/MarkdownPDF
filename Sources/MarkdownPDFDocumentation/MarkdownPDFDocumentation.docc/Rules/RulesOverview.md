# Public Swift coding rules (canonical)

The canonical, scrubbed coding rules for public Swift repos. Each file is one rule
area. This is the source of truth for the public rule set; the drop-in kit at
`../../templates/public-swift-repo/` is assembled from here by
`scripts/assemble-public-template.sh`.

`CONVENTIONS.md` is the short overview; this folder is the full set. Examples use a
sample Markdown to PDF renderer; replace the example names with your
project's when you adopt these.

## Always relevant (engine, today)

- [engineering.md](doc:Engineering) - the engineering bar: progressive
  architecture, impossible states unrepresentable, testable by design.
- [code-style.md](doc:CodeStyle) - namespacing discipline, file naming,
  one-type-per-file.
- [namespacing.md](doc:Namespacing) - caseless `enum` vs `struct` vs `class` for
  namespace anchors.
- [dependency-injection.md](doc:DependencyInjection) - no singletons, inject every
  collaborator through `init`, protocol seams.
- [concurrency.md](doc:Concurrency) - Swift 6 strict concurrency: `Sendable`,
  actors, `@MainActor`.
- [cross-platform.md](doc:CrossPlatform) - the core builds on macOS and Linux;
  guard platform-divergent code behind a protocol seam.
- [linux-server.md](doc:LinuxServer) - server-side operational rules for the
  `serve` command and any networking.
- [testing.md](doc:Testing) - Swift Testing, `@Test` / `#expect`, test isolation.
- [testing-discipline.md](doc:TestingDiscipline) - run the suite on every code
  change; write tests where none exist.
- [pdf-witness-gate.md](doc:PDFWitnessGate) - PDF structural, text, geometry,
  and raster witnesses required for generated PDF changes.
- [verification.md](doc:Verification) - no completion claim without fresh command
  output.
- [systematic-debugging.md](doc:SystematicDebugging) - reproduce, isolate,
  explain, fix.
- [documentation.md](doc:Documentation) - DocC catalogs and `///` requirements.
- [file-naming.md](doc:FileNaming) - filename conventions.
- [folder-grouping.md](doc:FolderGrouping) - when to flatten one-file folders.
- [package-structure.md](doc:PackageStructure) - workspace and package layout: one
  `Package.swift` under `Packages/`, many targets, `Apps/` for app targets.
- [package-architecture.md](doc:PackageArchitecture) - single-responsibility
  targets with unidirectional dependencies.
- [package-import-contract.md](doc:PackageImportContract) - per-target allowed
  imports; applies now, the engine and CLI are already two targets.
- [shared-protocols.md](doc:SharedProtocols) - the cross-target protocol seam.

Open decisions live in [docs/decisions/](../decisions/).

## Git and process

- [commits.md](doc:Commits) - Conventional Commits format.
- [git-discipline.md](doc:GitDiscipline) - issues, labels, PRs, branches, commits,
  remotes.

## The planned native macOS and iOS editor

- [views.md](doc:Views) - SwiftUI view architecture and identity.
- [view-models.md](doc:ViewModels) - ViewModel responsibilities and patterns.
- [components.md](doc:Components) - the component system.
- [colors.md](doc:Colors) - the color system.
- [fonts.md](doc:Fonts) - font registration in SPM packages.
