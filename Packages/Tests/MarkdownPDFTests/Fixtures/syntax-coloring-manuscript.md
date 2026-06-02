# Portable Syntax Coloring Manuscript

This fixture is a focused manuscript for fenced source-code coloring. It keeps
the examples public, ASCII-only, and renderer-local. The surrounding prose is
long enough to force page flow, while the code blocks contain comments, strings,
numbers, identifiers, operators, punctuation, tabs, long lines, and repeated
page-break pressure.

## Swift Scanner Example

The first listing uses Swift-shaped source because the renderer can scan it with
a small portable tokenizer without depending on platform APIs.

```swift
// Source coloring must preserve extraction and spacing.
struct PortableRecord {
    let identifier: String
    let values: [Double]
    let isActive: Bool
}

let records = (0..<18).map { index in
    PortableRecord(identifier: "record-\(index)", values: [1.0, 2.5, 4.0], isActive: index % 2 == 0)
}

let longLine = "SyntaxColoringWitness_LongIdentifier_AuthorInput_Parser_Layout_Writer_QPDF_Poppler_MuPDF_Raster_ShouldWrapInsideTheCodeBlock"
```

After the Swift listing, prose resumes immediately. This catches layout drift
that would make the gray code rectangle collide with the following paragraph.

## Metal Scanner Example

This listing resembles C-family GPU source and includes line comments, numeric
literals, operators, punctuation, and nested brackets.

```metal
// Portable syntax colors are DeviceRGB text colors, not a renderer dependency.
kernel void shadeTiles(
    device const float3 *normals [[buffer(0)]],
    device float3 *output [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    float3 normal = normals[id];
    float visibility = max(dot(normal, float3(0.0, 1.0, 0.0)), 0.0);
    output[id] = float3(visibility, visibility * 0.5, 1.0 - visibility);
}
```

The page continues with sustained prose so the witness has to cross page
boundaries. A correct renderer keeps the code text extractable and keeps Poppler
word boxes inside the page. A broken renderer can still emit valid PDF syntax,
so the geometry and raster witnesses are part of this feature.

## JSON Scanner Example

```json
{
  "fixture": "portable-syntax-coloring",
  "checks": ["qpdf", "poppler", "mupdf", "raster"],
  "repetitions": 12,
  "enabled": true
}
```

## Tab And Long-Line Example

The following Swift block contains literal tabs in the source fixture. The
renderer expands them before tokenization, so extraction remains consistent with
the existing plain code path.

```swift
func tabbedWitness() {
	let firstColumn = "tab-expanded"
	let secondColumn = firstColumn + "-with-operators" + String(42)
	let thirdColumn = "TabbedSyntaxColoringWitnessLongIdentifier_Alpha_Beta_Gamma_Delta_Epsilon_Zeta"
	print(firstColumn, secondColumn, thirdColumn)
}
```

## Repeated Page Pressure

The paragraphs below are intentionally plain. They keep the source-code feature
inside a manuscript-shaped document rather than a one-line smoke test. The
renderer must paginate through prose and colored code without relying on color
for correctness.

The first pressure paragraph repeats enough source-adjacent language to create
real line breaks. Parser output, layout segments, content streams, qpdf checks,
Poppler text boxes, MuPDF character quads, and raster bounds are all separate
witness layers. The text should remain readable if printed in grayscale.

The second pressure paragraph adds another pass over the same concepts. Syntax
coloring should not change extraction order, code indentation, or block
spacing. Unsupported language hints remain plain by design, and missing hints do
not produce warnings in the PDF.

```unknown-language
plainUnsupported = "this block must remain uncolored"
```

## Closing Marker

Syntax Coloring Manuscript Exit Marker
