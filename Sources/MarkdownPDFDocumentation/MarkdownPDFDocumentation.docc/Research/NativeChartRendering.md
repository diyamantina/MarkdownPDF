# Native data-chart rendering: pie, bar, line, scatter

Date: 2026-06-02

Issue: #126

## Scope

This note researches a portable, pure-Swift profile for rendering data charts
(pie, bar, line, and xy/scatter) directly to PDF bytes from the MarkdownPDF
renderer. It applies to macOS and Linux because it uses no Apple-only APIs. It
does not claim iOS support. The deliverable of #126 is documentation and a
witnessed first profile, not a promise of full chart-grammar coverage.

A chart is, for our purposes, a deterministic plan of geometric primitives
(filled paths, stroked polylines, arcs approximated by Beziers, text runs)
placed in a data-to-paper coordinate transform, then emitted as the same typed
PDF content operators the renderer already uses for tables and Mermaid diagrams.

## Product boundary

The implementation is pure Swift and Linux-buildable. It emits typed PDF content
operators directly. It must not depend on PDFKit, CoreGraphics, CoreText,
WebKit, any browser or JavaScript engine, Python, shell renderers, LaTeX,
HarfBuzz, or any C / third-party chart or PDF library.

Every open-source project cited below is a STUDY reference whose published
algorithm or layout behavior we reimplement in Swift. None is a dependency, none
is vendored, none is shelled out to. Each citation notes its license so the
reader knows the legal basis for studying it. Algorithms (nice numbers, extended
tick labeling, contrast math) are facts/math, not copyrightable expression;
palettes and source code are studied for behavior and reimplemented cleanly.

Text measurement reuses the renderer's existing base-font width tables, the same
ones that drive normal text and Mermaid label collision checks. No new
measurement engine is introduced.

## Standards and sources

Axis tick and label selection. The canonical modern algorithm is Talbot, Lin &
Hanrahan, "An Extension of Wilkinson's Algorithm for Positioning Tick Labels on
Axes," IEEE Transactions on Visualization and Computer Graphics 16(6):1036-1043,
InfoVis 2010. Stanford Vis Group landing page and canonical PDF:

  http://vis.stanford.edu/papers/tick-labels
  http://vis.stanford.edu/files/2010-TickLabels-InfoVis.pdf

Author's own copy (Justin Talbot): http://justintalbot.com/publication/extension-of-wilkinson/
PubMed record (DOI 10.1109/TVCG.2010.130): https://pubmed.ncbi.nlm.nih.gov/20975141/

The algorithm scores candidate labelings on four weighted components:
simplicity (prefers step sizes built from the nice set {1, 2, 5} and powers of
ten, and rewards including zero), coverage (how tightly the labeled range hugs
the data range), density (closeness of tick count to a target, default ~5), and
legibility (label formatting, font size, and orientation; can be optimized last).
Candidates are generated over nice step bases Q = [1, 5, 2, 2.5, 4, 3], an
integer "skip amount" j, and a target tick count m, searched with branch-and-
bound so the best total score wins. This is the predecessor of D3's
`d3.ticks` / `d3.scale` tick selection and R's `labeling::extended`.

Wilkinson's original optimization formulation appears in L. Wilkinson, "The
Grammar of Graphics," 2nd ed., Springer, 2005. The extended paper above is the
self-contained reference we implement from. R's `labeling` package documents
both the original and extended variants:

  https://search.r-project.org/CRAN/refmans/labeling/html/extended.html

Nice-number axis ranging. For the simpler "loose"/"tight" label endpoints we use
Paul Heckbert, "Nice Numbers for Graph Labels," in Graphics Gems (A. Glassner,
ed.), Academic Press, 1990, pp. 61-63. The core fact: the nicest decimal numbers
are 1, 2, 5 and their power-of-ten multiples. Reference code `Label.c`:

  https://www.realtimerendering.com/resources/GraphicsGems/gems/Label.c
  https://www.ri.cmu.edu/publications/nice-numbers-for-graph-labels/

