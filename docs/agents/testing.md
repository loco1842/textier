# Testing

## Running

`scripts/test.sh` runs `swift test`; its arguments go straight through. Plain `swift test` fails here: `xcode-select` points at the Command Line Tools, which lack the Swift Testing and SwiftUI macro plugins, so the script selects an installed Xcode. It only looks fine with a warm `.build`. Switching `xcode-select` needs `sudo`, which is the user's step, never an agent's.

- Core only (about 300 tests, under a second once built): `scripts/test.sh --skip TextierAppTests`
- One suite: `scripts/test.sh --filter SettingsTests`
- Everything: `scripts/test.sh` (the app tests take about a minute)

The script prints failures, compile errors and the summaries; the full output is in `.build/test.log`. `TEXTIER_TEST_TIMEOUT` (seconds, default 600) bounds a run. macOS has no `timeout`; the script uses `perl -e 'alarm N; exec @ARGV'`.

`ListLayoutTests.commandLSwitchesTheLayoutAndItHoldsAcrossCaptures` is flaky (`listRowCount` is nil) on an untouched tree too. If it alone fails in a full run, rerun it with `--filter` before treating it as a regression.

## App tests

`Tests/TextierAppTests` runs the app in-process. New app behaviour gets a test in the matching `AppTests` suite: `try await runInApp { let app = try AppHarness(); defer { app.tearDown() } … }`, inside `extension AppTests { @MainActor @Suite(…) struct … }`. The suites stay `.serialized`.

Traps the harness works around, and that new tests must too:

- An AppKit event (`NSApp.postEvent`, anything that posts one) while `NSApp.run()` isn't running stops the main run loop, and Swift Testing's async main exits silently: exit 0, no summary. `runInApp` starts `NSApp.run()` from a `CFRunLoopPerformBlock`; `scripts/test.sh` reports a run that ends without a summary.
- A main-queue `Task.sleep` never fires inside a test, because the test holds the main queue. App debounces use run-loop `Timer`s.
- SwiftUI's in-process accessibility tree omits Buttons and Toggles. Drive SwiftUI through its model (`PanelModel`, `SettingsModel`), and focus through the AppKit first responder.
- NSTextView's mouse tracking reads the real pointer, not the synthetic event: the harness stands in through `InputTextView.trackMouse`.
- NSTableView and NSOutlineView ignore a synthetic `mouseDown` unless their window is key, and it never is while another app is frontmost. Tree double-clicks go through `JSONViewer.doubleClick(_:)`.
- `cursorUpdate(with:)` with any event other than a cursor update throws and crashes the test process.
- The harness shows windows through `Effects.present` without activating the app, see-through and click-through, and puts the "Copied" label off screen (`Effects.copiedLabelOrigin`), so a run doesn't take the screen or keyboard from the person at the Mac. Don't call `NSApp.activate()` or `makeKeyAndOrderFront` directly in app code; go through `Effects.present`. Nothing can assume the app is active or a window key in the macOS sense; check `firstResponder` instead.
- A run that slows down test by test usually means objects from earlier tests survive and still observe notifications (a config reload reaches every live JSON Viewer). Closures stored on long-lived objects must not capture a window strongly.

## Looking at the UI

A scratch test can capture a window for real with `screencapture -x -l <windowNumber>` (the sandbox off, Screen Recording granted, and the display awake: it exits with status 1 while the display sleeps). Set `Effects.present` back to `{ NSApp.activate(); $0.makeKeyAndOrderFront(nil) }` and the window's `alphaValue` to 1 first, since the harness hides them. Without that permission: To see a window, render its view with `bitmapImageRepForCachingDisplay` and `cacheDisplay` from a test. Materials (the Settings sidebar, glass bands) come out blank there.
