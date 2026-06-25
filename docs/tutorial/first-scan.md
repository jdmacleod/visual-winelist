# Tutorial: scan your first wine list

This walks through scanning a wine list end to end, from a cold checkout to seeing your first bottle grid. Visual Winelist is two pieces: a **FastAPI backend** that does the extraction and image search, and the **iOS app** that takes the photo and shows the results. You run the backend on a Mac on your network; the iPhone talks to it over Wi-Fi.

> You need a physical iPhone (iOS 17+). The simulator has no camera, so it can't capture a wine list.

## 1. Start the backend

The backend needs Ollama (running the `qwen3-vl:8b` vision model) and a Brave Search API key. Full setup is in [backend/README.md](../../backend/README.md); the short version:

```bash
# one-time: pull the model and start Ollama
ollama pull qwen3-vl:8b
ollama serve            # leave running in its own terminal tab

# start the API (from the repo root)
cd backend
cp .env.example .env     # then fill in BRAVE_API_KEY
uv sync
uvicorn backend.main:app --reload --workers 1
```

The API comes up at `http://localhost:8000`. Confirm it's healthy:

```bash
curl http://localhost:8000/health
```

## 2. Find the backend's LAN IP

The iPhone reaches the backend by its address on your Wi-Fi network, not `localhost`. On the Mac running the backend:

```bash
ipconfig getifaddr en0
```

That prints something like `192.168.1.100`. Your backend URL is `http://192.168.1.100:8000`. Both devices must be on the same Wi-Fi network.

## 3. Build and run the iOS app

The Xcode project is generated from `ios/project.yml` by XcodeGen and isn't committed, so generate it first:

```bash
make project            # installs XcodeGen if needed, then generates the project
make ios-open           # opens ios/VisualWinelistIOS.xcodeproj in Xcode
```

In Xcode, set your Apple Developer team under the target's **Signing & Capabilities**, connect your iPhone, pick it from the destination picker, and press **⌘R**. Full device-setup notes (trusting the developer certificate, etc.) are in [ios/README.md](../../ios/README.md).

## 4. Point the app at your backend

On first launch you'll see a setup screen. Enter the backend URL from step 2 (`http://<LAN-IP>:8000`) and continue. You can change it later under **Settings → Visual Winelist → Backend URL**, or in the app's Preferences. The home screen then shows a **Scan a Wine List** button.

## 5. Capture a wine list

Tap **Scan a Wine List** and grant camera access when prompted. With the camera preview showing "Tap to scan a wine list," frame a printed or handwritten wine list and tap to capture.

The app switches to a branded waiting screen that names each phase as it runs (sending the photo → analyzing → wines found → fetching tasting notes). The first bottles show up within a few seconds; a full list of tasting notes takes a couple of minutes, depending on the backend's hardware and the number of wines.

## 6. Watch the grid fill in

Each wine appears in the 4-column grid as soon as it's identified, first with a placeholder bottle icon, then swapping to a real bottle photo once Brave Image Search finds one. Wines the model is unsure about show a small "?" badge. A "notes ready" mark appears on each card the moment its tasting note streams in.

## 7. Inspect a wine

Tap any card to open its detail view: the full-bottle image, name, vintage, price, and section in a gradient overlay, with the tasting note below. Low-confidence reads carry the "?" badge and a warning.

## 8. Scan another page

If the list spans multiple pages, tap **Scan more** to return to the camera and capture the next page. New wines are appended to the same grid, and duplicates (matched by name + vintage) are skipped automatically. Tap **Clear** to start over.

## What's next

- [How-to: evaluate extraction quality](../how-to/evaluate-extraction.md) if wines aren't being read correctly
- [Reference: configuration](../reference/configuration.md) for environment variables and tunables
- [Explanation: architecture & data flow](../explanation/architecture.md) for how the pieces fit together
