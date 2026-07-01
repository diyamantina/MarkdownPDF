# Portable PDF Validation Technical Report

Prepared by the MarkdownPDF test team

## Summary

This report captures a short engineering-style document with requirements,
decision records, and implementation notes. It complements the scientific
article fixture with a more operational structure.

## Requirements

| ID | Requirement | Platform |
|---|---|---|
| R1 | Render without network access | Linux and macOS |
| R2 | Keep base-font output valid by default | Linux and macOS |
| R3 | Distinguish macOS-only APIs in research notes | macOS only |

## Decision Record

The default renderer writes PDF bytes directly in Swift. The macOS product can
later add Core Graphics and Core Text behavior behind a separate target, while
the portable product remains Linux-buildable.

## Validation Notes

1. Build the package on macOS.
2. Build the package on Linux.
3. Render this fixture through the portable entry point.
4. Render the scientific article fixture through the macOS entry point when it
   is available.

## Appendix

```swift
let data = try MarkdownPDFRenderer().render(markdown: report)
```
