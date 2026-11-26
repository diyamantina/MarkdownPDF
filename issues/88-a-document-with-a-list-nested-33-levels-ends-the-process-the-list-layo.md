---
number: 88
title: "A document with a list nested 33 levels ends the process: the list layout overflows the stack"
state: closed
labels: ["before-1.0", "bug"]
assignees: []
created: 2026-11-24T15:57:15+01:00
updated: 2026-11-26T03:33:16+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/88
synced: 2026-11-26T03:33:16+01:00 89cfa48f4680
neutralized: 2
---

## What

Rendering a Markdown document whose list is nested 33 levels ends the process with a stack overflow (a bus error, 'Thread stack size exceeded'), on a thread of the Swift concurrency pool. Found on 2026-11-24 by the corpus test of the extraction work, on the tag 0.18.5; reproduced on two machines (Swift 6.4.2, arm64).

The crash report's repeating frames are the layout's list functions: render of a block, renderListItem and renderList, each repeated 33 times. The parser has a guard that keeps text past 32 levels of nesting as a plain paragraph so that hostile input degrades to prose, but the layout recurses three frames for each list level it was given, and on a thread with a small stack that is enough to overflow. Each nested level also indents the content by 24 points, so a list of 33 levels has no room on an A4 page long before that.

The input: a document made of the line 'Nested list, 33 levels.', an empty line, and then for each level from 0 to 32 the line made of two spaces repeated level times, then '- level ' and the level number plus one. A block quote nested the same way (a line of that many '> ' markers) is the same class and has not been tested alone; the third site that nests through the same guard, a footnote body, has not been tested either.

## Why

A public library must not end the process of its caller on a document it was given, whatever the nesting. This is the kind of input the 1.0 list's hostile-input item is about.

## Oracle first

The reference is the contract of the parser's guard: past the limit the text degrades to prose and the render finishes. A list, a block quote and a footnote body nested 31, 32, 33, 34, 100, 1000 and 10000 levels must each render to a PDF and never end the process, on the default stack of a worker thread; the PDF of each is read back with the library's own reader and contains the text of every level. Planted fault: remove the layout's guard, and the 10000-level case must end the process (checked in a child process, so the check itself survives).

## Acceptance

The cases above pass; the nesting limit of the layout is stated in the documentation next to the parser's limit; the corpus of the extraction work gets its nested documents past 32 levels back.

## Comments

### Mihaela, 2026-11-26T03:33:16+01:00

Fixed in 0.18.6 (commit 93c5990): a quote or list deeper than 16 levels is drawn as prose, and the tests render lists, quotes and footnotes up to 10000 levels on a small stack (a list to 1000, because its input grows with the square of the depth). Re-checked on main ac49d9e: the nesting tests pass. Remainders against the written acceptance: the list test stops at 1000 levels; the limit of 16 is not in README.md or Docs/ (it is in the CHANGELOG and Knowledge/); the planted fault checked in a child process is not a test, only a measurement noted in the test file.
