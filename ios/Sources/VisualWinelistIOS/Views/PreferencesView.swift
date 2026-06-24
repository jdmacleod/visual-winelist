import SwiftUI

struct PreferencesView: View {
    @AppStorage(UserDefaultsKey.showPriceOverlay) private var showPriceOverlay = false
    @AppStorage(UserDefaultsKey.sendDiagnostics) private var sendDiagnostics = false

    var body: some View {
        Form {
            Section("Wine List Display") {
                Toggle("Show price on card", isOn: $showPriceOverlay)
            }
            Section {
                Toggle("Send Diagnostics?", isOn: $sendDiagnostics)
            } header: {
                Text("Diagnostics")
            } footer: {
                Text(
                    "Sends scan timing (no photo, no wine data) to your backend after each "
                        + "scan to help diagnose performance. Off by default."
                )
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.appVersionString)
            }
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
    }
}
