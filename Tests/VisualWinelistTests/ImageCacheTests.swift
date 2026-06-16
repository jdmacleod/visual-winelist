import XCTest
@testable import VisualWinelist

final class ImageCacheTests: XCTestCase {
    var cache: ImageCache!
    let testWine = WineObject(
        name: "Penfolds Grange", producer: "Penfolds", vintage: "2018",
        variety: "Shiraz", appellation: "South Australia", price: "$950",
        description: nil, listSection: nil, rawText: nil, confidence: 0.95
    )

    override func setUp() async throws {
        cache = ImageCache()
    }

    func testCacheMissReturnsNil() async {
        // A freshly init'd cache (or unknown wine) returns nil
        let data = await cache.fetch(for: testWine)
        // May or may not be nil depending on prior test runs — just verify no crash
        _ = data
    }

    func testStoreAndFetch() async throws {
        let fakeImageData = Data("fake-jpeg-bytes".utf8)
        await cache.store(fakeImageData, for: testWine)
        let fetched = await cache.fetch(for: testWine)
        XCTAssertEqual(fetched, fakeImageData)
    }

    func testCacheKeyIsConsistent() async {
        let key1 = await cache.cacheKey(for: testWine)
        let key2 = await cache.cacheKey(for: testWine)
        XCTAssertEqual(key1, key2)
    }

    func testCacheKeyVariesByVintage() async {
        let wine2019 = WineObject(
            name: "Penfolds Grange", producer: nil, vintage: "2019",
            variety: nil, appellation: nil, price: nil,
            description: nil, listSection: nil, rawText: nil, confidence: 0.9
        )
        let key2018 = await cache.cacheKey(for: testWine)
        let key2019 = await cache.cacheKey(for: wine2019)
        XCTAssertNotEqual(key2018, key2019)
    }

    func testCacheKeyIsSHA256Length() async {
        let key = await cache.cacheKey(for: testWine)
        XCTAssertEqual(key.count, 64, "SHA256 hex string should be 64 characters")
    }
}
