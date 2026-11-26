---
number: 68
title: "The reader meets hostile files: a corpus of malformed PDFs with exact expected errors"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T10:57:51+01:00
updated: 2026-11-24T13:28:00+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/68
synced: 2026-11-24T13:28:00+01:00 4afe363f1591
neutralized: 2
---

## What

Build a corpus for the reader: truncated files, a bad or missing cross-reference table, offsets outside the file, cycles in the page tree and in object references, huge counts and lengths, bad stream filters, deeply nested arrays and dictionaries, an encrypted file. Each case has an exact expected error, and none may crash, hang or use memory without bound. State a bound on memory and time per byte of input. The library writes strictly and reads liberally: say where the reader recovers and where it refuses.

## Why

The reader is the library's own checker of everything it writes, and it reads files it did not write.

## Oracle first

The reference is the expected error per case, written before the run. Every case is classified accepted, rejected with a named error, or blocked with a reason.

## Acceptance

The corpus is committed, every case passes with its exact error, the bound is stated and tested, and a planted missing check (a cycle, a length) is caught.

## Comments

### Mihaela, 2026-11-24T13:28:00+01:00

Correction after reading the code on 2026-11-24. The reader says of itself that it is not a general PDF reader: anything outside the engine's own feature set is refused as unsupported (the reader's header comment and Docs/NOT-VERIFIED.md). So the sentence that the library reads liberally and reads files it did not write is not true today. Decide for 1.0: keep the reader strict (it reads what the engine writes) and say so, or widen it. The corpus then checks the decision: for a strict reader the expected answer for a foreign or malformed file is a typed unsupported or malformed error, never a crash. Cycles already have visited sets for the cross-reference chain, the page tree, the outline and the structure tree; the memory and time bound is not stated anywhere and the bound unit has to be named.
