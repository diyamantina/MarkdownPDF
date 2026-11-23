---
number: 23
title: "A large chart value crashes the renderer via Int(NaN)/Int overflow"
state: closed
labels: []
assignees: []
created: 2026-07-08T23:49:42+02:00
updated: 2026-07-09T00:30:58+02:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/23
synced: 2026-07-09T00:30:58+02:00 02be8a6cf8cf
neutralized: 1
---

A pie or chart value big enough to overflow the geometry aborts the whole render:

```
```mermaid
pie
    "w" : 1e308
    "v" : 1e308
```
```
// Fatal error: Double value cannot be converted to Int because it is either infinite or NaN
```

The pie total `1e308 + 1e308` is Inf, and `-2*pi*value / total` computes `-Inf / Inf = NaN` (the `2*pi*1e308` product itself overflows to Inf first). `NaN != 0` passes the sweep guard, so `Int(ceil(abs(NaN) / ...))` at `PDFPageCanvas.swift:394` traps.

A second trap at `MarkdownPDFRenderer.swift:1862`, `Int(value.rounded())` in `formatChartNumber`, fires for any legend value exceeding `Int.max`.

`ChartBlock.parseNumber` filters non-finite *inputs* but not sums or products that overflow downstream. Fix: guard the two `Int(Double)` conversions.

Found by an adversarial structural-integrity audit.
