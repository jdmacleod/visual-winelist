import SwiftUI

@main
struct VisualWinelistApp: App {
    var body: some Scene {
        WindowGroup {
            appContent
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    @ViewBuilder
    private var appContent: some View {
        switch Result(catching: { try StartupValidator.validate() }) {
        case .success(let backendURL):
            ContentView(backendURL: backendURL)
        case .failure(let error):
            StartupErrorView(message: error.localizedDescription)
        }
    }
}

struct StartupErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Setup Required")
                .font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Open README") {
                if let url = URL(string: "https://github.com/jdmacleod/visual-winelist#readme") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(width: 480, height: 340)
        .padding(40)
    }
}
