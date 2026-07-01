# Vendored algorithm references

Study-only source snapshots of the canonical from-scratch algorithms behind the
harder portable features, vendored under `researchcode/` per the source snapshot
policy.

## Overview

A survey of the existing `researchcode/` engines found that the hardest
algorithms are delegated, not implemented, by the vendored PDF and typesetting
projects: every vendored PDF engine wraps zlib or miniz for DEFLATE, and the
typesetters delegate UAX #9 bidi and UAX #14 line breaking to fribidi, ICU, or
Rust crates. To reimplement these in pure Swift we need the real reference
source to study.

These snapshots are research evidence only. They are not Swift package targets,
nothing in the product or tests imports, compiles, links, or shells out to them,
and they are not build dependencies. Each upstream LICENSE is retained alongside
the studied files, and nested Git metadata was removed before tracking.

Snapshot date: 2026-06-02.

## Provenance

| Project | Upstream | License | Files to study | For |
|---|---|---|---|---|
| libdeflate | https://github.com/ebiggers/libdeflate | MIT (`COPYING`) | `lib/deflate_compress.c` | DEFLATE encoder (#127) |
| zlib | https://github.com/madler/zlib | zlib (`LICENSE`) | `deflate.c`, `trees.c` | canonical DEFLATE + length-limited Huffman (#127) |
| fribidi | https://github.com/fribidi/fribidi | LGPL-2.1 (`COPYING`) | `lib/fribidi-bidi.c` | reference UAX #9 bidi (#123) |
| unicode-bidi | https://github.com/servo/unicode-bidi | MIT / Apache-2.0 | `src/implicit.rs`, `explicit.rs`, `prepare.rs`, `level.rs` | clean pure UAX #9 bidi (#123) |
| unicode-linebreak | https://github.com/axelf4/unicode-linebreak | Apache-2.0 (`LICENSE`) | `src/lib.rs`, `src/shared.rs` | UAX #14 line breaking incl. CJK ID class (#122) |

## How these become implementation

Per the source snapshot policy, the path is to study the concept, translate it
into a small pure-Swift design that preserves direct PDF byte generation and
Linux buildability, and validate with witness tests. The snapshots never enter
the build graph. The `fribidi` snapshot is LGPL-2.1; it is kept as a reading
reference only and its license is retained, consistent with the study-only,
no-linking boundary.
