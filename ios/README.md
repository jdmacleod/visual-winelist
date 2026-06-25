# visual-winelist iOS

SwiftUI iPhone app that scans restaurant wine lists via the visual-winelist backend.

## Requirements

- Xcode 15+ (for building and deploying to a physical device)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — the `.xcodeproj` is generated, not committed
- An Apple Developer account (free tier works for personal device installation)
- A running visual-winelist backend on your local network
- Physical iPhone running iOS 17+ (camera required; simulator has no camera)

## Setup

1. Start the backend (see [backend/README.md](../backend/README.md)).

2. Find the backend server's LAN IP address:
   ```
   ipconfig getifaddr en0
   ```

3. Open the iOS app on your iPhone. On first launch you'll see a setup screen — enter `http://<LAN-IP>:8000` as the backend URL. Both devices must be on the same Wi-Fi network.

   You can also set the URL via **Settings → Visual Winelist → Backend URL**.

## Building in Xcode

**Generate the Xcode project** (it's produced from `project.yml` by XcodeGen and is git-ignored):

```bash
make project          # from the repo root — installs XcodeGen if missing
# or: cd ios && xcodegen generate
```

Regenerate whenever you add, rename, or remove a source file — the generated project globs the source directories, so new files are picked up automatically (no hand-edited file list).

**Open the Xcode project** (not the Swift package):

```
make ios-open         # or: open ios/VisualWinelistIOS.xcodeproj
```

**Configure code signing** (one-time setup):

1. In the Project Navigator, click **VisualWinelistIOS** at the top.
2. Select the **VisualWinelistIOS** target → **Signing & Capabilities** tab.
3. Set **Team** to your Apple Developer account.
4. Xcode will auto-generate a provisioning profile.

**Run on a physical device:**

1. Connect your iPhone via USB and trust the Mac.
2. Select your iPhone from the destination picker in the Xcode toolbar.
3. Press **⌘R** to build and run.

On first launch on the device, go to **Settings → General → VPN & Device Management** and trust your developer certificate.

## Project structure

```
ios/
├── project.yml                    ← XcodeGen spec (source of truth)
├── VisualWinelistIOS.xcodeproj/   ← GENERATED from project.yml (git-ignored)
├── Package.swift                  ← SwiftPM manifest — runs the XCTest suite
└── Sources/
    ├── VisualWinelistIOS/         ← main app target
    │   ├── Info.plist             ← bundle ID, camera usage description
    │   ├── VisualWinelistIOSApp.swift
    │   ├── App/
    │   ├── Backend/
    │   ├── Camera/
    │   ├── Debug/
    │   ├── Design/
    │   ├── Generated/             ← build-time GitSHA file (git-ignored)
    │   ├── Models/
    │   ├── Resources/
    │   │   ├── Assets.xcassets
    │   │   └── Settings.bundle
    │   ├── ViewModels/
    │   └── Views/
    ├── DebugBridgeCore/           ← HTTP state server (DEBUG only)
    ├── DebugBridgeUI/             ← SwiftUI bridge wiring (DEBUG only)
    └── DebugBridgeTouch/          ← ObjC UITouch synthesis (DEBUG only)
```

The main app source lives under `Sources/VisualWinelistIOS/`. The three `DebugBridge*` directories are compiled directly into the single app target (no module imports in the xcodeproj world); they're DEBUG-only and excluded from App Store builds. **Two build worlds:** the generated `.xcodeproj` compiles everything into one target, while `Package.swift` builds `DebugBridge*` as separate modules (imports required) and is what runs the XCTest suite on a simulator. `#if canImport(DebugBridgeCore)` bridges both. See `project.yml` for the full target spec.

## Build settings of note

| Setting | Value |
|---|---|
| Bundle ID | `com.jdmacleod.visual-winelist` |
| Deployment target | iOS 17.0 |
| Supported devices | iPhone only |
| Orientation | Portrait only |
| Swift version | 5.9 |

All build settings live in `project.yml` — edit there and run `make project`, not in Xcode's Build Settings UI (those edits are overwritten on regeneration). To change the bundle ID, edit `PRODUCT_BUNDLE_IDENTIFIER` under the target's `settings.base`.

## Features

- **4-column wine grid** — approximately 8 wines per scroll on an iPhone 15; card text is the wine name only (one line, truncated).
- **Full-bottle detail view** — tapping a card opens a 280 pt image panel showing the full bottle label (blur background + fit scaling); name, vintage, price, and section appear in a gradient overlay. Tasting notes start immediately below.
- **Preferences screen** — tap the gear icon (top-left of the grid toolbar) to open Preferences:
  - *Show price on card* — displays extracted price as a translucent capsule badge at the top-left of each card. Persisted via `@AppStorage`.
  - *About* — shows the app version from `CFBundleShortVersionString` (set via `MARKETING_VERSION` in `project.yml`).

## Architecture

The iOS client uses `URLSessionDataDelegate` for SSE streaming (rather than the `async/await bytes(for:)` API) because it needs to hold an explicit `URLSessionDataTask` reference to support task cancellation when the user navigates away mid-scan. See [docs/explanation/design-decisions.md](../docs/explanation/design-decisions.md) for the full rationale.
