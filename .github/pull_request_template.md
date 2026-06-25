## What does this change?

<!-- A short description of the change and why it's needed. -->

## How was this tested?

<!-- iOS XCTest output, manual scan results, eval script output, etc. -->

## Checklist

- [ ] iOS device build passes (`make project` then `xcodebuild build … -destination "generic/platform=iOS"`)
- [ ] iOS XCTest suite passes on a simulator (`xcodebuild test`)
- [ ] `swift format lint -r --configuration .swift-format ios/Sources ios/Tests Scripts` passes
- [ ] If this touches backend extraction prompts, ran `Scripts/eval-extraction.swift` against `resources/images/`
- [ ] If this touches Brave image search, ran `Scripts/validate-brave-hitrate.swift`
