import Foundation

struct StartupValidator {
    /// Reads BACKEND_URL from UserDefaults (populated by Settings.bundle).
    /// Returns nil when not configured — the app should show SetupView.
    static func backendURL() -> URL? {
        let raw = UserDefaults.standard.string(forKey: "BACKEND_URL") ?? ""
        guard !raw.isEmpty, let url = URL(string: raw), url.scheme != nil else { return nil }
        return url
    }
}
