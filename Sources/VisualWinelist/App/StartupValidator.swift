import Foundation

enum StartupError: Error, LocalizedError {
    case invalidBackendURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidBackendURL(let raw):
            return """
                BACKEND_URL is not a valid URL: "\(raw)"

                Set the backend URL in your environment:

                    export BACKEND_URL=http://192.168.1.100:8000

                The default (http://localhost:8000) is used when BACKEND_URL is not set.
                """
        }
    }
}

struct StartupValidator {
    static func validate() throws -> URL {
        let raw = ProcessInfo.processInfo.environment["BACKEND_URL"] ?? "http://localhost:8000"
        guard let url = URL(string: raw), url.scheme != nil else {
            throw StartupError.invalidBackendURL(raw)
        }
        return url
    }
}
