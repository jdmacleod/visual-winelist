import XCTest
@testable import VisualWinelist

final class WineExtractionPromptTests: XCTestCase {

    func testPromptContainsJSONLInstruction() {
        XCTAssertTrue(
            WineExtractionPrompt.text.contains("one JSON object per line"),
            "Prompt must instruct JSONL output")
    }

    func testPromptContainsAllRequiredFields() {
        let required = [
            "name", "producer", "vintage", "variety", "appellation",
            "price", "description", "listSection", "rawText", "confidence",
        ]
        for field in required {
            XCTAssertTrue(
                WineExtractionPrompt.text.contains(field),
                "Prompt missing required field: \(field)")
        }
    }

    func testPromptContainsNoMarkdown() {
        XCTAssertFalse(
            WineExtractionPrompt.text.contains("```"),
            "Prompt must not use markdown code blocks — model mirrors the format")
    }

    func testPromptConfidenceRange() {
        XCTAssertTrue(
            WineExtractionPrompt.text.contains("0.0") || WineExtractionPrompt.text.contains("0.0 to 1.0"),
            "Prompt must specify confidence range")
    }
}
