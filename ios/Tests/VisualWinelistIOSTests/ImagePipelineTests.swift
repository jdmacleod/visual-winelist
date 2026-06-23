// iOS tests run via:
//   xcodebuild test -package-path ios \
//     -destination "platform=iOS Simulator,name=iPhone 16"

import UIKit
import XCTest

@testable import VisualWinelistIOS

// MARK: - T5: resizeForUpload

final class ResizeForUploadTests: XCTestCase {

    private func makeJPEGData(size: CGSize) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    func testResizeForUpload_downscales_when_oversized() {
        let oversized = makeJPEGData(size: CGSize(width: 4032, height: 3024))
        let result = resizeForUpload(oversized)
        let image = UIImage(data: result)!
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 1920)
        XCTAssertTrue(result.starts(with: [0xFF, 0xD8]), "Output must be JPEG")
    }

    func testResizeForUpload_passthrough_when_undersized() {
        let small = makeJPEGData(size: CGSize(width: 800, height: 600))
        let result = resizeForUpload(small)
        XCTAssertEqual(result, small, "Small images must pass through unchanged")
    }
}

// MARK: - T6: fetchImage size param

@MainActor
final class FetchImageSizeTests: XCTestCase {

    override func tearDown() async throws {
        await MockProtocolRegistry.shared.reset()
        try await super.tearDown()
    }

    private func makeClient() -> BackendClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return BackendClient(
            baseURL: URL(string: "http://localhost:8000")!,
            session: URLSession(configuration: config)
        )
    }

    func testFetchImageAppendsSize() async throws {
        var capturedURL: URL?
        let fakeJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x01])
        await MockProtocolRegistry.shared.setHandler { request in
            capturedURL = request.url
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, fakeJPEG)
        }

        let client = makeClient()
        _ = try await client.fetchImage(wineId: "abc123", size: "card")

        let urlString = capturedURL?.absoluteString ?? ""
        XCTAssertTrue(urlString.contains("?size=card"), "URL must contain ?size=card; got \(urlString)")
    }

    func testFetchImageDefaultSizeIsCard() async throws {
        var capturedURL: URL?
        let fakeJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x01])
        await MockProtocolRegistry.shared.setHandler { request in
            capturedURL = request.url
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, fakeJPEG)
        }

        let client = makeClient()
        _ = try await client.fetchImage(wineId: "abc123")

        let urlString = capturedURL?.absoluteString ?? ""
        XCTAssertTrue(urlString.contains("?size=card"), "Default size must be card; got \(urlString)")
    }
}
