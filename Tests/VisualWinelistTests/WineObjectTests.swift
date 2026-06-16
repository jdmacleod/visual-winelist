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
    }

    func testDecodingMinimalObject() throws {
        let json = """
        {"name":"Ridge Monte Bello","confidence":0.88}
        """
        let wine = try JSONDecoder().decode(WineObject.self, from: Data(json.utf8))
        XCTAssertEqual(wine.name, "Ridge Monte Bello")
        XCTAssertNil(wine.vintage)
        XCTAssertNil(wine.producer)
    }

    func testEqualityByNameAndVintage() {
        let a = WineObject(name: "Opus One", producer: nil, vintage: "2019",
                           variety: nil, appellation: nil, price: nil,
                           description: nil, listSection: nil, rawText: nil, confidence: 0.9)
        let b = WineObject(name: "OPUS ONE", producer: nil, vintage: "2019",
                           variety: nil, appellation: nil, price: nil,
                           description: nil, listSection: nil, rawText: nil, confidence: 0.85)
        XCTAssertEqual(a, b, "Same name+vintage should be equal regardless of case")
    }

    func testInequalityDifferentVintage() {
        let a = WineObject(name: "Opus One", producer: nil, vintage: "2019",
                           variety: nil, appellation: nil, price: nil,
                           description: nil, listSection: nil, rawText: nil, confidence: 0.9)
        let b = WineObject(name: "Opus One", producer: nil, vintage: "2020",
                           variety: nil, appellation: nil, price: nil,
                           description: nil, listSection: nil, rawText: nil, confidence: 0.9)
        XCTAssertNotEqual(a, b, "Different vintages should not be equal")
    }

    func testLowConfidenceThreshold() {
        let lowConf = WineObject(name: "Unknown", producer: nil, vintage: nil,
                                  variety: nil, appellation: nil, price: nil,
                                  description: nil, listSection: nil, rawText: nil, confidence: 0.65)
        let highConf = WineObject(name: "Known", producer: nil, vintage: nil,
                                   variety: nil, appellation: nil, price: nil,
                                   description: nil, listSection: nil, rawText: nil, confidence: 0.80)
        let state1 = WineState.extracting(lowConf)
        let state2 = WineState.extracting(highConf)
        XCTAssertTrue(state1.isLowConfidence)
        XCTAssertFalse(state2.isLowConfidence)
    }
}
