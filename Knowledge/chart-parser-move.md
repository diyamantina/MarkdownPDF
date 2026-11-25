# The chart parser moved to ExtendedMarkdown: what was checked

## What moved

MEASURED (read from the tree, 2026-11-25): `ChartBlock.swift`, 581 lines, imported Foundation only and named no PDF type. It became `ExtendedMarkdown.Core.Chart` in the package ExtendedMarkdown (commit d5040a0bbdaa), with the nested `Kind`, `Series`, `Point` and `ParseResult` and the entry points `parseChartFence`, `parseMermaidPie` and `isMermaidPieCandidate`, all public. The body moved unchanged except the type name.

MEASURED: what stayed here: the two geometry extensions (`ExtendedMarkdown.Core.Chart.TickLabelLayout`, `.DoughnutGeometry`, 126 lines of drawing geometry), the render plans in the renderer and the drawing tests. The parser tests (3) moved with the parser; the huge-value drawing test stayed as `ChartHugeValueTests`.

MEASURED (grep of the public and the private repositories, `*.swift`): no other live code names `ChartBlock`. TileDown has a chart parser of its own (`TileTile`, `ChartFence`); it is a separate implementation and was not touched. Unifying the two is not done.

## The oracle: the corpus, written before and after

MEASURED (Claw, 2026-11-25): the corpus (`corpus-method.md`, 210 files, five option sets) was written at the host main d7373195 and kept read-only; the digest of the digests of its files is `b380210e4fa359ad250375d3917f7da33eb1bb79`. Two runs at the same tree were identical (`diff -r`), so the corpus is deterministic. After the move (this repository at 5aa04e31, ExtendedMarkdown at d5040a0b) it was written again and `diff -r` against the baseline reported IDENTICAL: no byte of any PDF changed.

MEASURED: the full suite before the move was 1033 tests in 126 suites; after it 1031 in 127 (3 parser tests moved out, one suite split off), plus the 10 tests of the second target.

## A finding made by the move

MEASURED (a boundary test written in ExtendedMarkdown): the category limit of 12 cannot be reached by a value-series chart: the category count must equal the value count, and the value count is refused at 12 first. The guard was kept as it was; a move changes no behaviour.

## The same fault as before, a third time

MEASURED (2026-11-25, the push hook): the first push of the move failed in the hook with `'Chart' is not a member type of ExtendedMarkdown.Core`. The cause was the one in `extended-markdown-move.md`: this repository tracks no `Package.resolved` and takes ExtendedMarkdown by branch `main`, and the worktree still resolved the commit before the move. `swift package update ExtendedMarkdown` in the worktree cured it; the file is ignored by git, so the tree stayed clean. A commit that needs a newer sibling commit lands only after the sibling, and its worktree is updated first.
