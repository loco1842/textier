# textier v1

Status: done (v1 shipped and verified by hand 2026-10-09)

## Problem Statement

When a developer hits a dense log line (a Laravel/Monolog line with a timestamp, a channel, a level, a message and a large JSON context payload with URLs, file paths and a backtrace), the structure is invisible. To debug it they select the JSON by hand, paste it into a JSON beautifier website, read it there, then copy a file path back out and open it manually in the editor. Each hop is a context switch, and the clipboard is the only tool.

## Solution

textier is a macOS menu bar app. Press a global shortcut anywhere: textier grabs the selected text (or the clipboard) and opens the Panel with the Input. Everything structured in it is highlighted as a Match: datetimes, JSON objects and arrays, URLs, file paths. Click a Match for its Actions; double-click runs the first one. JSON opens in a Match Window with an interactive JSON Viewer: an order-preserving tree, expand/collapse, copy value / key / key path, inline parsing of JSON escaped inside string values, and the URLs and paths inside it clickable again. File paths open in the user's editor at the line. Patterns are configurable in a JSON file that textier writes out with its Presets on first launch and hot-reloads on save.

## User Stories

### Capture and the Panel

1. As a developer, I want to press a global shortcut from any app, so that textier opens with my current selection without me copying it first.
2. As a developer, I want textier to fall back to the clipboard when nothing is selected, so that the shortcut still works after a manual ⌘C.
3. As a developer, I want to be asked for the Accessibility permission the first time the shortcut needs it, so that I understand why textier wants it and can grant it once.
4. As a developer, I want the Panel to be a floating, resizable, centered window, so that wide log lines are readable.
5. As a developer, I want to dismiss the Panel with Esc, so that it gets out of the way as fast as it appeared.
6. As a developer, I want pressing the shortcut while the Panel is open to re-capture and replace the Input, so that the shortcut always means "look at this".
7. As a developer, I want to edit the Input directly in the Panel, so that I can trim noise or paste something else.
8. As a developer, I want Matches to update live as I edit, so that I get instant feedback while tuning text or a regex.
9. As a developer, I want text that isn't part of any Match to be plain, selectable text, so that the Panel still behaves like a text view.

### Matches and Actions

10. As a developer, I want datetimes highlighted, so that I can see when a line happened at a glance.
11. As a developer, I want JSON objects and arrays highlighted wherever they appear in the Input, so that I can find the payload inside a log line.
12. As a developer, I want URLs highlighted, so that I can open them without selecting them.
13. As a developer, I want absolute and `~/` file paths highlighted, with an optional `:line` or `:line:col` suffix, so that I can jump into code.
14. As a developer, I want only the outermost Match highlighted when Matches nest, so that the Panel stays readable.
15. As a developer, I want the longest Match to win when two Patterns overlap, with config order as the tie-break, so that detection is predictable.
16. As a developer, I want to click a Match and see a menu of its Actions, so that a stray click never does anything destructive.
17. As a developer, I want to double-click a Match to run its first Action, so that the common case is one gesture.
18. As a developer, I want to copy a Match as-is, so that I can paste it elsewhere.
19. As a developer, I want to open a Match in a Match Window, so that I can look at it on its own.
20. As a developer, I want to open a URL Match in my default browser, so that I can follow it immediately.
21. As a developer, I want to open a file path Match in my editor at the right line, so that I land on the code that logged it.
22. As a developer, I want to copy a JSON Match beautified, so that I can paste readable JSON into a ticket or a chat.
23. As a developer, I want each Preset to ship with a sensible first Action (JSON → open, URL → open-url, file path → open-file, datetime → copy), so that double-click does the obvious thing.

### Match Windows and the JSON Viewer

