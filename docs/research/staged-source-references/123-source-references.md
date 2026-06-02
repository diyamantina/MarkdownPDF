## Reference implementations (vendored in `researchcode/`)

All four engines split bidi the same way our pipeline should: resolve UAX #9 levels over logical text, split into same-level/same-script runs, shape each run, then apply rule L2 to reorder into visual order while keeping the logical buffer for extraction (ToUnicode). None reimplements UAX #9 (Pango -> fribidi, SILE -> ICU, Typst -> `unicode-bidi`), which validates our pure-Swift #84 as the one novel piece.

Pango (C, LGPL-2.1+ - reference only):
- `researchcode/pango/pango/pango-layout.c` - `reorder_runs_recurse()` (~L6025) + `pango_layout_line_reorder()` (~L6090): textbook UAX #9 rule L2 run reordering with a single-direction fast path. Base direction (P2/P3) via `pango_find_base_dir()`.

SILE (Lua, MIT) - closest analog (reorders typeset boxes, our exact use case):
- `researchcode/sile/packages/bidi/init.lua` - `create_matrix()` (~L22, L2 as a permutation; example `Levels [0,0,0,1,1] -> [1,2,3,5,4]`), `splitNodelistIntoBidiRuns()` (~L111, runs via ICU `icu.bidi_runs`), `package:reorder()` (~L195, with a neutral-resolution fallback ~L206-223), `reverse_each_node()` (~L61, mirror glyph order in RTL boxes).

HarfBuzz (C++, MIT-style) - per-run shaping AFTER bidi + mirroring:
- `researchcode/harfbuzz/src/hb-ot-shape.cc` - `hb_ot_rotate_chars()` (~L651): bracket mirroring via `unicode->mirroring()` with `rtlm`-feature fallback (~L664-668); `hb_ensure_native_direction()` (~L588): RTL-run grapheme reversal + numeric-run native-LTR handling. Authoritative model for our BidiMirroring step.

Typst (Rust, Apache-2.0) - cleanest split-and-reorder:
- `researchcode/typst/crates/typst-layout/src/inline/shaping.rs` - `shape_range()` (~L717): split runs by `level != prev_level || script change` (~L750) before shaping; `prepare.rs:78` builds levels via `unicode-bidi` `BidiInfo::new`.
- `researchcode/typst/crates/typst-layout/src/inline/line.rs` - `reorder()` (~L249) using `bidi.visual_runs()`: visual-order ranges for render while retaining logical ranges for ToUnicode extraction. Confirms our visual/logical separation.

To-vendor (see #137): `fribidi/lib/fribidi-bidi.c` (LGPL, the reference UAX#9) and `unicode-bidi/src/{implicit,explicit,prepare,level}.rs` (MIT/Apache, clean pure UAX#9) - the actual algorithm to port for #84-level resolution.

Spec anchors: Unicode UAX #9 (P2/P3, W/N/I resolution, L1/L2), UAX #14 (line breaking), UCD BidiMirroring.txt.