Graphics Gems sample code license: the published code carries the standard
Graphics Gems permissive grant (free to use/modify, no warranty). We use it only
as an algorithm reference and reimplement in Swift.

Categorical color palettes with print/grayscale safety. Mark Harrower & Cynthia
A. Brewer, "ColorBrewer.org: An Online Tool for Selecting Colour Schemes for
Maps," The Cartographic Journal 40(1):27-37, 2003. DOI 10.1179/000870403235002042:

  https://www.tandfonline.com/doi/abs/10.1179/000870403235002042
  https://www.cs.rpi.edu/~cutler/classes/visualization/S18/papers/colorbrewer.pdf

ColorBrewer schemes are classified sequential, diverging, and qualitative, and
each is annotated for colorblind-safe, print-safe, photocopy-safe, and
projector-safe use. The ColorBrewer color specifications themselves are released
under the Apache License 2.0, so the numeric RGB values may be reproduced with
attribution. For our categorical chart series we transcribe a qualitative,
print-and-photocopy-safe set (e.g. the Set2 / Dark2 families) as Swift constants.

WCAG contrast for label-on-fill legibility. W3C WCAG 2.1 Success Criterion 1.4.3
(Contrast Minimum) defines the relative-luminance and contrast-ratio math we use
to decide black vs. white data labels over a colored bar or pie slice:

  https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html

Relative luminance L = 0.2126 R + 0.7152 G + 0.0722 B over linearized sRGB
channels (channel c_lin = c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)^2.4).
Contrast ratio = (L_light + 0.05) / (L_dark + 0.05); AA normal text needs 4.5:1.
We pick the label ink (black or white) that maximizes contrast against the
underlying fill, and fall back to a stroked label halo only when neither clears
the 4.5:1 bar.

## The model

A chart is planned in three coordinate spaces and one pass each:

1. Data space. Raw values from the parsed chart block (one categorical or numeric
   axis plus one or more numeric series).
2. Scale space. For numeric axes, run extended tick selection (Talbot et al.) to
   get the labeled domain, step, and tick positions; format labels with the
   step's decimal precision. For categorical axes (bars, pie), the domain is the
   ordered category list with even band spacing. Map data -> paper with an affine
   transform into the plot rectangle.
3. Paper space. Emit typed primitives into the content stream.

Geometry per chart type:

- Bar. Each category gets a band of width `plotW / n`; a bar is a filled
  rectangle (`re` + `f`) from baseline (value 0 mapped to paper) to the value.
  Grouped bars subdivide the band; stacked bars accumulate baselines. Negative
  values draw below the zero line. Axis baseline is the y of value 0.
- Line. Map each (x, y) to paper, emit `m` then a run of `l` operators, stroke
  with `S`. Missing points break the polyline. Optional point markers reuse the
  scatter marker path.
- Scatter (xy). Independent numeric x and y scales, both via extended ticks.
  Each point is a small marker centered on its mapped coordinate: a filled
  circle (4-Bezier approximation), square (`re`), or triangle (path) keyed by
  series so the chart stays legible in grayscale.
- Pie. Total = sum of non-negative values; each slice sweep angle = 2*pi *
  value/total. A circular arc is approximated by cubic Beziers, max ~90 degrees
  per segment, control-point distance k = (4/3) * tan(sweep/4) * r. Build the
  wedge path: `m` center, `l` to arc start, the Bezier `c` run along the arc,
  `l` back to center, `f`. Labels placed at the slice centroid angle, radius ~
  0.6 r, with leader lines to outside callouts when the slice is too thin to hold
  text (collision test against the existing width tables).

Circle/arc primitive. PDF has no arc operator, so all curvature is cubic Bezier.
For a quarter circle the magic constant is 0.5522847498 * r; for arbitrary
sweeps use k = (4/3) * tan(theta/4) * r. This single helper serves pie slices,
scatter circle markers, and rounded elements.

