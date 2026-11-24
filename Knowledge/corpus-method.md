# The byte baseline: 190 PDFs that must not change when code moves

## Why

A move of code (a rename, an extraction into another package) must change no output. The only check that says so is a comparison of bytes, not of "looks the same". The corpus is the set of inputs and the folder of the PDFs they produced before the move.

## What it holds

MEASURED (test file `CorpusTests.swift` on the branch that adds it; counts from its run): 38 documents, each written with 5 option sets, 190 PDFs. The documents are the library's examples, the dialect cases, and generated documents that nest quotes and lists up to the parser's limit of 32 levels.

## How it is made

1. Write every PDF into a folder.
2. Write the whole set a second time into another folder and compare the two with `diff -r`. MEASURED: equal, 0 differences. If they differ, the output is not deterministic and no baseline can be taken.
3. Keep the first folder as the baseline. After a move, write the set again and compare. Any difference is a change of behaviour, to be explained or reverted.

## The planted faults

A comparison that cannot fail proves nothing. Two faults are planted and each must turn the comparison red:

- MEASURED: a soft line break read as a hard one: 120 of 190 files differ.
- MEASURED: the depth limit of 32 read as 31: 5 of 190 files differ (the generated quote documents at depth 32).

The second fault was not caught by the first version of the corpus, whose generated documents stopped below the limit. It was added after that miss.

## Limits

- DOCUMENTED (the test file header): the corpus covers the options of its 5 sets only; an option outside them is not compared.
- UNVERIFIED: that the output is equal on a second machine. The two runs of step 2 ran on one machine.
