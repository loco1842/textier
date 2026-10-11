# Build textier as a native Swift app

textier is a macOS menu bar app that needs a global hotkey, pasteboard access, Accessibility-driven selection capture and rich text highlighting. We build it natively in Swift (SwiftUI, falling back to AppKit where SwiftUI lacks menu bar or panel control) rather than in a web-tech shell (Tauri, Electron). Everything the app does is macOS-platform territory, the detection core is plain string processing, and a web shell would route all of the platform work through third-party plugins while adding a large runtime for a tool that lives in the menu bar.

## Consequences

- macOS only. There is no plan for other platforms.
- The detection core should stay free of AppKit/SwiftUI imports so it can be unit-tested without a running app.
