import CoreGraphics

enum ScanSettings {
    /// Longest-side pixel cap applied to the uploaded JPEG. Mutable so we can A/B
    /// different upload sizes at runtime while gathering TTFI baselines (see E10).
    static var uploadMaxSide = 1920
    static var uploadJPEGQuality: CGFloat = 0.85
}
