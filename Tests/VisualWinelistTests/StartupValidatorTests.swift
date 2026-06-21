import XCTest

@testable import VisualWinelist

@MainActor
final class StartupValidatorTests: XCTestCase {

    // MARK: - StartupValidator.validate()

    func testValidateReturnsLocalhostDefault() throws {
        let url = try StartupValidator.validate(environment: [:])
        XCTAssertEqual(url.absoluteString, "http://localhost:8000")
    }

    func testValidateWithCustomURL() throws {
        let url = try StartupValidator.validate(environment: ["BACKEND_URL": "http://192.168.1.100:8000"])
        XCTAssertEqual(url.absoluteString, "http://192.168.1.100:8000")
    }

    func testValidateThrowsOnGarbageURL() {
        XCTAssertThrowsError(
            try StartupValidator.validate(environment: ["BACKEND_URL": "not a url :::"])
        ) { error in
            guard case StartupError.invalidBackendURL(let raw) = error else {
                XCTFail("expected StartupError.invalidBackendURL, got \(error)")
                return
            }
            XCTAssertEqual(raw, "not a url :::")
        }
    }

    // MARK: - WineListViewModel.checkHealth()

    private struct MockHealthClient: BackendClientProtocol {
        let healthResult: Result<HealthResponse, Error>

        func checkHealth() async throws -> HealthResponse {
            return try healthResult.get()
        }

        func scan(photoData: Data) -> AsyncThrowingStream<SSEEvent, Error> {
            AsyncThrowingStream { $0.finish() }
        }

        func fetchImage(wineId: String) async throws -> Data { Data() }
    }

    func testCheckHealthWhenBackendUnreachable() async {
        let vm = WineListViewModel(
            backend: MockHealthClient(
                healthResult: .failure(BackendError.unreachable("http://localhost:8000"))
            )
        )
        await vm.checkHealth()
        guard case .unreachable = vm.backendStatus else {
            XCTFail("expected .unreachable, got \(vm.backendStatus)")
            return
        }
    }

    func testCheckHealthWhenOllamaNotRunning() async {
        let degraded = HealthResponse(status: "degraded", ollama: false, brave_key: true)
        let vm = WineListViewModel(
            backend: MockHealthClient(healthResult: .success(degraded))
        )
        await vm.checkHealth()
        guard case .degraded(let message) = vm.backendStatus else {
            XCTFail("expected .degraded, got \(vm.backendStatus)")
            return
        }
        XCTAssertTrue(
            message.lowercased().contains("ollama"),
            "degraded message should mention Ollama; got: \(message)"
        )
    }
}
