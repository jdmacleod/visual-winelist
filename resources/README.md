# resources/

## images/ (not included in repository)

`resources/images/` contains wine list photos used to evaluate the Qwen3-VL extraction prompt. These images are excluded from the repository via `.gitignore` because they are photographs of real restaurant menus and are not ours to redistribute.

To run the extraction eval, populate `resources/images/` with your own wine list photos before running:

```
swift Scripts/eval-extraction.swift
```

Supported formats: JPEG, PNG, WebP. Aim for 10–20 photos spanning a range of restaurant styles and list formats — dense numbered lists, producer-forward formats, menus with per-wine descriptions, multi-column layouts. The eval measures wine count, confidence, parse error rate, and field coverage (section headers, prices, vintages) across all photos.

Photos taken in dim restaurant lighting at a slight angle are the most useful test cases, as these represent the real operating environment.
