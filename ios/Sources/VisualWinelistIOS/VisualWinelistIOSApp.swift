import SwiftUI

@main
struct VisualWinelistIOSApp: App {
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
            ContentView(backendURL: url)
        } else {
            SetupView()
        }
    }
}