Color and label policy. Series colors come from the transcribed ColorBrewer
qualitative palette (print- and photocopy-safe ordering). For every data label
drawn over a fill, compute WCAG contrast both ways and choose the higher-contrast
ink; if both fail 4.5:1, move the label outside the shape with a leader rather
than print low-contrast text. This makes charts legible when the PDF is printed
in grayscale, matching the renderer's portability ethos.

## How-to (pure Swift sketch)

- `NiceTicks`: extended Talbot algorithm. Inputs (dataMin, dataMax, targetCount,
  weights). Output (labeledMin, labeledMax, step, [tickValue], formatString).
  Scoring helpers `simplicity`, `coverage`, `density`, `legibility`; candidate
  loop over Q-bases and j skips with branch-and-bound pruning on max attainable
  score. Heckbert `niceNum(x, round:)` available as the cheap fallback path.
- `ChartScale`: stores domain, range (plot rect edge), and the data->paper map;
  categorical and linear variants. No log scale in the first profile.
- `ArcPath`: emits Bezier arc segments given center, radius, start/sweep angle.
- `Palette`: static qualitative ColorBrewer constants; `contrastInk(over:)`
  returns `.black`/`.white` using the WCAG luminance/contrast formulas.
- `ChartPlanner`: turns a parsed chart block into a list of typed primitives;
  runs label collision checks against the font width tables before committing,
  exactly like the Mermaid edge-label rule.
- `ChartEmitter`: serializes primitives to content operators (`re`, `m`, `l`,
  `c`, `f`, `S`, `rg`, text show ops) into the existing content-stream writer.

Everything above is arithmetic and PDF operator emission. No platform graphics
context, no rasterization, no external process.

## Reference implementations

Studied for behavior and algorithm shape; reimplemented in Swift, never linked:

- D3 (`d3-scale`, `d3-shape`, `d3-array` ticks). License: ISC, (c) Mike Bostock
  (BSD-3-Clause before v7). Best reference for tick selection, band scales, and
  arc/pie layout math. https://github.com/d3/d3/blob/main/LICENSE
- Vega-Lite. License: BSD-3-Clause, UW Interactive Data Lab. Reference for the
  declarative chart-spec -> mark mapping we mirror in our parsed chart block.
  https://github.com/vega/vega-lite
- matplotlib. License: matplotlib/PSF-style BSD-compatible license. Reference for
  bar/line/scatter axis conventions, baseline handling, and tick formatting.
  https://matplotlib.org/stable/project/license.html
- gnuplot. License: gnuplot license (freely redistributable; modified versions
  distributed as patches only). Study its autoscaling/tic behavior only as a
  concept; do not copy code given the unusual terms.
  https://spdx.org/licenses/gnuplot.html
- Chart.js. License: MIT. Reference for default categorical color cycling and
  legend/label placement heuristics. https://github.com/chartjs/Chart.js
- plotters (Rust). License: MIT. Closest pure-language drawing-primitive model to
  ours (paths, no platform context); good architectural analogue.
  https://github.com/plotters-rs/plotters/blob/master/LICENSE

License note: MIT/BSD/ISC/Apache-2.0 permit study and clean reimplementation
with attribution where code is copied; we copy no code, only algorithms. The
gnuplot license is restrictive, so it is concept-only.

## Witness policy

A chart type cannot be documented as supported until it passes:

- qpdf structural validation with no warnings.
- Swift structural checks for the content stream, resources, and page objects.
- Poppler text extraction proving axis labels, tick labels, and legend text are
  present and source-faithful.
- Poppler `pdftotext -tsv` geometry proving tick labels and data labels do not
  overlap and sit within the plot rectangle.
- MuPDF structured text for character quads on dense label sets.
- Poppler and MuPDF raster comparison proving bar/slice/marker ink bounds match
  the planned geometry, including a grayscale render to prove print legibility.
- macOS and Linux runs producing byte-comparable output for the same input.

Unsupported chart inputs (log axes, time axes, unknown chart kinds, more series
than the palette safely distinguishes) must render visible fallback text, never a
silently wrong chart. Mermaid pie charts are the first chart syntax promoted out
of fallback into the native chart profile.

