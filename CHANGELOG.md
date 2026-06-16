# Changelog

## v0.1.0 (2026-06-16)

Initial proof-of-concept release. macOS app that photographs a printed or
handwritten restaurant wine list and turns it into a visual grid of tappable
bottle images, using a local Ollama model (Qwen3-VL) for text extraction and
Brave Image Search for bottle photos.

- Camera capture with retry on transient macOS Continuity Camera "Reactions"
  video-effect glitches
- Local Ollama (Qwen3-VL) streaming extraction of wines from a photographed
  list
- Brave Image Search bottle photo lookup, with ranked (non hard-filtered)
  candidate selection and per-attempt failure logging
- Wine grid view with a "Clear" button to reset and a "Scan more" flow for
  multi-page lists
- Wine detail sheet with extraction debug info (raw OCR text, confidence,
  parsed fields, Brave query)
