// VisualWinelistIOS-Bridging-Header.h
// Exposes DebugBridgeTouch (KIF-derived UITouch synthesis) to Swift.
// Only available in DEBUG — the ObjC class uses UIKit private selectors
// that must not be called in App Store builds.

#ifdef DEBUG
#import "../DebugBridgeTouch/include/DebugBridgeTouch.h"
#endif