24. As a developer, I want a Match Window to be a normal window, so that I can move it, resize it and keep it open while I work.
25. As a developer, I want to open many Match Windows at once, so that I can compare payloads.
26. As a developer, I want a Match Window to detect Matches inside its own content again, so that URLs and paths inside a JSON payload are clickable.
27. As a developer, I want JSON shown as a tree in the JSON Viewer by default, so that I can explore nested structure instead of reading braces.
28. As a developer, I want to toggle the JSON Viewer between tree and beautified text, so that I can read or copy whichever form suits the moment.
29. As a developer, I want the tree to preserve the original key order, so that it reads the way it was logged.
30. As a developer, I want beautified JSON to use 2-space indentation and preserve key order, so that it matches what I'd write by hand.
31. As a developer, I want nodes expanded to depth 2 on open, with arrays longer than 20 items collapsed, so that small payloads are fully visible and large ones don't flood the window.
32. As a developer, I want to expand or collapse everything under a node, so that I can drill into one branch quickly.
33. As a developer, I want to copy a node's value (a scalar, or a subtree as JSON), so that I can take exactly the part I need.
34. As a developer, I want to copy a node's key, so that I can search for it in code.
35. As a developer, I want to copy a node's key path (such as `backtrace[0].file`), so that I can reference the location precisely.
36. As a developer, I want string values that are themselves JSON to be parseable inline into a nested subtree, so that a Monolog `context` payload is readable without opening another window.
37. As a developer, I want an escaped-JSON string value to also be openable in its own Match Window, so that I can isolate it when it's large.
38. As a developer, I want string values that are URLs or file paths to carry their open Actions inside the tree, so that the backtrace is one click from my editor.

### Configuration

39. As a developer, I want textier to write `~/.config/textier/config.json` with all Presets on first launch, so that I edit a working example instead of reading documentation.
40. As a developer, I want to add my own regex Pattern to the config, so that textier highlights things specific to my stack.
41. As a developer, I want to enable, disable, copy or edit a Preset, so that the defaults bend to my needs without me rewriting them.
42. As a developer, I want to enable or disable a Built-in Pattern, so that I can turn JSON detection off if I ever need to.
43. As a developer, I want each Pattern to declare its name, regex (or built-in id), enabled flag, Action list and optional color, so that one entry fully describes a Pattern.
44. As a developer, I want the Log Level Preset shipped but disabled, so that it's one flag away when I want it.
45. As a developer, I want textier to hot-reload the config when I save it, so that tuning a regex is "save, look at Panel".
46. As a developer, I want a broken regex to skip only that Pattern and warn me, so that one typo doesn't kill all highlighting.
47. As a developer, I want malformed config JSON to be rejected while the last good config stays active, so that textier never runs with nothing.
48. As a developer, I want config warnings shown in the Panel footer and as a badge on the menu bar icon, so that I notice without digging into logs.
49. As a developer, I want to set the global shortcut in the config, so that I can avoid conflicts with my other tools.
50. As a developer, I want to set an `editorCommand` template in the config, so that any editor can be used.
51. As a developer, I want textier to fall back to my login shell's `$EDITOR` when no `editorCommand` is set, so that my existing preference is respected even though GUI apps don't inherit shell exports.
52. As a developer, I want known GUI editors (`cursor`, `code`, `zed`, `subl`) to receive the correct line-number flag automatically, so that `open-file` lands on the line without me writing a template.
53. As a developer, I want `cursor -g {path}:{line}` as the final default, so that textier works for me out of the box.

### Menu bar

54. As a developer, I want a menu bar icon with Open Panel, Open Config File, Reload Config and Quit, so that the essentials are reachable without the shortcut.
55. As a developer, I want Open Config File to use the same editor resolution as `open-file`, so that it opens where I expect.

### Build and run

56. As a developer, I want to build and test textier from the command line with SwiftPM, so that I (and an agent) never depend on Xcode to make progress.
57. As a developer, I want a script that assembles the `.app` bundle from the built binary, so that I can put textier in my menu bar without a project file.
58. As a developer, I want the detection core unit-tested, so that Pattern and JSON behaviour is locked down independently of the UI.

## Implementation Decisions

Vocabulary follows `CONTEXT.md`. ADR-0001 (native Swift) and ADR-0002 (own JSON parser) apply throughout.

### Package shape

- One SwiftPM package with two targets plus tests: `TextierCore` (library, Foundation only, no AppKit/SwiftUI imports) and `Textier` (executable, SwiftUI with AppKit where needed). A bundling script turns the executable into a `.app` with an `Info.plist` marking it as a menu bar agent (no Dock icon).
- Minimum deployment target macOS 15. Swift 6 language mode.
- SwiftPM is the source of truth; Xcode-beta is used only when signing, entitlements or debugging require it. No project file is committed.
- Dependencies are kept to zero if practical; a global-hotkey helper package is acceptable if the Carbon/CGEvent route proves fragile.

