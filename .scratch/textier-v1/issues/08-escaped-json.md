# 08: Escaped JSON

**What to build:** JSON hidden inside a JSON string value becomes readable. `TextierCore` gains the `escaped-json` Built-in Pattern: a string value whose unescaped content parses as a JSON object or array is marked as an escaped-JSON node. In the JSON Viewer such a node shows a parse-inline affordance that replaces the string with a nested subtree (collapsible back to the string), and offers `open`, which opens the unescaped JSON in its own Match Window with the full JSON Viewer. Nested escaped JSON (a payload inside a payload) works recursively. The Pattern appears in the config file as a Built-in entry and can be disabled.

Spec: `.scratch/textier-v1/spec.md`. Vocabulary: `CONTEXT.md`. Decisions: ADR-0002.

**Blocked by:** 07 (JSON Viewer tree)

**Status:** done

- [x] A fixture with `"payload":"{\"a\":1,\"b\":[1,2]}"` shows the `payload` node with a parse-inline affordance
- [x] Parsing inline replaces the string with a subtree `a: 1`, `b: [1, 2]` in that order; it can be collapsed back to the string
- [x] `open` on the node opens a Match Window with the unescaped JSON in the JSON Viewer
- [x] Escaped JSON two levels deep parses inline at both levels
- [x] A string that merely contains braces but isn't valid JSON is not marked
- [x] Disabling `escaped-json` in the config removes the affordance after reload
- [x] The first-launch config file includes the `escaped-json` Built-in entry, enabled
- [x] Unit tests cover escaped-JSON detection, unescaping, nested escaping, and non-JSON strings with braces

## Comments

**2026-10-08, implementation:** Built and committed. 134 tests pass under `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`; `swift build` and `scripts/bundle.sh` succeed. No UI was driven.

- Core API:
  - `JSONValue.escapedJSON -> JSONValue?` is the parsed JSON when a string value's unescaped content parses as a non-empty object or array. It returns nil for strings that only contain braces (`{not json}`, `use {name} here`), for scalars (`"1"`, `"\"x\""`), for empty `{}` / `[]` (matching the noise rule for the Input), and for anything that isn't a string. Surrounding whitespace inside the string is allowed.
  - `Builtin.escapedJSON` is name `escaped-json`, kind `.builtin(.escapedJSON)`, Actions `[open]`. It comes right after `json` in `Config.default`, so the first-launch file has the entry enabled.
  - `Config.escapedJSONPattern` is that Pattern when it's in the Config and enabled, otherwise nil.
  - Detection over the Input still yields nothing for it, because it applies only to string values in the JSON Viewer.
- **An older config file without the `escaped-json` entry has it off.** A Pattern the file doesn't list is absent, as with any other entry, because the file is the Config. To turn it on, add `{ "name": "escaped-json", "builtin": "escaped-json", "enabled": true, "actions": ["open"] }` after the `json` entry, or delete the file so textier writes the defaults again.
- JSON Viewer:
  - An escaped-JSON string node shows a `{…}` badge before the string and has a disclosure triangle. The parsed JSON's entries are the node's children, so expanding the node parses it inline and its value cell turns into `{2 keys} parsed from string`. Collapsing it shows the string again.
  - The disclosure triangle, double-click, and the context menu's Parse Inline / Show as String all do the same thing. Expand All and Collapse All also parse and unparse nested payloads.
  - The context menu also has the Pattern's Actions (Open) on the unescaped JSON. Open opens a Match Window titled `escaped-json` showing the full JSON Viewer.
  - Copy Value copies the string while collapsed and the pretty JSON while parsed inline. Key paths run through the string's key (`payload.b[1]`).
  - Nested escaped JSON is the same rule one level down.
  - Escaped strings start collapsed, as strings, when a window opens.
  - This replaces ticket 07's `JSONNode.content` / `replaceContent(_:)` with `content(parsedInline:)`. Swapping a node's children would have changed outline items under the outline view.
- Config reload: `ConfigStore` now also posts `ConfigStore.didReload`. Open JSON Viewers reload their tree on it and keep their expanded nodes, so disabling `escaped-json` removes the affordance (and any inline parse) from open windows as well as new ones.
- Still to check by hand:
  - The `payload` node of a window opened on `{"payload":"{\"a\":1,\"b\":[1,2]}"}` shows the badge.
  - Expanding it shows `a: 1`, `b: [1 2]` in that order, and collapsing it shows the string again.
  - Open from its menu opens a viewer window.
  - A two-level payload parses inline at both levels.
  - Setting `"enabled": false` on `escaped-json` and saving removes the badge in an open window.


**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v1/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
