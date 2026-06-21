import SwiftUI

struct SetupView: View {
    @AppStorage("BACKEND_URL") private var savedURL = ""
    @State private var inputURL = ""
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    heroSection
                    urlField
                    if let err = validationError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    connectButton
                    instructionsCard
                }
                .padding(24)
            }
            .navigationTitle("Connect to Backend")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "wineglass")
                .font(.system(size: 56))
                .foregroundStyle(.wineRed)
            VStack(spacing: 6) {
                Text("Point. Scan. Discover.")
                    .font(.title3.bold())
                Text("Connect to your backend server to start scanning wine lists and get instant tasting notes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Backend URL")
                .font(.subheadline.bold())
            TextField("http://192.168.1.100:8000", text: $inputURL)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.go)
                .onSubmit { connect() }
        }
    }

    private var connectButton: some View {
        Button(action: connect) {
            Text("Connect")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(inputURL.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Finding the server's IP address", systemImage: "info.circle")
                .font(.subheadline.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("On the Mac running the backend, open Terminal and run:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("ipconfig getifaddr en0")
                    .font(.caption.monospaced())
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: .cornerRadiusSmall))
                Text("Then enter: http://<that-ip>:8000")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Both devices must be on the same Wi-Fi network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: .cornerRadiusLarge))
    }

    // MARK: - Actions

    private func connect() {
        let raw = inputURL.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else {
            validationError = "Enter a URL"
            return
        }
        guard let url = URL(string: raw), url.scheme != nil else {
            validationError = "Enter a valid URL (e.g. http://192.168.1.100:8000)"
            return
        }
        validationError = nil
        savedURL = url.absoluteString
    }
}
