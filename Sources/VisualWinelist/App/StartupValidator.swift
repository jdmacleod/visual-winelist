import Foundation

enum StartupError: Error, LocalizedError {
    case missingBraveAPIKey

    var errorDescription: String? {
        switch self {
        case .missingBraveAPIKey:
            return """
            BRAVE_API_KEY is not set.

            visual-winelist uses the Brave Search API for bottle images.
            Get a free API key at https://brave.com/search/api/ then set it:

                export BRAVE_API_KEY=your_key_here

            Add that line to your shell profile (~/.zshrc or ~/.bash_profile) \
            and relaunch the app.
            """
        }
    }
}

struct StartupValidator {
    static func validate() throws -> String {
        guard let key = ProcessInfo.processInfo.environment["BRAVE_API_KEY"], !key.isEmpty else {
            throw StartupError.missingBraveAPIKey
        }
        return key
    }
}
