import SwiftUI
import UIKit

#if DEBUG
    import DebugBridgeCore
    import DebugBridgeUI
#endif

private class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask { .portrait }
}

@main
struct VisualWinelistIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        #if DEBUG
            StateServer.shared.start()
            DebugBridgeUIWiring.installAll()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Observes BACKEND_URL in UserDefaults and routes to SetupView or ContentView.
/// When SetupView writes the URL, @AppStorage triggers a re-render automatically.
struct RootView: View {
    @AppStorage("BACKEND_URL") private var backendURLString = ""

    private var backendURL: URL? {
        guard !backendURLString.isEmpty,
            let url = URL(string: backendURLString),
            url.scheme != nil
        else { return nil }
        return url
    }

    var body: some View {
        if let url = backendURL {
            // Key by the URL string so changing the backend in Preferences rebuilds
            // ContentView (and its viewModel) against the new server instead of
            // keeping the stale @State client.
            ContentView(backendURL: url)
                .id(backendURLString)
        } else {
            SetupView()
        }
    }
}