### TextierCore: detection

- `Config` holds an ordered list of Patterns, the shortcut, and the optional `editorCommand`. A Pattern is one of: Built-in (identified by id: `json`, `escaped-json`), Preset or User Pattern (both regex-backed; the distinction is only whether textier wrote it). Each carries `name`, `enabled`, `actions` (ordered; first is the default Action), optional `color`.
- The Action vocabulary is a closed enum: `copy`, `open`, `copy-pretty`, `open-url`, `open-file`. Config validation rejects unknown Action names with a warning.
- Detection is one pure function from (Input text, Config) to a list of top-level Matches. A Match has a range in the Input, the Pattern that produced it, its Action list, and child Matches found inside it. Regex Patterns run over the whole Input (not per line) with the regex anchored to nothing; multi-line JSON is detected by the JSON scanner, not by regex.
- Overlap rule: candidates are collected from all enabled Patterns; when two candidates overlap without one containing the other, the longer wins, tie broken by Pattern order in the Config. When one contains the other, the inner becomes a child of the outer. Only top-level Matches are highlighted in the Panel; children surface in the Match Window.
- Default regex scope for Presets: datetime (`YYYY-MM-DD` with optional `T`/space time, fractional seconds, `Z`/offset; and 10/13-digit Unix epoch as a whole word); URL (`http`/`https` schemes only, terminated by whitespace or a closing quote/bracket); file path (absolute `/…` or `~/…`, optional `:line[:col]`); log level (PSR-3 set, whole word, disabled by default).

### TextierCore: JSON

- An ordered JSON value model (object entries as an ordered array of key/value pairs) with its own scanner, parser and pretty-printer, per ADR-0002.
- The JSON Built-in Pattern scans the Input for every `{` or `[` and attempts a parse from there; a successful parse yields a Match and scanning resumes after it. Failed parses advance by one character. Two candidates are skipped as noise: a `[` directly after an identifier character or a closing bracket (index syntax such as `items[0]`, `call()[0]`), and empty `{}` / `[]`.
- The `escaped-json` Built-in Pattern applies to JSON string values: a string value whose unescaped content parses as a JSON object or array is marked as an escaped-JSON node. In the JSON Viewer this node offers inline parsing (replace the string with a nested subtree) and the `open` Action.
- Pretty-printing: 2-space indent, key order preserved, string escapes normalised, no trailing whitespace.
- Key paths use dot notation for object keys and bracket indices for arrays (`backtrace[0].file`); keys that aren't plain identifiers are bracket-quoted.

### TextierCore: config

- Location `~/.config/textier/config.json`. On first launch (file absent) textier writes the full Preset list, the default shortcut and an empty `editorCommand`, so the file documents itself.
- Loading returns a Config plus warnings. A Pattern with an invalid regex or unknown Action is dropped with a warning; the rest of the file loads. A `color` that isn't `#RRGGBB` or `#RRGGBBAA` warns and the Pattern loads without a color; a valid one tints that Pattern's highlight. Malformed JSON yields a single fatal warning and the previous Config remains in effect.
- The app watches the file and reloads on change; a Reload Config menu item triggers the same path.

### TextierCore: editor command

- A pure resolver takes the config template, the resolved `$EDITOR` string (or nil), a path and an optional line, and returns an argument vector. Precedence: config `editorCommand` (placeholders `{path}`, `{line}`) → `$EDITOR` with known GUI editors (`cursor`, `code` → `-g {path}:{line}`; `zed`, `subl` → `{path}:{line}`), unknown editors → `{editor} {path}` → default `cursor -g {path}:{line}`. Terminal editors (`vi`, `vim`, `nvim`, `nano`, …) in `$EDITOR` are skipped for the default, since textier runs the editor without a terminal.
- The app resolves `$EDITOR` once at launch by running the user's login shell non-interactively and caches the value.

### Textier app

