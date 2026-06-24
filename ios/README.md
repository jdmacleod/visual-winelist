# visual-winelist iOS

SwiftUI iPhone app that scans restaurant wine lists via the visual-winelist backend.

## Requirements

- Xcode 15+ (for building and deploying to a physical device)
- An Apple Developer account (free tier works for personal device installation)
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

## Building in Xcode

**Open the Xcode project** (not the Swift package):

```
File → Open → select ios/VisualWinelistIOS.xcodeproj
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
├── VisualWinelistIOS.xcodeproj/   ← open this in Xcode
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/
│       └── VisualWinelistIOS.xcscheme
└── Sources/
    ├── VisualWinelistIOS/         ← main app target
    │   ├── Info.plist             ← bundle ID, camera usage description
    │   ├── VisualWinelistIOSApp.swift
    │   ├── App/
    │   ├── Backend/
    │   ├── Camera/
    │   ├── Design/
    │   ├── Models/
    │   ├── Resources/
    │   │   └── Settings.bundle
    │   ├── ViewModels/
    │   └── Views/
    ├── DebugBridgeCore/           ← HTTP state server (DEBUG only)
    ├── DebugBridgeUI/             ← SwiftUI bridge wiring (DEBUG only)
    └── DebugBridgeTouch/          ← ObjC UITouch synthesis (DEBUG only)
```

The main app source lives under `Sources/VisualWinelistIOS/`; the three `DebugBridge*` targets alongside it are DEBUG-only and excluded from App Store builds. The `.xcodeproj` references all source files directly — no code duplication. `Package.swift` remains for `swift build` and CI tooling.

## Build settings of note

| Setting | Value |
|---|---|
| Bundle ID | `com.jdmacleod.visual-winelist` |
| Deployment target | iOS 16.0 |
| Supported devices | iPhone only |
| Orientation | Portrait only |
| Swift version | 5.9 |

To change the bundle ID (required if you have a custom domain), edit `PRODUCT_BUNDLE_IDENTIFIER` in the target's Build Settings.

## Features

- **4-column wine grid** — approximately 8 wines per scroll on an iPhone 15; card text is the wine name only (one line, truncated).
- **Full-bottle detail view** — tapping a card opens a 280 pt image panel showing the full bottle label (blur background + fit scaling); name, vintage, price, and section appear in a gradient overlay. Tasting notes start immediately below.
- **Preferences screen** — tap the gear icon (top-left of the grid toolbar) to open Preferences:
  - *Show price on card* — displays extracted price as a translucent capsule badge at the top-left of each card. Persisted via `@AppStorage`.
  - *About* — shows the app version sourced from the repo `VERSION` file.

## Architecture

The iOS client uses `URLSessionDataDelegate` for SSE streaming (rather than the `async/await bytes(for:)` API used by the macOS client) because it needs to hold an explicit `URLSessionDataTask` reference to support task cancellation when the user navigates away mid-scan. See [docs/explanation/design-decisions.md](../docs/explanation/design-decisions.md) for the full rationale.
