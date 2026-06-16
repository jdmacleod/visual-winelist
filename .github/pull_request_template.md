## What does this change?

<!-- A short description of the change and why it's needed. -->

## How was this tested?

<!-- swift test output, manual scan results, eval script output, etc. -->

## Checklist

- [ ] `swift build` passes
- [ ] `swift test` passes
- [ ] `swift format lint -r --configuration .swift-format Sources Tests Scripts` passes
- [ ] If this touches `WineExtractionPrompt.swift`, ran `Scripts/eval-extraction.swift` against `resources/images/`
- [ ] If this touches `BraveSearchClient.swift`, ran `Scripts/validate-brave-hitrate.swift`
