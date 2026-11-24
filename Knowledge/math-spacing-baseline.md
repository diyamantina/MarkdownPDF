# Math spacing arrives from MathTypeset: what changed in the corpus and what did not

## Why this note exists

MarkdownPDF takes its math layout from the package MathTypeset, by branch `main`. When MathTypeset began to put the TeX space between neighbouring atoms (thin 3, medium 4, thick 5 mu, one mu being 1/18 of the font size, by the classes of the TeXbook), no line of MarkdownPDF changed, yet the PDFs that contain math changed. The byte corpus of [corpus-method.md](corpus-method.md) is the way to say exactly which ones.

## What was measured

Everything below is MEASURED in runs of the 210-PDF corpus (42 documents, 5 option sets each), written twice for every state and compared with `diff -r`.

- The corpus written twice with the new MathTypeset is equal: 0 differences, 0 errors.
- The same inputs written with the MathTypeset before the change (state v5) against the baseline of the earlier state (v4) differ in exactly 5 PDFs: the five renderings of `CHANGELOG.md`. The file is part of the corpus and was edited between the two baselines, so the difference comes from the input and not from the code. That the older baseline read the older file is INFERRED from the edit, not seen.
- The new MathTypeset against the state before it (v6 against v5) differs in exactly 5 PDFs, all in the option set that turns math on (`math-code`): `math-formulas`, `01-combined-showcase`, `02-scientific-article`, `04-math-handbook` and `08-grand-handbook`. The other 205 PDFs are byte-equal.
- The five were read with the library's own PDF reader, one pair each: the page counts are equal (4, 4, 2, 1 and 20) and the extracted text is equal on every page. Only positions move: 75 of 223, 6 of 349, 4 of 240, 7 of 118 and 14 of 1185 text runs. The glue changes where a formula stands, never what the page says.
- The digest of the SHA-256 list of the 210 files (the output of `shasum -a 256 *` in the folder, in file-name order) of state v6 is `e74895b39fb82ac4e99199fa0d30339721897bf9d1f1a2f67470146d358ccbfd`; of state v5 it is `2540f04a03bd0a79f46fee6899ce9f7241a57d357dcb444a381e78ed8a67ae83` (the digest of the list file as written by `shasum -a 256 *` in the folder).

## A defect the reading found

A first run of the new MathTypeset drew one formula of `math-formulas` as visible source: `\operatorname{argmax}` threw an error for a symbol with no class, and the library draws a formula it cannot lay out as its source. The text of two pages differed, which only the reader showed (the byte comparison says "differs", not what). The class table was fixed in MathTypeset, and the five pairs above are from the run after the fix. The 1020 tests of this repository passed while the formula was lost (MEASURED: that run was made on the state before the fix): no test failed on it.

## Limits

- UNVERIFIED which path draws inline math in running text. In the option set `math-code`, `$E = mc^2$` inside a list item is drawn as ordinary text runs and none of the 192 runs of that page moved, so inline math in running text is not spaced by this change; the glue reaches display math only.
- The numbers hold for one machine and for the five option sets of the corpus.
- UNVERIFIED that any test of this repository would fail on a formula lost the way `\operatorname` was: the corpus and the reader found it.
