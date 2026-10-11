# 01: Panel and Inspector skeleton

**What to build:** The Panel becomes one larger window with the Input on the left and the Inspector on the right, and the Inspector shows what was found. The Panel is rebuilt as a SwiftUI window hosting the existing AppKit Input text view; it stays floating, centered and resizable, opens at about 1100×650, remembers its size and divider position, closes with Esc, and keeps the footer for config warnings and the Accessibility note. `TextierCore` gains the Inspection seam: `inspect(Input, Config, previous: nil, now, timeZone, fileExists)` returning ordered tabs (one per Pattern with Matches, ordered by the position of each Pattern's first Match, nested Matches counting at their own position; Plain Text last), each with entries carrying index, one-line preview (whitespace collapsed, truncated), UTF-16 range, Actions, the parent tag for nested Matches ("in json 0"), and a text detail; Plain Text entries are the gaps between top-level Matches, trimmed, without whitespace- or punctuation-only gaps; the initial selection is the largest top-level Match. The Inspector shows the tabs with counts, the selected tab's list, and the selected entry's text; selecting an entry selects and scrolls to its range in the Input. The Inspector is hidden when there are no Matches. Existing highlighting and the v1 click menu in the Input are left as they are for now; existing Match Windows keep working.

Spec: `.scratch/textier-v2/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** None (can start immediately)

**Status:** done

- [x] The Monolog line opens the Panel with tabs datetime, json, url, file path, Plain Text, in that order, with counts 1, 1, 1, 6
- [x] The json entry is selected on open and its text is shown in the detail area
- [x] The file path tab lists six entries, each tagged "in json 0", with readable one-line previews
- [x] The Plain Text tab lists the log message as one entry; punctuation-only gaps are not listed
- [x] Selecting any entry, nested ones included, selects and scrolls to its exact text in the Input
- [x] An Input with no Matches shows no Inspector; adding a Match brings it back at its remembered width
- [x] The Panel opens at about 1100×650, remembers size and divider between openings, floats, and closes with Esc; the footer still shows config warnings and the Accessibility note
- [x] Unit tests on the Inspection seam cover tab order, counts, entries and previews, parent tags, Plain Text entries and the initial selection on the Monolog fixture

## Comments

**2026-10-09, implementation:** Built and committed; unit tests pass. Inspection seam in `Sources/TextierCore/Inspection*.swift` (tests: `InspectionTests.swift`); the Panel is an `NSPanel` hosting SwiftUI (`PanelView`, `InspectorView`) with the AppKit Input in a split view. A smoke launch of the debug build showed tabs datetime 1, json 1, url 1, file path 6, Plain Text 1, the json entry selected and the Inspector at its default width. The app now needs an Xcode toolchain to build (SwiftUI `@State` is a macro the Command Line Tools can't expand); `scripts/bundle.sh` picks `/Applications/Xcode*.app` while `xcode-select` points at the CLT.
- Automated: the matching suites in `Tests/TextierAppTests` cover the acceptance criteria in-process. Still to check by hand: steps 1, 2, 5 of `.scratch/textier-v2/manual-test.txt`.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v2/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
