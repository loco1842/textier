# 01: Walking skeleton: Panel highlights URLs

**What to build:** The thinnest end-to-end path through textier. A SwiftPM package with a `TextierCore` library (Foundation only), a `Textier` SwiftUI/AppKit executable and a `TextierCoreTests` target, plus a script that assembles a menu bar `.app` (no Dock icon) from the built binary. The app shows a menu bar icon with Open Panel and Quit. Open Panel shows a floating, centered, resizable Panel holding an editable text view. `TextierCore` exposes the detection seam: a pure function from (Input, Config) to top-level Matches, where Config is an in-code list of Patterns and this ticket ships exactly one: the URL Preset (`http`/`https`, terminated by whitespace or a closing quote/bracket), with Actions `copy`. The Panel highlights each Match; a single click opens a menu of its Actions, double-click runs the first. Matches re-detect (debounced) as the Input is edited. Text outside Matches stays plain and selectable.

Spec: `.scratch/textier-v1/spec.md`. Vocabulary: `CONTEXT.md`. Decisions: ADR-0001.

**Blocked by:** None (can start immediately)

**Status:** done

- [x] `swift build` and `swift test` succeed from the CLI; no Xcode project is committed (plain `swift test` needs the `xcode-select` switch; see Comments)
- [x] The bundle script produces a runnable `.app` that appears in the menu bar without a Dock icon
- [x] Menu bar menu has Open Panel and Quit
- [x] The Panel is a floating, centered, resizable window with an editable text view
- [x] Pasting the Monolog fixture line highlights its URL as a Match
- [x] Single click on a Match shows a menu containing `copy`; double-click copies the Match text to the pasteboard
- [x] Editing the Input updates Matches live
- [x] Unit tests on the detection seam cover URL positives and near-miss negatives, and the Action list of a Match
- [x] `TextierCore` has no AppKit or SwiftUI imports

## Comments

**2026-10-08, implementation:** Built and committed.
- `swift build` works under Command Line Tools. Plain `swift test` does not: with more than one test file, the CLT toolchain can't find the Swift Testing macro plugin. It passes after `sudo xcode-select -s /Applications/Xcode-beta.app` (the human step already listed in the spec), or with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`.
- `scripts/bundle.sh` produces `build/Textier.app`. `lsappinfo` reports it as a `UIElement` (no Dock icon).
- Still to check by hand: the menu bar item, the Panel, highlighting the Monolog URL, click for the menu, double-click to copy, and live re-detection. The agent's terminal has no Accessibility access, so it couldn't drive the UI.
- Extra: option-click on a Match falls through to normal text editing, so a Match's text can still be edited by clicking.


**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v1/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
