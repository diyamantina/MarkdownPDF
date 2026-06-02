# Multilingual corpus

A witness corpus of diacritic Latin, Cyrillic, and Greek text plus complex
tables. With an embedded font that covers these scripts (DejaVu Sans or
Liberation Sans), the glyphs typeset and round-trip through the subset and the
ToUnicode map. CJK is covered separately by the synthetic-font manuscript.

## Diacritic Latin

French: Voila, a la mode, creme brulee, deja vu, Champs-Elysees become Voilà, à la mode, crème brûlée, déjà vu.

German: Grüße, Mädchen, Fußball, schöner, Zürich.

Spanish: ¿Cómo estás? ¡Hola! mañana, niño, jalapeño, piñata.

Nordic and Slavic Latin: Ångström, smörgåsbord, Mötley, Dvořák, Łódź, žluťoučký kůň.

Inline styles: **café**, *résumé*, `naïve`, and ~~façade~~.

## Cyrillic

Russian: Привет, мир! Здравствуйте.

Russian pangram: Съешь же ещё этих мягких французских булок да выпей чаю.

Ukrainian: Доброго дня, Україна.

Bulgarian: Здравей свят.

Inline: **Россия**, *Москва*, `код`.

## Greek

Modern: Καλημέρα κόσμε. Γειά σου. Ελληνικά.

Letters: αβγδε ζηθικλμ νξοπρσ τυφχψω, ΑΒΓΔΕ ΖΗΘ ΙΚΛ ΜΝΞ.

Greek pangram: Ξεσκεπάζω την ψυχοφθόρα βδελυγμία.

## Complex tables

Alignment, inline styles, and mixed scripts in one table:

| Script | Sample | **Note** | Count |
|:-------|:------:|---------:|------:|
| Latin | café résumé | *accented* | 12 |
| Cyrillic | Привет мир | `код` | 7 |
| Greek | Καλημέρα | [link](https://example.com) | 3 |
| Mixed | café Привет Ω | ~~strike~~ | 99 |

A wide table that forces column measurement and wrapping:

| A | B | C | D | E | F |
|---|---|---|---|---|---|
| 1 | 2 | 3 | 4 | 5 | 6 |
| café | Привет | Καλημέρα | Zürich | Ωμέγα | Дякую |
| a long cell with several words to force wrapping in a narrow column | x | y | z | w | v |

A table with empty cells and mixed-script content:

| Left | Center | Right |
|:-----|:------:|------:|
| a | | c |
| | b | |
| très long contenu accentué éàü | Ωμέγα | Привет |
