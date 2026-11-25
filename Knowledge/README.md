# Knowledge: what was learned while building MarkdownPDF

Every claim carries one of three marks: MEASURED (read in a run, with the test or the command that holds it), DOCUMENTED (a document says it, named) and UNVERIFIED (not run). Markdown only.

## Index

- [layout-stack-depth.md](layout-stack-depth.md): why a deeply nested list or quote ended the process, the stack measurement that separates the unfixed layout from the guard, the guard of 16 levels.
- [corpus-method.md](corpus-method.md): the byte baseline of 190 PDFs, how it is made, and the planted faults that prove it can fail.
- [extended-markdown-move.md](extended-markdown-move.md): the Markdown reader moved to the package ExtendedMarkdown: what moved and what could not, the corpus and test-identifier oracle, and the rule for later commits of the other package.
- [chart-parser-move.md](chart-parser-move.md): the chart parser moved to ExtendedMarkdown, the 210-file corpus identical before and after (baseline digest), and the stale-dependency fault met a third time.
- [pre-push-hook.md](pre-push-hook.md): why a push from a cold worktree failed with "unable to read tree", and the line that cures it.
- [math-spacing-baseline.md](math-spacing-baseline.md): what the TeX spacing between math atoms (from MathTypeset) changed in the 210-PDF corpus: 5 PDFs, positions only, and the one formula the first version lost.
- [measured/README.md](measured/README.md): the raw numbers behind the notes.
