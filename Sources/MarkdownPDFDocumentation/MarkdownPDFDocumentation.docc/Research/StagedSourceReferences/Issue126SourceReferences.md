# Issue 126 source references

Staged source and reference materials gathered for issue #126, vendored study-only under `researchcode/`.

## Source-code references (vendored in `researchcode/`)

Concrete implementations to study (study-only, reimplement in pure Swift; emit raw PDF operators in DeviceRGB, no CoreGraphics).

- `researchcode/dart_pdf/pdf/lib/src/pdf/graphics.dart` - `_bezierArcFromCentre` / `bezierArc`: kappa arc-to-cubic-Bezier (`kappa = 4/3 * (1-cos(h))/sin(h)`, <=90deg fragments). The pie-slice arc primitive to port. (Dart, Apache-2.0)
- `researchcode/dart_pdf/pdf/lib/src/widgets/chart/pie_chart.dart` - `PieGrid`/`PieDataSet`: slice angles from `2*pi/total`, wedge via `bezierArc(large: delta>pi)`, bisector label/popout. (Apache-2.0)
- `researchcode/dart_pdf/pdf/lib/src/widgets/chart/{bar_chart,point_chart,line_chart}.dart` - bar `drawRect`, scatter `drawEllipse`, line polyline + Catmull-Rom `curveTo` smoothing. (Apache-2.0)
- `researchcode/reportlab/src/reportlab/graphics/charts/utils.py` - `nextRoundNumber`: Heckbert 1-2-5-10 nice-number tick selector; pair with `axes.py:_calcValueStep` for tick step + limit rounding. (Python, BSD-style)
- `researchcode/weasyprint/weasyprint/svg/path.py` - `path()` `aA` branch: SVG elliptical-arc to Bezier with `h = 4/3 * tan(delta/4)`; `shapes.py` circle kappa `0.5523`. (Python, BSD-3)

Note: the vendored `matplotlib/` and `cairo/` are pruned to font-subsetting only (`ticker.py`/`scale.py`/`_axes.py`/`cairo-arc.c` absent); use dart_pdf/reportlab/weasyprint above. graphviz has no reusable Cartesian-axis code.

Spec anchors (high authority) confirmed correct: Talbot/Lin/Hanrahan 2010 (tick labeling), Heckbert "Nice Numbers" (matches reportlab `nextRoundNumber`), ColorBrewer, WCAG 1.4.3 contrast.
