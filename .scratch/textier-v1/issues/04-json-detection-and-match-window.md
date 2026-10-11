# 04: JSON detection and the Match Window (text mode)

**What to build:** JSON objects and arrays anywhere in the Input become Matches, and `open` shows them beautified in a Match Window. `TextierCore` gains an ordered JSON value model (object entries as an ordered list of key/value pairs) with its own scanner, parser and pretty-printer per ADR-0002; Foundation's `JSONSerialization` is not used for anything the user sees. The `json` Built-in Pattern scans the Input for every `{` or `[`, attempts a parse, yields a Match on success and resumes after it, otherwise advances one character. Multi-line JSON is detected. The JSON Pattern's Actions are `open`, `copy-pretty`, `copy`. A Match Window is a standard window (many may be open) showing the Match: for JSON, the pretty-printed text (2-space indent, key order preserved) with nested Matches detected again and highlighted, clickable with their own Actions; for other Matches, the raw text with nested Matches highlighted. `copy-pretty` copies the beautified JSON. URLs and file paths inside the JSON are children of the JSON Match in the Panel (hidden there, visible in the Match Window).

Spec: `.scratch/textier-v1/spec.md`. Vocabulary: `CONTEXT.md`. Decisions: ADR-0002.

**Blocked by:** 03 (Presets and overlap/nesting rules)

**Status:** done

- [x] The Monolog fixture's context payload is one JSON Match in the Panel; the URL and file paths inside it are not separately highlighted there
- [x] Double-clicking the JSON Match opens a Match Window with the payload pretty-printed, 2-space indent, keys in original order
- [x] In the Match Window the URL and file paths inside the JSON are highlighted and offer their Actions
- [x] `copy-pretty` puts the beautified JSON on the pasteboard
- [x] A top-level JSON array is detected; invalid JSON-looking text (`{not json}`) is not
- [x] JSON spanning several lines is detected as one Match
- [x] Several Match Windows can be open at once
- [x] Unit tests: parse → pretty-print round trip on ordered fixtures, key-order preservation, string escape handling, embedded detection mid-line and multi-line, scanner survives invalid candidates

## Comments

**2026-10-08, implementation:** Built and committed. 60 tests pass (`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`); `scripts/bundle.sh` builds.
- JSON API in `TextierCore` (`Sources/TextierCore/JSON.swift`), no `JSONSerialization`:
  - `JSONValue`: `.object([JSONEntry])`, `.array([JSONValue])`, `.string(String)`, `.number(String)` (source text, so `1.50` stays `1.50`), `.bool(Bool)`, `.null`. `JSONEntry` has `key` and `value`; duplicate keys are kept in order.
  - `JSONValue.parse(_:) -> JSONValue?` parses a whole document (surrounding whitespace allowed), strict RFC 8259. Nesting deeper than 512 fails instead of overflowing the stack.
  - `JSONValue.scan(_:at:) -> (value, length)?` parses one value from a UTF-16 offset.
  - `prettyPrinted`: 2-space indent, key order kept, `{}`/`[]` for empty containers, only `"`, `\` and control characters escaped (`\/` becomes `/`), no trailing whitespace or newline.
- The `json` Built-in runs in `detect`. On the Monolog line the top-level Matches are the datetime and the JSON payload; the URL and the six file paths are its children, so the Panel doesn't highlight them.
- `detectNested(in:config:)` (new, `TextierCore`) is what a Match Window highlights: it detects over the window's text and swaps a Match that spans all of it (the shown Match itself) for its children. Without it, the pretty JSON would be one Match again and its URL and paths would stay hidden.
- Match Window: `MatchWindowController.open(_ match:)` in `Sources/Textier/MatchWindow.swift`, a standard titled/closable/resizable/miniaturizable window. Open windows are kept in a list until they close, and new ones cascade. JSON objects and arrays show beautified, anything else raw. The text is read-only and selectable, and detects with `AppConfig.current` when the window opens. Ticket 07 can replace the text view with the JSON Viewer tree there.
- `open` opens a Match Window. `copy-pretty` copies the beautified JSON (or the raw text if it doesn't parse). `open-file` still does nothing.
- Known behaviour: following the spec, any valid JSON starting at `{` or `[` is a Match, so `[0]` in `items[0]` or an empty `[]` gets highlighted. If that's noisy, a minimum size or "not right after an identifier" rule would fix it.
- UX issue to decide: the Panel is a floating panel and a Match Window is a normal window, so a Match Window opened from the Panel shows up behind it. It's larger and cascades, so part of it shows. Ordering the Panel out (or dropping it to the normal level) when a Match Window opens would fix it, but that's in `PanelController.swift`, which this ticket doesn't own.
- Still to check by hand in `build/Textier.app`:
  - the Monolog payload is one highlighted Match, with no separate URL or path highlights
  - double-clicking it opens a Match Window with 2-space pretty JSON in the logged key order
  - the URL and paths in the window are highlighted and offer their Actions
  - Copy Beautified puts pretty JSON on the pasteboard
  - several Match Windows can be open at once

**2026-10-08, follow-up (user decision):** JSON detection skips index syntax (a `[` directly after an identifier character, `)` or `]`, as in `items[0]` or `matrix[1][2]`) and empty `{}` / `[]`, so they aren't highlighted. JSON inside an index expression, as in `lookup[{"id":7}]`, is still found. The spec's JSON section records the rule.

**2026-10-08, follow-up:** The Panel now floats only while it is the key window, so a Match Window opened from it comes to the front. Check by hand: double-click the JSON Match; the Match Window should appear in front of the Panel, and clicking the Panel should bring it back to the front.

**2026-10-08, follow-up (code review):** Open Match Windows follow config reloads: text mode re-detects with the reloaded Config, and the JSON Viewer drops its cached URL/file-path string Matches and reloads (keeping expansion). Check by hand: with a Match Window open, disable the `url` Preset and save; the URL stops being highlighted in that window.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v1/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
