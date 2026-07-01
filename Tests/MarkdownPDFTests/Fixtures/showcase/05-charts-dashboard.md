# Metrics Dashboard · Tableau de bord · Панель показателей

A gallery of native vector charts with surrounding analysis, mixing scripts in
titles and labels.

## Throughput by script

```chart
type: bar
title: Glyphes rendus par script
x-label: Script
y-label: Glyphes
categories: Latin, Cyrillic, Greek, Symbols
series: Couverts = 220, 96, 84, 60
```

Le latin domine la couverture, suivi du cyrillique et du grec.

## Render time trend

```chart
type: line
title: Temps de rendu (ms)
x-label: Pages
y-label: ms
x: 1, 2, 4, 8, 16
series: A4 = 12, 19, 33, 61, 118
series: A3 = 15, 24, 44, 83, 160
```

## Corpus composition

```chart
type: pie
title: Состав корпуса
slice: Prose = 38
slice: Tables = 22
slice: Math = 20
slice: Charts = 12
slice: Diagrams = 8
```

## Scatter of size vs time

```chart
type: scatter
title: Taille vs temps
x-label: KB
y-label: ms
points: Docs = (12, 8), (40, 19), (120, 44), (300, 96)
```

## Summary table

| Metric | A4 | A3 | Δ |
| :--- | ---: | ---: | ---: |
| 1 page | 12 | 15 | +3 |
| 8 pages | 61 | 83 | +22 |
| 16 pages | 118 | 160 | +42 |
