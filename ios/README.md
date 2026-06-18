# visual-winelist iOS

SwiftUI iPhone app that scans restaurant wine lists via the visual-winelist backend.

## Requirements

- Xcode 15+ (for building and deploying to a physical device)
- A running visual-winelist backend on your local network
- Physical iPhone running iOS 16+ (camera required; simulator has no camera)

## Setup

1. Start the backend (see [backend/README.md](../backend/README.md)).

2. Find the backend server's LAN IP address:
   ```
   ipconfig getifaddr en0
   ```

3. Open the iOS app on your iPhone. On first launch you'll see a setup screen — enter `http://<LAN-IP>:8000` as the backend URL. Both devices must be on the same Wi-Fi network.

   You can also set the URL via **Settings → Visual Winelist → Backend URL**.

## Building

```bash
cd ios
swift build --sdk $(xcrun --sdk iphonesimulator --show-sdk-path) --triple arm64-apple-ios16.0-simulator
```

For a physical device, open `ios/` as a Swift package in Xcode (File → Open → select `ios/Package.swift`) and run on your connected iPhone.

## Architecture

The iOS client uses `URLSessionDataDelegate` for SSE streaming (rather than the `async/await bytes(for:)` API used by the macOS client) because it needs to hold an explicit `URLSessionDataTask` reference to support task cancellation when the user navigates away mid-scan. See [docs/explanation/design-decisions.md](../docs/explanation/design-decisions.md) for the full rationale.
