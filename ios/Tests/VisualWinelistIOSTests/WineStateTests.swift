// iOS tests run via:
//   xcodebuild test -scheme VisualWinelistIOS \
//     -destination "platform=iOS Simulator,name=iPhone 17"

import XCTest

@testable import VisualWinelistIOS

final class WineStateTests: XCTestCase {

    private func wine(note: String? = nil) -> WineObject {
        WineObject(name: "Opus One", confidence: 0.9, wineId: "w1", tastingNote: note)
    }

    func testHasNotesFalseWhenNoteAbsent() {
        XCTAssertFalse(WineState.ready(wine(note: nil), Data()).hasNotes)
    }

    func testHasNotesFalseWhenNoteBlank() {
        XCTAssertFalse(
            WineState.ready(wine(note: "   \n"), Data()).hasNotes,
            "Whitespace-only notes must not trip the indicator")
    }

    func testHasNotesTrueWhenNotePresent() {
        XCTAssertTrue(WineState.ready(wine(note: "Bold and structured."), Data()).hasNotes)
    }

    func testHasNotesSurvivesStateTransition() {
        // withUpdatedWine is how handleNotesEvent applies a streamed note.
        let base = WineState.extracting(wine(note: nil))
        XCTAssertFalse(base.hasNotes)
        let updated = base.withUpdatedWine(wine(note: "Cherry, leather."))
        XCTAssertTrue(updated.hasNotes, "A note applied via withUpdatedWine must light the card")
    }
}
