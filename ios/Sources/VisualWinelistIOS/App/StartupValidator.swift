import Foundation

struct StartupValidator {
    /// Reads BACKEND_URL from UserDefaults (populated by Settings.bundle).
    /// Returns nil when not configured — the app should show SetupView.
    static func backendURL() -> URL? {
        let raw = UserDefaults.standard.string(forKey: "BACKEND_URL") ?? ""
        // Require an http(s) scheme: lenient URL parsing accepts junk like
        // "not-a-url:::" (scheme "not-a-url"), which would route us past Setup
        // into a dead backend. The backend is always http/https on the LAN.
        guard !raw.isEmpty, let url = URL(string: raw),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }
}
