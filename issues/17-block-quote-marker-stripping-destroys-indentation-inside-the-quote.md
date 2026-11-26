---
number: 17
title: "Block quote marker stripping destroys indentation inside the quote"
state: closed
labels: []
assignees: []
created: 2026-07-08T22:40:16+02:00
updated: 2026-07-08T22:55:37+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/17
synced: 2026-07-08T22:55:37+02:00 3b29405b178f
neutralized: 2
---

`stripBlockQuoteMarker(from:)` (MarkdownParser.swift:504) trims the whole line, then drops the `>`, then trims the remainder:

```swift
let trimmed = line.trimmingCharacters(in: .whitespaces)
guard trimmed.hasPrefix(">") else { return nil }
return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
```

The second trim removes every leading space of the quote's content, so nothing indented can survive inside a block quote.

```markdown
> - a
>   - b
```

parses as `quote(ul(2))` (two siblings) instead of `quote(ul(1)[p, ul(1)])`. Outside a quote the same list nests correctly. Four-space indentation behaves identically, so indented code blocks inside quotes are also impossible, and a continuation line indented to an item's content column is dedented to column zero.

Per CommonMark, the block quote marker is: up to three leading spaces, a `>`, then **at most one** following space. Everything after that is the quote's content, indentation intact.

This predates the nested-list work (#3); that change simply made it observable, since before it nothing inside a list item could nest either.
