# 02: Global shortcut and selection capture

**What to build:** Pressing ⌃⌥T in any app opens the Panel with the current selection as the Input. textier simulates ⌘C, waits up to ~200 ms for the pasteboard change count to move, and reads the new contents; if nothing changed (no selection), it reads the existing pasteboard instead. The user's previous pasteboard contents are restored after a simulated copy. The Accessibility permission is requested the first time a simulated copy is attempted, with a short explanation. Pressing the shortcut while the Panel is already open re-captures and replaces the Input. Esc closes the Panel. The shortcut is a hard-coded default in this ticket; ticket 05 makes it configurable.

Spec: `.scratch/textier-v1/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 01 (Walking skeleton)

**Status:** done

- [x] ⌃⌥T registered as a global shortcut while textier runs; works when another app is frontmost
- [x] With text selected in another app, the shortcut opens the Panel with that text as Input
- [x] With nothing selected, the shortcut opens the Panel with the current clipboard text
- [x] After a simulated copy the user's prior pasteboard contents are restored
- [x] Accessibility permission is requested once, on first simulated copy, with an explanation
- [x] Pressing the shortcut with the Panel open replaces the Input with a fresh capture
- [x] Esc dismisses the Panel

## Comments

**2026-10-08, implementation:** Built and committed. `swift build`, `swift test` (with `DEVELOPER_DIR` set to Xcode-beta) and `scripts/bundle.sh` all pass.
- `HotKey` (`Sources/Textier/HotKey.swift`) registers ⌃⌥T with Carbon `RegisterEventHotKey`. Registering needs no Accessibility permission. `register(_:)` replaces any earlier shortcut, so ticket 05 can call it again on reload. Launching `build/Textier.app` logs no registration error, so Carbon accepted the shortcut. Nobody has pressed it yet: the agent can't send keystrokes to other apps.
- `SelectionCapture` (`Sources/Textier/SelectionCapture.swift`) works in this order: snapshot every pasteboard item and type, post ⌘C, poll `changeCount` for up to 200 ms, read the string, then restore the snapshot. If the pasteboard doesn't change, it reads the existing clipboard. It captures before textier activates, so the selection still belongs to the frontmost app. The posted ⌘C carries explicit `.maskCommand` flags, so the ⌃⌥ still held from the shortcut don't leak into it.
- Accessibility: the first time a capture runs without trust, textier shows an explanation alert, then the system prompt, and records in UserDefaults (`didExplainAccessibility`) that it asked. After that it silently falls back to the clipboard until access is granted. That one capture uses the clipboard.
- Esc closes the Panel, both from the text view (intercepted in `textView(_:doCommandBy:)`, since NSTextView would otherwise start completion) and from the panel itself.
- To check by hand, with `build/Textier.app`, not `swift run`: the Accessibility grant is tied to the binary's identity, and the bundle is ad-hoc signed, so re-grant (remove and re-add it in System Settings → Privacy & Security → Accessibility) after every rebuild. Items still to check: every item above.

**2026-10-08, follow-up:** When a capture falls back to the clipboard because Accessibility isn't granted (including after a rebuild drops the grant), the Panel footer now says so and points to System Settings → Privacy & Security → Accessibility. Check by hand: after a rebuild, without re-granting, press ⌃⌥T and look for the footer note.

**2026-10-08, follow-up (code review):** When the shortcut fires while textier is frontmost (Panel or a Match Window key), it skips the simulated ⌘C and reads the clipboard; before, it copied the Panel's own selection, so a partly selected Input replaced itself with the fragment. Check by hand: select part of the Input in the Panel, press ⌃⌥T, and the Input becomes the clipboard text.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v1/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
