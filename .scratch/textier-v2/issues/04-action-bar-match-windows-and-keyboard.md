# 04: Action bar, Match Windows and keyboard

**What to build:** Actions move into the Inspector. An Action bar above the detail area shows the selected entry's Actions as buttons, the first emphasized, plus Copy and Pop Out; JSON entries show Copy (raw) and Copy Beautified as separate buttons regardless of `copyJSON`; Plain Text entries show Copy only. The `open` Action is titled "Open in Window" (its config name stays `open`). A Match Window is redefined as the Inspector's view of one entry, popped out: the Action bar plus the detail view, no tabs; it opens from Open in Window, Pop Out or ⌘⇧P, many can be open at once, and they follow config reloads. Keyboard: Return or a double-click on a list row runs the first Action; Tab/Shift-Tab move focus between the Input and the Inspector; ⌘1–⌘9 switch tabs; ↑/↓ move through the list.

Spec: `.scratch/textier-v2/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 01 (Panel and Inspector skeleton)

**Status:** done

- [x] Selecting the URL entry shows Open in Browser (emphasized), Copy and Pop Out; Open in Browser opens it
- [x] Selecting a file path shows Open in Editor first; Return opens it in the editor
- [x] The JSON entry shows Open in Window, Copy Beautified, Copy and Pop Out; Open in Window opens a Match Window with the Action bar and detail view
- [x] Plain Text entries show only Copy
- [x] ⌘⇧P pops out the selected entry; two Match Windows can be open at once and follow a config reload
- [x] Tab/Shift-Tab, ⌘1–⌘9 and ↑/↓ work as described

## Comments

**2026-10-09, implementation:** Built and committed; unit tests pass. "Copied" is a small label by the pointer for every copy (Input clicks, Action bar, detail rows, node toolbar). Pop Out isn't offered inside a Match Window (it would duplicate the window).
- Automated: the matching suites in `Tests/TextierAppTests` cover the acceptance criteria in-process. Still to check by hand: steps 6, 11 of `.scratch/textier-v2/manual-test.txt`.

**2026-10-09, change after review by the user:** Pop Out and Open in Window both open a Match Window, so JSON showed the same thing twice, and a Match Window offered Open in Window on itself (each click opened another identical window). Now Pop Out appears only when the entry has no `open` Action (JSON: Open in Window, Copy Beautified, Copy; URL: Open in Browser, Copy, Pop Out), and a Match Window never offers to open itself. This deliberately narrows story 67 ("Copy and Pop Out always in the Action bar"). ⌘⇧P still pops out any entry.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v2/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
