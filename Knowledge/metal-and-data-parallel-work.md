# Metal and the performance work here (2026-11-26)

- MEASURED (search of `Sources` on `main` at 3b4dfad for imports of `Metal`, `MetalKit`, `Accelerate`, `simd` and `CoreImage`): none.
- The work of a render (font tables, shaping, layout, compression, writing the PDF) is serial, full of branches and has to give exact bytes. That is not the shape of work a GPU speeds up. UNVERIFIED: the cost of each part; no profile was taken.
- No Metal path is planned unless a profile names data-parallel work that holds a real share of a run. Even then SIMD or Accelerate comes first, behind a paired release number, with the current path as the answer key.
- What decides: the rows and the profile of issue 78.
