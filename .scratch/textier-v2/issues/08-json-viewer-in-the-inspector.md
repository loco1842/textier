# 08: JSON Viewer in the Inspector

**What to build:** JSON entries show the JSON Viewer in the Inspector and in Match Windows, with a Tree/Text toggle (tree first; Text is the beautified JSON). The JSON Viewer's context menu is replaced by a small toolbar acting on the selected node: Copy Value, Copy Key, Copy Key Path, Expand All, Collapse All. Escaped JSON still parses inline in the tree, and its open action opens a Match Window. URL and file path string values stay clickable with their Actions. Expansion rules from v1 still apply (depth 2, arrays over 20 collapsed, root as a row).

Spec: `.scratch/textier-v2/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 01 (Panel and Inspector skeleton), 04 (Action bar, Match Windows and keyboard)

**Status:** done

- [x] Selecting the Monolog JSON shows the tree in the Inspector with keys in original order and backtrace frames expanded
- [x] The Tree/Text toggle switches to beautified JSON and back
- [x] The node toolbar copies `backtrace[0].file` as a key path, a frame as pretty JSON, and expands/collapses a subtree
- [x] No context menu appears in the tree
- [x] An escaped-JSON value parses inline, collapses back, and its open opens a Match Window
- [x] A backtrace `file` value opens the editor; the `url` value opens the browser
- [x] Popping out the JSON shows the same viewer in a Match Window

## Comments

**2026-10-09, implementation:** Built and committed; unit tests pass. The tree has no menus; the node toolbar above it acts on the selected node (plus a link value's Actions and an escaped-JSON string's Parse Inline / Show as String and Open in Window). Link values open on double-click in the tree and on a single click in Text mode.
- Automated: the matching suites in `Tests/TextierAppTests` cover the acceptance criteria in-process. Still to check by hand: steps 8, 10 of `.scratch/textier-v2/manual-test.txt`.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v2/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
