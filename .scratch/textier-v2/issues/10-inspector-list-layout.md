# 10: Inspector as one list

**What to build:** A setting to show the Inspector's Pattern groups in one view instead of tabs, for small Inputs where switching tabs on every click is slower than scanning. A new optional config key `inspectorLayout`: `"tabs"` (default, v2 behaviour) or `"list"`. In the list layout the tab bar goes away and the list shows every group (each Pattern, then Plain Text) as a collapsible section headed by its color dot, name and count; the selected entry's Action bar and parsed view stay below. Selection, ↑/↓ (across sections), Return, double-click, Tab/Shift-Tab and ⌘1–⌘9 (jump to the nth section) work as with tabs. Selecting an entry in a collapsed section (from the Input) expands it. Collapsed sections are kept while the Panel stays open. First-launch emission writes `"inspectorLayout": "tabs"`; an unknown value warns and falls back to tabs.

Spec: `.scratch/textier-v2/spec.md` (follow-up requested by the user, 2026-10-09). Vocabulary: `CONTEXT.md`.

**Blocked by:** 01, 04

**Status:** done

- [x] `"inspectorLayout": "list"` shows every Pattern as a section with its entries; `"tabs"` keeps the tab bar
- [x] A section collapses and expands; selecting into a collapsed section expands it
- [x] ↑/↓ move across sections; Return runs the first Action; ⌘1–⌘9 jump to sections
- [x] Switching the key and saving applies without reopening the Panel
- [x] A Tabs/List switch in the Panel toolbar (also ⌘L) changes the layout; it holds across captures until the app quits or the config's `inspectorLayout` changes
- [x] Unit tests on the config seam cover default, both values, round trip and the unknown-value warning
- [x] The list looks right: section headers with dots and counts, disclosure chevrons, rows indented under them

## Comments

**2026-10-09, implementation:** `InspectorLayout` in `Config.swift`, parsed in `ConfigFile.swift` (tests: `ConfigFileTests.swift`); the Inspector renders both layouts from the same Inspection (`InspectorView`, sidebar-style `List` with `Section(isExpanded:)`). App tests: `ListLayoutTests.swift`.
- Still to check by hand: step 12 of `.scratch/textier-v2/manual-test.txt`.

**2026-10-09, follow-up:** Added the toolbar switch (segmented Tabs/List next to Highlighting) and ⌘L. The config key is the starting layout; the switch overrides it for the session and never writes the config file.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v2/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
