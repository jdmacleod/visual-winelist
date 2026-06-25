import Foundation

struct StartupValidator {
    /// Reads BACKEND_URL from UserDefaults (populated by Settings.bundle).
    /// Returns nil when not configured — the app should show SetupView.
    static func backendURL() -> URL? {
        validHTTPURL(UserDefaults.standard.string(forKey: "BACKEND_URL") ?? "")
    }

    /// Parses a backend URL, requiring an http(s) scheme. Lenient URL parsing
    /// accepts junk like "not-a-url:::" (scheme "not-a-url") or "ftp://x", which
    /// would route us to a dead backend. Single source of truth for the rule —
    /// shared by Setup, Preferences, and the backend-URL editor.
    static func validHTTPURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }
}