- Menu bar presence via `MenuBarExtra`, with menu items Open Panel, Open Config File, Reload Config, Quit. A warning badge appears on the icon while config warnings exist.
- Global shortcut, default ⌃⌥T, registered from Config. On press: if the frontmost app has a selection, simulate ⌘C and wait up to ~200 ms for the pasteboard change count to move; if it doesn't, read the existing pasteboard. The user's prior pasteboard contents are restored after a simulated copy. The Accessibility permission is requested the first time simulation is attempted.
- The Panel is a floating, centered, resizable `NSPanel`-style window hosting an editable text view. Highlighting is rendered as attributed text over the Input; a debounced re-detection runs on each edit. A single click on a Match shows a menu of its Actions; double-click runs the first. Esc closes the Panel. Pressing the shortcut while open re-captures and replaces the Input; when textier itself is frontmost there is no other app's selection, so the re-capture reads the clipboard. A footer line shows the current config warnings when any exist.
- A Match Window is a standard window. For a JSON Match it hosts the JSON Viewer with a tree/text toggle (tree default); for other Matches it shows the Match text with nested Matches highlighted. Many Match Windows may be open.
- JSON Viewer tree: nodes expanded to depth 2 on open, arrays longer than 20 items collapsed; per-node Actions copy value / copy key / copy key path / expand all / collapse all; escaped-JSON nodes offer parse-inline and open; string values that are URL or file-path Matches carry `open-url` / `open-file` (only regex Patterns whose Actions include one of those apply, so a datetime string isn't a link). The root is a row of its own, so a long root array also starts collapsed. Open Match Windows re-detect when the config reloads.
- `open-url` uses the system default browser. `open-file` runs the resolved editor command as a subprocess; if it can't launch or exits non-zero, the file opens with macOS `open` and a warning shows in the footer and badge until the next working launch or reload; `open` on a non-JSON Match opens a plain Match Window.

## Testing Decisions

- A good test drives a public `TextierCore` seam with realistic text and asserts on the returned structure or string, never on internal helpers. The canonical fixture is the Laravel/Monolog line from the grilling session; tests should prefer such real-world lines over synthetic minimal strings, adding minimal strings only to isolate one rule.
- Primary seam: detection. Tests cover each Preset's scope (positives and near-miss negatives), JSON objects and arrays embedded mid-line, multi-line JSON, nesting (URL inside JSON becomes a child), overlap (longest wins, then config order), disabled Patterns producing nothing, and Action lists per Match including first-Action order.
- JSON seam: round-trip parse → pretty-print on ordered fixtures, key-order preservation, escape handling, escaped-JSON string detection and unescaping, key-path generation including non-identifier keys and array indices, and rejection of invalid JSON without crashing the scanner.
- Config seam: first-launch default emission is itself valid and loads back identically; bad regex is dropped with a warning while others load; unknown Action is dropped with a warning; malformed JSON produces a fatal warning and no Config.
- Editor command seam: every branch of the precedence chain, placeholder substitution, and nil line handling.
- The `Textier` app target has no automated tests in v1; it is verified manually against the done scenario.
- Tests run with `swift test`. There is no prior art in the repo; these are the first tests.

## Out of Scope

- Datetime conversion (`convert-time`), search/filter in the JSON Viewer, Launch at Login.
- Pairing separate `"file"` and `"line"` JSON keys into one `open-file` target.
- Distribution: signing, notarization, auto-update, App Store, anyone other than the author.
- An in-app settings UI; configuration is file-only.
- History of past Inputs, persistence of Panel content between launches.
- Per-user expansion depth or array-collapse thresholds in the JSON Viewer.
- Platforms other than macOS 15+.
- Configurable colors beyond the optional per-Pattern `color` field.

## Further Notes

- Human step before any `xcodebuild`-dependent work: `sudo xcode-select -s /Applications/Xcode-beta.app` (the machine currently points at Command Line Tools). `swift build` does not need it. Plain `swift test` does: under Command Line Tools the Swift Testing macro plugin is not found once the test target has more than one file. Until the switch is made, run `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`.
- The done scenario for v1: select the Monolog log line in any app, press ⌃⌥T, the Panel opens with datetime, JSON, URL and file paths highlighted; double-click the JSON, a Match Window opens with the tree; click a backtrace `file` value, Cursor opens that file; add a User Pattern in the config, save, and see it highlighted in the Panel without restarting.
- Glossary: `CONTEXT.md`. Decisions: `docs/adr/0001-native-swift-app.md`, `docs/adr/0002-own-json-parser.md`.
