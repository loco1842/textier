# 03: Click-to-copy and the Highlighting toggle

**What to build:** Clicking in the Input stops interrupting. With Highlighting on, a click without drag on a highlighted Match copies it (raw text, or beautified JSON for a JSON Match when the new `copyJSON` config key is `"pretty"`; default `"raw"`), shows a brief "Copied", and places the cursor; a drag starting in a Match selects text and copies nothing; a double-click on a Match selects it in the Inspector on its tab; a double-click outside Matches selects a word. Clicking a nested Match's text copies its top-level Match. The Action menu in the Input is removed (and the option-click workaround with it). A Highlighting toggle in the Panel toolbar, also ⌘E, turns off all tints and click behaviour so the Input is plain, editable text; detection and the Inspector keep running. Each capture turns Highlighting on; otherwise it stays where it was left while the Panel is open.

Spec: `.scratch/textier-v2/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 01 (Panel and Inspector skeleton)

**Status:** done

- [x] Clicking the datetime on the Monolog line puts it on the pasteboard and flashes "Copied"; the cursor lands where clicked
- [x] Clicking the JSON copies its raw text; with `"copyJSON": "pretty"` it copies beautified JSON
- [x] Dragging across part of the JSON selects that part and leaves the pasteboard unchanged
- [x] Double-clicking the JSON selects it in the Inspector's json tab; double-clicking a Plain Text word selects the word
- [x] No menu appears on any click in the Input
- [x] ⌘E and the toolbar toggle remove all tints and click behaviour; the Inspector still updates while typing
- [x] A new ⌃⌥T capture starts with Highlighting on
- [x] An unknown `copyJSON` value warns and falls back to raw; unit tests on the config seam cover `copyJSON`

## Comments

**2026-10-09, implementation:** Built and committed; unit tests pass. `InputTextView` copies on a click without drag and hands double-clicks to the Inspector; the Action menu and option-click are gone. ⌘E is handled by the Panel window so it works wherever focus is. `copyJSON` tests are in `ConfigFileTests.swift`.
- Automated: the matching suites in `Tests/TextierAppTests` cover the acceptance criteria in-process. Still to check by hand: steps 3, 4, 11 of `.scratch/textier-v2/manual-test.txt`.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v2/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
