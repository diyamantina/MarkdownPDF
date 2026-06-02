# CJK corpus

Chinese, Japanese kanji, hiragana, and katakana examples. The portable renderer
emits printable ASCII and substitutes scalars an embedded font does not cover, so
without a CJK-covering font these render as the fallback. Supply a CJK font
through `PDFOptions.EmbeddedFonts` to typeset them; the synthetic-font manuscript
witnesses the embedded CJK path for covered glyphs.

## Chinese Simplified

你好世界。这是中文测试，包含简体字。

## Chinese Traditional

漢字測試，繁體中文，標點符號。

## Japanese kanji

日本語、東京、漢字、平仮名、片仮名。

## Hiragana

ひらがな、こんにちは、ありがとう、さようなら、おはよう。

## Katakana

カタカナ、コンニチハ、テスト、コンピュータ、アニメ。

## Mixed CJK table

| Script | Sample | Romaji or Pinyin |
|:-------|:-------|:-----------------|
| Chinese | 你好 | ni hao |
| Kanji | 日本 | nihon |
| Hiragana | ひらがな | hiragana |
| Katakana | カタカナ | katakana |
