# 07: JSON Viewer tree

**What to build:** A Match Window for a JSON Match opens in the JSON Viewer: an interactive, order-preserving tree, with a toggle to the beautified text mode from ticket 04 (tree is the default). On open, nodes are expanded to depth 2 and arrays longer than 20 items are collapsed regardless of depth. Each node offers Actions: copy value (the scalar, or the subtree as pretty JSON), copy key, copy key path (dot notation for object keys, bracket indices for arrays, bracket-quoted keys that aren't plain identifiers, e.g. `backtrace[0].file`), expand all and collapse all under the node. String values that are URL or file path Matches carry `open-url` / `open-file` in the tree, so a backtrace `file` value is one click from the editor. `TextierCore` provides key-path generation for the ordered JSON model.

Spec: `.scratch/textier-v1/spec.md`. Vocabulary: `CONTEXT.md`. Decisions: ADR-0002.

**Blocked by:** 04 (JSON detection and Match Window), 06 (`open-file` and editor resolution)

**Status:** done

- [x] Opening the Monolog fixture's JSON Match shows a tree with keys in original order; the 5-frame `backtrace` array is expanded, its frames' children visible (depth 2)
- [x] A fixture with a 25-item array shows that array collapsed on open
- [x] Tree/text toggle switches to the pretty-printed text and back; `copy-pretty` is available in text mode
- [x] Copy value on `backtrace[0]` copies that frame as pretty JSON; on a scalar copies the raw value
- [x] Copy key path on the first frame's `file` yields `backtrace[0].file`
- [x] Expand all / collapse all act on the selected node's subtree
- [x] Clicking the `url` string value offers `open-url`; clicking a backtrace `file` value offers `open-file` and opens the file in the editor
- [x] Unit tests cover key-path generation including array indices and non-identifier keys

## Comments

**2026-10-08, implementation:** Built and committed. `swift build` and `scripts/bundle.sh` succeed, and all 119 tests pass under `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`. No UI was driven.
- Core (`Sources/TextierCore/JSONTree.swift`):
  - `keyPath([JSONPathComponent])`, where a component is `.key(String)` or `.index(Int)`. Identifier keys (`[A-Za-z_$][A-Za-z0-9_$]*`) use dot notation, indices use brackets, and any other key is bracket-quoted as a JSON string (`headers["content-type"]`).
  - `JSONValue.isExpandedOnOpen(atDepth:)`. The root is depth 0, so its entries are depth 1. Containers at depth 2 or less are expanded, which shows rows down to depth 3: `backtrace` and each of its frames are open, so the frames' `file`/`line`/`function` are visible. Arrays with more than 20 items start collapsed at any depth.
  - `JSONValue.copyText`: a scalar's raw value (a string unquoted, a number as its source text) or a container as pretty JSON.
  - `JSONValue.isContainer` and `subscript(key:)`.
  - `stringValueMatch(_:config:)`: the Match a string value is in its entirety. Only regex Patterns apply, so escaped JSON stays the `escaped-json` Pattern's job (ticket 08).
- App (`Sources/Textier/JSONViewer.swift`, `MatchWindow.swift`):
  - A JSON Match Window opens in the tree, with a Tree/Text toggle and a Copy Beautified button. Text mode is the ticket 04 view, with nested Matches highlighted.
  - The tree is an `NSOutlineView` with Key and Value columns. The root is not a row; its entries are the top-level rows.
  - Every row's context menu has Copy Value, Copy Key, Copy Key Path and, on containers, Expand All and Collapse All for that node's subtree.
  - URL and file path string values are link-styled. A single click shows their Actions (Open in Browser / Open in Editor, Copy); double-click runs the first. Elsewhere, double-click toggles the node.
- Still to check by hand:
  - The Monolog JSON opens as a tree, with keys in order and the backtrace frames expanded.
  - A 25-item array starts collapsed.
  - The Tree/Text toggle works.
  - Copy Value on `backtrace[0]` copies the frame as pretty JSON, and on a scalar copies the raw value.
  - Copy Key Path on the first frame's `file` copies `backtrace[0].file`.
  - Expand All / Collapse All act on the clicked node's subtree.
  - Clicking the `url` value offers Open in Browser; clicking a `file` value offers Open in Editor and opens the file.

**2026-10-08, follow-up (code review):** (1) The root value is now a visible row (key `root`, value `{N keys}` / `[N items]`) and follows the same open rule, so a root array longer than 20 items starts collapsed; an object root starts expanded and the depth-2 rule for its descendants is unchanged (backtrace frames' children still visible). The root row has no Copy Key / Copy Key Path. (2) Only regex Patterns whose Actions include `open-url` or `open-file` make a string value a link (`stringValueMatch`), so datetime strings are plain; a User Pattern declaring either Action still works. Unit tests cover (2); (1) is UI. Check by hand: open a Match Window on a 25-item array and see it collapsed under `root`; a datetime string value isn't link-styled.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v1/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
