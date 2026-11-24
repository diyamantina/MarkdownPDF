# Measured facts

Raw results that the notes in `Knowledge/` rely on. Each line names the test or command that produced it.

- Stack of the render thread against the nesting test (`NestingDepthTests`, variable `NESTING_STACK_KB`): 128, 192 and 256 KB end the process on the unfixed layout and on the guard; 384 KB ends the process on the unfixed layout (signal code 10) and passes on the guard (3 tests, 70 seconds). MEASURED, 2026-11-24.
- Corpus: 190 PDFs written twice, 0 files differ between the two runs. MEASURED, 2026-11-24.
- Corpus with the soft-break fault planted: 120 of 190 differ. With the depth fault planted: 5 of 190 differ. MEASURED, 2026-11-24.
