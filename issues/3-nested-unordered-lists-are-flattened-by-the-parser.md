---
number: 3
title: "Nested unordered lists are flattened by the parser"
state: closed
labels: []
assignees: []
created: 2026-07-08T17:19:33+02:00
updated: 2026-07-08T22:45:16+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/3
synced: 2026-07-08T22:45:16+02:00 57c4e4963b61
neutralized: 2
---

`BlockParser.parseUnorderedList` consumes every line whose leading marker matches, regardless of indentation, and appends each as a sibling `ListItem`. `unorderedMarker(in:)` trims leading spaces, so depth is discarded.

```markdown
- outer
  - inner
```

renders as two siblings, both at the same indent.

The renderer already supports nesting: `renderList` recurses through `render(block)` for each item block and shifts `options.margins.left` by 24. Only the parser is missing. `MarkdownBlock.ListItem.blocks` is already `[MarkdownBlock]`, so the model needs no change; every item is currently a single `.paragraph`.

Same limitation applies to nested ordered lists and to block content inside items (code fences, nested quotes).