## Implemented first profile

Issue #126 implements the first portable chart profile in Swift. The renderer
recognizes Mermaid `pie` blocks and fenced `chart` blocks with `type: bar`,
`type: line`, or `type: scatter`.

The fenced chart grammar is intentionally small:

- Common keys: `type`, `title`, `x-label`, `y-label`.
- Bar and line charts: `categories: Q1, Q2` plus `series: Name = 1, 2`, or
  numeric `x: 2024, 2025` for line charts.
- Scatter charts: `series: Name = (1, 2), (2, 4)`.
- Pie charts: Mermaid `pie title ...` with `label : value` entries, or fenced
  chart `slice: Label = value` entries.

The first profile uses direct PDF operators only: `re`/`f` for bars and legend
swatches, `m`/`l`/`S` for axes and line series, cubic `c` Beziers for pies and
circle markers, and ordinary text runs for titles, axis labels, tick labels, and
legend labels. Dense or unknown inputs still render visible fallback text.

## Ordered work

1. #126 First native chart profile: Mermaid pie, fenced bar, fenced line, and
   fenced scatter charts.
2. Add extended Talbot tick scoring when the simple Heckbert 1-2-5 fallback
   produces crowded labels.
3. Add richer label collision handling for outside pie callouts and dense
   categorical axes.
4. Add grouped and stacked bar variants once their witness fixtures exist.

## Platform notes

This is portable macOS/Linux Swift. It is not macOS-only and does not establish
iOS support. It uses no CoreGraphics, CoreText, or browser measurement; all
curvature is cubic-Bezier arithmetic and all text measurement reuses the shared
base-font tables. A future macOS adapter could cross-check measurements, but the
shared renderer may claim only behavior implemented in Swift and witnessed on
both platforms.


## Source-code references (vendored in `researchcode/`)

Concrete implementations to study (study-only, reimplement in pure Swift; emit raw PDF operators in DeviceRGB, no CoreGraphics).

- `researchcode/dart_pdf/pdf/lib/src/pdf/graphics.dart` - `_bezierArcFromCentre` / `bezierArc`: kappa arc-to-cubic-Bezier (`kappa = 4/3 * (1-cos(h))/sin(h)`, <=90deg fragments). The pie-slice arc primitive to port. (Dart, Apache-2.0)
- `researchcode/dart_pdf/pdf/lib/src/widgets/chart/pie_chart.dart` - `PieGrid`/`PieDataSet`: slice angles from `2*pi/total`, wedge via `bezierArc(large: delta>pi)`, bisector label/popout. (Apache-2.0)
- `researchcode/dart_pdf/pdf/lib/src/widgets/chart/{bar_chart,point_chart,line_chart}.dart` - bar `drawRect`, scatter `drawEllipse`, line polyline + Catmull-Rom `curveTo` smoothing. (Apache-2.0)
- `researchcode/reportlab/src/reportlab/graphics/charts/utils.py` - `nextRoundNumber`: Heckbert 1-2-5-10 nice-number tick selector; pair with `axes.py:_calcValueStep` for tick step + limit rounding. (Python, BSD-style)
- `researchcode/weasyprint/weasyprint/svg/path.py` - `path()` `aA` branch: SVG elliptical-arc to Bezier with `h = 4/3 * tan(delta/4)`; `shapes.py` circle kappa `0.5523`. (Python, BSD-3)

Note: the vendored `matplotlib/` and `cairo/` are pruned to font-subsetting only (`ticker.py`/`scale.py`/`_axes.py`/`cairo-arc.c` absent); use dart_pdf/reportlab/weasyprint above. graphviz has no reusable Cartesian-axis code.

Spec anchors (high authority) confirmed correct: Talbot/Lin/Hanrahan 2010 (tick labeling), Heckbert "Nice Numbers" (matches reportlab `nextRoundNumber`), ColorBrewer, WCAG 1.4.3 contrast.
