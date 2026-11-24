# The layout recursed without a limit, and a list of 33 levels ended the process

## What happened

MEASURED (test `NestingDepthTests`): a Markdown list nested 33 levels, rendered on a thread with a small stack, ended the whole process with a crash (signal code 10). No error was thrown and no PDF was returned.

The parser already refuses to nest past 32 levels (`MarkdownParser.maximumNestingDepth`). That limit did not protect the layout: the parser can hand the layout a tree of 32 container levels, and a footnote body or a quote written on one line (`> > > ...`) can reach many more before the parser's guard applies to it. The layout lays out a quote or a list item by calling itself for the blocks inside, so each level costs several stack frames and 24 points of indent.

## The stack measurement

MEASURED (the test with `NESTING_STACK_KB` set, one process for each run, on the tag 0.18.5 and on the guard):

| Stack of the render thread | Unfixed layout | Layout with the guard |
|---|---|---|
| 128 KB | process ends | process ends |
| 192 KB | process ends | process ends |
| 256 KB | process ends | process ends |
| 384 KB | process ends (signal code 10) | passes: 3 tests, 31 to 10000 levels |

Reading: below 384 KB the renderer cannot run at all, so a case there proves nothing about nesting. 384 KB is the first stack where the two differ, so it is the stack the test uses. A pool thread of the Swift concurrency runtime has a stack of this order, which is where the crash was first seen.

## The guard

DOCUMENTED (comment on `maximumContainerDepth` in `MarkdownPDFRenderer.swift`): past 16 levels of quotes and list items the container is drawn as one paragraph of its text, with its words kept. 16 levels of indent already leave a page about a third of its width, so nothing readable is lost by stopping there.

MEASURED (test `NestingDepthTests`): lists, quotes and footnote bodies from 31 to 10000 levels render on the 384 KB thread and the deepest text is read back from the PDF with the library's own reader.

## Method lessons

- A limit in one stage (the parser) does not protect a later recursive stage. Check each recursion on its own input.
- To reproduce a stack overflow, choose the stack, not the depth: run the case on a thread of a stated size, in its own process, and treat the process ending as the failing result. The planted fault is the unfixed code, and it must be red as a crash.
- Compare text after folding white space: a line that wraps between two words hides them from a plain `contains`.
- Carry a result out of a thread with a stream continuation, not a box marked as unchecked: the compiler then knows it is safe. `Synchronization.Mutex` needs a newer system than this package targets.
