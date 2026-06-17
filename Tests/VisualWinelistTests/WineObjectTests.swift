import XCTest
@testable import VisualWinelist

final class WineObjectTests: XCTestCase {

    func testDecodingFullObject() throws {
        let json = """
            {
                "name": "Château Margaux",
                "producer": "Château Margaux",
                "vintage": "2018",
                "variety": "Cabernet Sauvignon blend",
                "appellation": "Margaux, Bordeaux",
                "price": "$240",
                "description": "First Growth, limited availability",
                "listSection": "Red Wines / By the Bottle",
                "rawText": "Château Margaux 2018 · First Growth · $240",
                "confidence": 0.94
            }
            """
        let wine = try JSONDecoder().decode(WineObject.self, from: Data(json.utf8))
        XCTAssertEqual(wine.name, "Château Margaux")
        XCTAssertEqual(wine.vintage, "2018")
        XCTAssertEqual(wine.confidence, 0.94)
        XCTAssertNil(wine.wineId)
        XCTAssertNil(wine.tastingNote)
        XCTAssertEqual(wine.pairings, [])
    }

    func testDecodingMinimalObject() throws {
        let json = """
            {"name":"Ridge Monte Bello","confidence":0.88}
            """
        let wine = try JSONDecoder().decode(WineObject.self, from: Data(json.utf8))
        XCTAssertEqual(wine.name, "Ridge Monte Bello")
        XCTAssertNil(wine.vintage)
        XCTAssertNil(wine.producer)
        XCTAssertEqual(wine.pairings, [], "missing pairings key should default to []")
    }

    func testDecodingWithBackendFields() throws {
        let json = """
            {
                "name": "Opus One",
                "confidence": 0.91,
                "wine_id": "abc123def456",
                "tasting_note": "Rich with dark fruit.",
                "pairings": ["lamb", "duck"]
            }
            """
        let wine = try JSONDecoder().decode(WineObject.self, from: Data(json.utf8))
        XCTAssertEqual(wine.wineId, "abc123def456")
        XCTAssertEqual(wine.tastingNote, "Rich with dark fruit.")
        XCTAssertEqual(wine.pairings, ["lamb", "duck"])
    }

    func testEqualityByWineId() {
        var a = WineObject(name: "Opus One", confidence: 0.9, wineId: "id-abc")
        var b = WineObject(name: "Opus One", confidence: 0.85, wineId: "id-abc")
        XCTAssertEqual(a, b, "Same wine_id should be equal regardless of other fields")

        a = WineObject(name: "Opus One", confidence: 0.9, wineId: "id-abc")
        b = WineObject(name: "Opus One", confidence: 0.9, wineId: "id-xyz")
        XCTAssertNotEqual(a, b, "Different wine_ids should not be equal")
    }

    func testEqualityFallbackByNameAndVintage() {
        let a = WineObject(name: "Opus One", vintage: "2019", confidence: 0.9)
        let b = WineObject(name: "OPUS ONE", vintage: "2019", confidence: 0.85)
        XCTAssertEqual(a, b, "Same name+vintage should be equal regardless of case when no wine_id")
    }

    func testInequalityDifferentVintage() {
        let a = WineObject(name: "Opus One", vintage: "2019", confidence: 0.9)
        let b = WineObject(name: "Opus One", vintage: "2020", confidence: 0.9)
        XCTAssertNotEqual(a, b, "Different vintages should not be equal")
    }

    func testLowConfidenceThreshold() {
        let lowConf = WineObject(name: "Unknown", confidence: 0.65)
        let highConf = WineObject(name: "Known", confidence: 0.80)
        XCTAssertTrue(WineState.extracting(lowConf).isLowConfidence)
        XCTAssertFalse(WineState.extracting(highConf).isLowConfidence)
    }

    func testIdUsesWineIdWhenPresent() {
        let wine = WineObject(name: "Test", confidence: 0.9, wineId: "server-id-xyz")
        XCTAssertEqual(wine.id, "server-id-xyz")
    }

    func testIdFallsBackToNameVintage() {
        let wine = WineObject(name: "Test Wine", vintage: "2020", confidence: 0.9)
        XCTAssertEqual(wine.id, "test wine-2020")
    }
}
