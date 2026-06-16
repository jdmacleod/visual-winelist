# Tutorial: scan your first wine list

This walks through scanning a wine list end to end, from a cold checkout to seeing your first bottle grid.

## 1. Install and start Ollama

```
brew install ollama
ollama pull qwen3-vl:8b
ollama serve
```

Leave `ollama serve` running in a terminal tab — Visual Winelist talks to it over `http://localhost:11434`.

## 2. Get a Brave Search API key

Sign up for a free key at [brave.com/search/api](https://brave.com/search/api/), then export it:

```
export BRAVE_API_KEY=your_key_here
```

Add that line to `~/.zshrc` (or `~/.bash_profile`) so it's set every time you open a terminal — the app reads it from the environment at launch and won't find it otherwise.

## 3. Build and run

From the project root:

```
swift build
swift run
```

The first launch asks for camera access — grant it. If `BRAVE_API_KEY` isn't set, you'll see a "Setup Required" screen instead of the camera; fix the environment variable and relaunch.

## 4. Capture a wine list

Once the camera preview appears with "Point at wine list, then tap to scan," frame a printed or handwritten wine list and tap anywhere in the preview.

The app switches to a "Reading wine list…" screen while Ollama processes the photo. This typically takes 10–60 seconds depending on your hardware and the number of wines on the list.

## 5. Watch the grid fill in

As Ollama identifies each wine, it appears in the grid immediately with a placeholder bottle icon, then swaps to a real bottle photo once Brave Image Search finds one (usually a second or two later). Wines the model is unsure about show a small "?" badge.

## 6. Inspect a wine

Tap any bottle to open its detail sheet: full name, vintage, price, grape, region, and an **EXTRACTION DEBUG** section showing exactly what was read off the page and the Brave query used to find the photo.

## 7. Scan another page

If the list spans multiple pages, tap **Scan more** to return to the camera and capture the next page — new wines are appended to the same grid, and duplicates (matched by name + vintage) are skipped automatically.

To start over, tap **Clear**.

## What's next

- [How-to: evaluate extraction quality](../how-to/evaluate-extraction.md) if wines aren't being read correctly
- [Reference: configuration](../reference/configuration.md) for environment variables and tunables
- [Explanation: architecture & data flow](../explanation/architecture.md) for how the pieces fit together
