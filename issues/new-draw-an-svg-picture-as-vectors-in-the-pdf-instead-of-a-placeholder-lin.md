---
number:
title: "Draw an SVG picture as vectors in the PDF instead of a placeholder line"
state: open
labels: []
assignees: []
created: 
updated: 
host: 
synced: 
neutralized: 1
---

A page's hero picture that is an SVG file is not drawn in the PDF. The PDF of every TileDown article that has an SVG `image:` starts with a gray placeholder line, `[Image: <title>]`, and the picture is missing. MarkdownPDF embeds raster images (JPEG, PNG) only.

The owner's wish (2026-11-22): the PDF should match the page. A drawing engine now exists in the package (rectangles, rounded rectangles, polygons, curves, circles, text), used by the Mermaid diagrams, the charts and the board tiles, so an SVG can be drawn as vectors instead of being left out.

## What to do

A first SVG-to-vector path for the subset that site pictures use: `svg` with `viewBox`, `rect` (with `rx`), `circle`, `path` (M, L, C, Z and the relative forms), `text` with a monospace or sans font, `fill` and `stroke` colors (hex, `none`), `stroke-width`, simple `g` groups. An element or attribute outside the subset is reported and the picture falls back to the placeholder as today, never a wrong picture (the same rule as Mermaid).

## Oracle first

The pictures of the tiledown.com site (`content/assets/post-*.svg`, 21 pairs, light and dark) are the fixtures: every drawn rectangle and circle of a picture is a known number, read back from the content stream; a picture that uses something outside the subset is listed as unsupported, not skipped. The dark variant is chosen by the caller (the PDF is light).

## Not covered

Gradients, filters, clip paths, images inside SVG and CSS styling are out of the first slice and must be reported when met.
