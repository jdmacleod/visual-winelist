import SwiftUI

struct PreferencesView: View {
    @AppStorage(UserDefaultsKey.showPriceOverlay) private var showPriceOverlay = false

    var body: some View {
        Form {
            Section("Wine List Display") {
                Toggle("Show price on card", isOn: $showPriceOverlay)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.appVersionString)
            }
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
    }
}
