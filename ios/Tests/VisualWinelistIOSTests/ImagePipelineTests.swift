// iOS tests run via:
//   xcodebuild test -package-path ios \
//     -destination "platform=iOS Simulator,name=iPhone 16"

import UIKit
import XCTest

@testable import VisualWinelistIOS

// MARK: - T5: resizeForUpload

final class ResizeForUploadTests: XCTestCase {

    private func makeJPEGData(size: CGSize) -> Data {
        // scale = 1 so `size` is the pixel size, not points. Without this the
        // renderer uses the simulator's screen scale (3×), turning an 800×600
        // "undersized" fixture into 2400×1800 px — which resizeForUpload then
        // correctly downscales, making the passthrough assertion flake by device.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
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
        let pixelW = Int((image.size.width * image.scale).rounded())
        let pixelH = Int((image.size.height * image.scale).rounded())
        XCTAssertLessThanOrEqual(
            max(pixelW, pixelH), 1920,
            "Oversized image (\(pixelW)×\(pixelH) px) was not downscaled to ≤1920 px")
        XCTAssertTrue(result.starts(with: [0xFF, 0xD8]), "Output must be JPEG")
    }

    // Regression: UIImage.size returns points, not pixels. A photo from a 3× device
    // has size=(1440,1920) points — so the old guard `max(size.width,size.height)>1920`
    // evaluated to `1920>1920` (false) and returned the original 4320×5760 data.
    func testResizeForUpload_3x_device_photo_is_capped_at_1920_pixels() {
        // Build a UIImage that matches a 4320×5760 iPhone Pro capture:
        // size=(1440,1920) pts, scale=3 → 4320×5760 pixel JPEG.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 1440, height: 1920), format: format)
        let source = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 1440, height: 1920)))
        }
        // Confirm fixture pixel dimensions before asserting on the fix.
        XCTAssertEqual(Int(source.size.width * source.scale), 4320)
        XCTAssertEqual(Int(source.size.height * source.scale), 5760)

        let data = source.jpegData(compressionQuality: 0.9)!
        let result = resizeForUpload(data)
        let out = UIImage(data: result)!
        let outPixelW = Int((out.size.width * out.scale).rounded())
        let outPixelH = Int((out.size.height * out.scale).rounded())
        XCTAssertLessThanOrEqual(
            max(outPixelW, outPixelH), 1920,
            "3× device photo was not downscaled: output is \(outPixelW)×\(outPixelH) px")
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
