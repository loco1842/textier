# textier v2: Panel and Inspector revamp

Status: done

## Problem Statement

textier v1 finds everything structured in a log line, but the windows it shows them in work against the debugging loop. The Panel is a small text box where every Match looks the same (one blue tint), and the only way to learn what a Match is or does is a click that pops up a menu. Looking at a Match means opening a separate Match Window for each one, so a session leaves a trail of windows, and Matches nested inside JSON (the URL, the six backtrace paths) are invisible until you open their parent. There is no overview of what was found, no way to tell two JSON objects apart without opening both, and the parsed JSON is uncolored text or a bare tree. Editing the Input is awkward because a click on a Match opens a menu instead of placing the cursor.

## Solution

The Panel becomes one larger window: the Input on the left and an Inspector on the right. The Inspector has one tab per Pattern that matched, in the order the Patterns first appear in the Input, plus a Plain Text tab for everything else. Each tab lists every Match of that Pattern, nested ones included, with an index and a one-line preview, and shows the selected Match parsed: JSON in the JSON Viewer with VS Code-style syntax colors, a URL broken into its parts, a datetime converted into the common forms, a file path with its line and whether it exists. In the Input, each Pattern has its own color; a click copies a Match and a double-click jumps to it in the Inspector, and a Highlighting toggle turns all of that off to make the Input plain, easy-to-edit text. Actions live in an Action bar instead of menus. A Match can be popped out into a Match Window to keep it beside another.

## User Stories

### The Panel

1. As a developer, I want the Panel to show the Input and the Inspector side by side, so that I see the raw line and what was found in it at once.
2. As a developer, I want the Panel to open larger by default (about 1100×650), so that a long log line and a JSON tree both fit.
3. As a developer, I want to drag the divider between the Input and the Inspector, so that I can give room to whichever I'm reading.
4. As a developer, I want the Panel to remember its size and divider position between openings, so that I set it up once.
5. As a developer, I want the Panel to stay floating, centered and dismissable with Esc, so that the v1 habits still work.
6. As a developer, I want the Inspector hidden when the Input has no Matches, so that plain text doesn't come with an empty side panel.
7. As a developer, I want the Inspector to come back at its remembered width as soon as a Match appears, so that the layout doesn't jump around.
8. As a developer, I want config warnings and the Accessibility note to stay in the Panel footer, so that nothing I relied on in v1 disappears.

### Highlighting in the Input

9. As a developer, I want each Pattern's Matches tinted in that Pattern's own color, so that I can tell a datetime from JSON from a path at a glance.
10. As a developer, I want every Preset and Built-in Pattern to have a distinct default color, so that the Input is readable without any configuration.
11. As a developer, I want my existing config file, which has no colors, to get the default colors automatically, so that I don't have to edit it after upgrading.
12. As a developer, I want User Patterns without a color to get the next unused palette color, so that my own Patterns are distinguishable too.
13. As a developer, I want to set a Pattern's color in the config as one hex value, so that I can match my editor's colors.
14. As a developer, I want to set a Pattern's color as a light/dark pair, so that it reads well in both appearances.
15. As a developer, I want only top-level Matches highlighted in the Input, so that nested Matches don't turn the line into noise.

### Click, double-click and the Highlighting toggle

16. As a developer, I want a single click on a highlighted Match to copy it, so that grabbing a value is one gesture.
17. As a developer, I want a brief "Copied" confirmation, so that I know the click did something.
18. As a developer, I want that click to also place the cursor, so that the Input still behaves like a text view.
19. As a developer, I want a drag that starts inside a Match to select text as usual without copying, so that I can select part of a Match.
20. As a developer, I want clicking a URL nested inside a JSON Match to copy the whole JSON, so that the behaviour follows what is highlighted.
21. As a developer, I want a click on a JSON Match to copy its raw text by default, so that I get exactly what was logged.
22. As a developer, I want a `copyJSON` config setting that makes that click copy beautified JSON instead, so that I can choose the form I paste most often.
23. As a developer, I want a double-click on a Match to select it in the Inspector, on its tab, so that I can see it parsed.
24. As a developer, I want a double-click outside any Match to select a word as usual, so that Plain Text still edits normally.
25. As a developer, I want no pop-up Action menu in the Input, so that clicking never interrupts me.
26. As a developer, I want a Highlighting toggle in the Panel toolbar, so that I can switch the Input to plain text.
27. As a developer, I want Highlighting off to remove every highlight and click behaviour, so that I can edit the Input freely.
28. As a developer, I want the Inspector to keep updating while Highlighting is off, so that I can edit a line (or tune a regex) and watch the Matches change.
29. As a developer, I want every new capture to start with Highlighting on, so that a fresh capture is ready to look at.
30. As a developer, I want the toggle to stay where I put it while the Panel stays open, so that editing isn't interrupted.
31. As a developer, I want ⌘E to toggle Highlighting, so that I don't need the mouse.

### The Inspector: tabs and lists

32. As a developer, I want one tab per Pattern that matched, so that Matches are grouped by kind.
33. As a developer, I want tabs ordered by where their Pattern first appears in the Input, left to right, so that the tabs read like the line.
34. As a developer, I want each tab to show its Pattern's color dot and its Match count, so that I know what's inside before opening it.
35. As a developer, I want no tab for a Pattern with no Matches, so that the tab bar only shows what was found.
36. As a developer, I want a Plain Text tab, always last, so that the parts of the line that aren't Matches (the log message) are readable too.
37. As a developer, I want each tab to list every Match of its Pattern, nested ones included, so that all six backtrace paths are in one place.
38. As a developer, I want each list row to show the Match's index within its Pattern and a one-line preview, so that I can tell `{"a":"b"}` from `{"c":"d"}` without opening them.
39. As a developer, I want nested Matches tagged with their parent (such as "in json 0"), so that I know where they came from.
40. As a developer, I want selecting a nested Match to select its exact text in the Input, so that I can find it even though it isn't highlighted.
41. As a developer, I want selecting any Match in the Inspector to scroll the Input to it and select it, so that the two sides stay in sync.
42. As a developer, I want the Plain Text tab to list each continuous piece of leftover text as its own entry, trimmed, skipping pieces that are only whitespace or punctuation, so that the log message shows up as one readable entry.
43. As a developer, I want the largest top-level Match (usually the JSON payload) selected when the Panel opens, so that I land on what I came for.
44. As a developer, I want the tab order fixed when the Input is captured or pasted, so that tabs don't reorder while I type.
45. As a developer, I want new Patterns that appear while I edit to add tabs at the end (before Plain Text), and empty tabs to disappear, so that the tab bar stays truthful without jumping.
46. As a developer, I want the selection to move to the nearest Match of the same Pattern when I edit, so that I don't lose my place.
47. As a developer, I want the selection to fall back to the largest top-level Match when its tab disappears, so that something sensible is always selected.

### The Inspector: parsed views

48. As a developer, I want a JSON Match shown in the JSON Viewer, tree first, so that I can explore the structure.
49. As a developer, I want a Tree/Text toggle on JSON, so that I can read or copy the beautified text.
50. As a developer, I want the beautified JSON syntax-colored like in VS Code, so that keys, strings, numbers and literals are easy to tell apart.
51. As a developer, I want the tree's values colored with the same theme, so that both views look like one tool.
52. As a developer, I want URLs and file paths inside JSON to stay clickable in both views, so that the backtrace is still one click from my editor.
53. As a developer, I want the JSON Viewer's node actions (copy value, copy key, copy key path, expand all, collapse all) in a small toolbar for the selected node instead of a context menu, so that there are no menus anywhere.
54. As a developer, I want escaped JSON inside a string value to keep parsing inline in the tree, so that a Monolog `context` payload stays readable.
55. As a developer, I want the escaped-JSON node's open action to open a Match Window, so that I can isolate a large inner payload.
56. As a developer, I want a URL Match shown as its scheme, host, path and one row per query parameter (decoded), so that I can read a long query string.
57. As a developer, I want each URL part and query value copyable, so that I can grab a single parameter.
58. As a developer, I want a datetime Match shown as ISO 8601 UTC, local time with offset, epoch seconds, epoch milliseconds and relative time ("2 days ago"), so that I can compare it with other logs and with now.
59. As a developer, I want each conversion copyable, so that I can paste the form another tool expects.
60. As a developer, I want a datetime without an offset (like Monolog's `2026-10-07 11:17:10`) treated as local time and labelled "assumed local", so that I know what was assumed.
61. As a developer, I want a toggle to treat such a datetime as UTC instead, so that I can read logs from servers that log in UTC.
62. As a developer, I want epoch values always treated as UTC, so that conversions are unambiguous.
63. As a developer, I want a file path Match shown as its path, line (and column), and whether the file exists on this machine, so that I know before I try to open it.
64. As a developer, I want log level Matches, User Pattern Matches and Plain Text entries shown as their text, so that every tab has something to look at.

### Actions and the Action bar

65. As a developer, I want the selected Match's Actions as buttons in an Action bar at the top of the Inspector, so that I can see what I can do with it.
66. As a developer, I want the first Action emphasized, so that the default is obvious.
67. As a developer, I want Copy and Pop Out always in the Action bar, so that the common things are always there.
68. As a developer, I want Copy (raw) and Copy Beautified as separate buttons on JSON, whatever `copyJSON` says, so that each button always does what it says.
69. As a developer, I want Plain Text entries to offer only Copy, so that the bar never shows Actions that don't apply.
70. As a developer, I want Return or a double-click on a list row to run the first Action, so that the default is one keystroke.
71. As a developer, I want the `open` Action called "Open in Window", so that its name says what it does now.

### Match Windows

72. As a developer, I want Pop Out (and ⌘⇧P) to open the selected Match in a Match Window, so that I can keep it beside another one.
73. As a developer, I want a Match Window to show the Action bar and the same parsed view as the Inspector, with no tabs, so that it is the Inspector's view of one Match.
74. As a developer, I want to have many Match Windows open at once, so that I can compare payloads.
75. As a developer, I want Match Windows to follow config reloads as they do in v1, so that colors and Patterns stay current.

### Keyboard

76. As a developer, I want Tab and Shift-Tab to move focus between the Input and the Inspector, so that I can work without the mouse.
77. As a developer, I want ⌘1 to ⌘9 to switch Inspector tabs, so that I can jump to a Pattern.
78. As a developer, I want ↑ and ↓ to move through the Inspector's list, so that I can step through Matches.

### Themes

79. As a developer, I want GitHub Light and GitHub Dark used by default, following the system appearance, so that colors fit macOS without setup.
80. As a developer, I want to point the config at my own VS Code theme files for light and dark, so that textier looks like my editor.
81. As a developer, I want a broken or missing theme file to warn me and fall back to the default theme, so that a typo never leaves me without colors.

## Implementation Decisions

Vocabulary follows `CONTEXT.md` (new this version: Inspector, Plain Text; redefined: Panel, Match Window, JSON Viewer). ADR-0001 (native Swift), ADR-0002 (own JSON parser) and ADR-0003 (native syntax coloring with VS Code themes, not Shiki) apply.

### TextierCore: detection and config

- `detect` is unchanged in behaviour. A Match's color becomes resolved: the Pattern's configured color, or else its palette default. Colors are a light/dark pair (one hex value fills both).
- A built-in palette assigns default colors: Presets and Built-ins by name, User Patterns the next unused palette color in Config order. An explicit `color` always wins.
- `color` in the config file accepts `"#RRGGBB"`, `"#RRGGBBAA"` or `{"light": "#…", "dark": "#…"}`. Invalid values warn and fall back to the palette (v1 behaviour, with the palette replacing the old blue).
- New optional config keys: `theme` (`{"light": path, "dark": path}` to VS Code theme JSON files, relative to the config file's folder or absolute) and `copyJSON` (`"raw"` default, or `"pretty"`). First-launch emission writes `copyJSON` and the Presets' explicit colors so the file documents itself; `theme` is omitted when default. Unknown values warn and fall back to the default.
- The `open` Action keeps its raw name `open` in the config; only its title changes to "Open in Window".

### TextierCore: Inspection (new seam)

- One pure function produces everything the Inspector shows: `inspect(Input, Config, previous: Inspection?, now, timeZone, fileExists) → Inspection`. `fileExists` is a lookup the caller passes in, so tests never touch the disk.
- An Inspection holds ordered tabs. A Pattern tab carries the Pattern's name, resolved color, and its entries; the Plain Text tab is always last and only present when Plain Text entries exist. The Inspector is shown only when at least one Pattern tab exists.
- An entry carries: its index within its tab, its one-line preview (whitespace collapsed, truncated), its UTF-16 range in the Input, its Actions, the parent tag for a nested Match (Pattern name and index of the enclosing top-level Match), and its parsed detail.
- Parsed detail is one of: JSON (the ordered JSON value), URL (scheme, host, port, path, ordered decoded query parameters, fragment), datetime (the instant; whether the zone was assumed local; ISO 8601 UTC, local with offset, epoch seconds, epoch milliseconds, relative to `now`; and the same set when re-read as UTC), file path (path, line, column, exists), or text.
- Tab order without `previous`: by the position of each Pattern's first Match (nested Matches count at their own position). With `previous`: existing tabs keep their order, new tabs are appended before Plain Text, empty tabs are dropped.
- Selection: without `previous`, the largest top-level Match. With `previous` and a previous selection, the Match of the same Pattern whose range is nearest the old one; if that tab is gone, the largest top-level Match.
- Plain Text entries are the gaps between top-level Matches, trimmed, excluding gaps that are only whitespace or punctuation.
- Inspection runs on the same debounced cadence as detection in v1, and after config reloads.

### TextierCore: syntax coloring (new seam)

- `Theme.load(data)` reads a VS Code theme JSON (its `tokenColors` scope rules and editor foreground/background) and resolves colors for the scopes JSON uses (keys, strings, numbers, booleans, null, punctuation), following TextMate scope-selector precedence closely enough for those scopes.
- `colorize(JSON text, theme) → [colored range]`, each with a UTF-16 range, a color and a font style, built from the existing JSON scanner's tokens. Escaped JSON inside strings is colored as a string.
- GitHub Light and GitHub Dark ship as bundled theme files. A theme that fails to load produces a config warning and the bundled default is used.

### Textier app

- The Panel window is built in SwiftUI. It hosts the existing AppKit text view for the Input and the existing AppKit outline view for the JSON tree as embedded views; the Inspector's tabs, lists, parsed views and Action bar are SwiftUI.
- The Panel stays a floating, centered, resizable panel closed by Esc, with a toolbar (the Highlighting toggle), a split with a remembered divider, and the footer for warnings and the Accessibility note.
- Highlighting is a Panel setting, not a domain concept. On: top-level Matches are tinted in their resolved color (for the current appearance), a click without drag copies the Match (raw, or pretty JSON per `copyJSON` for JSON Matches), shows a brief "Copied" and places the cursor; a drag selects text; a double-click on a Match selects it in the Inspector. Off: no tint and no click behaviour. Each capture turns it on; ⌘E toggles it.
- The Action menu in the Input and the JSON Viewer's context menu are removed. Actions live in the Action bar (and the JSON Viewer's node toolbar).
- Inspector ↔ Input selection is two-way: selecting an entry selects its range in the Input and scrolls to it.
- A Match Window shows one entry's Action bar and parsed view, with no tabs. It is opened by "Open in Window" (`open`), Pop Out or ⌘⇧P, and by the escaped-JSON node's open action.
- Keyboard: Tab/Shift-Tab between Input and Inspector, ⌘1–⌘9 for tabs, ↑/↓ in the list, Return runs the first Action, ⌘⇧P pops out, ⌘E toggles Highlighting.
- The menu bar is unchanged.

## Testing Decisions

- As in v1, a good test drives a public TextierCore seam with realistic text and asserts on the returned structure, never on internal helpers. The Laravel/Monolog line is the canonical fixture; add minimal strings only to isolate one rule.
- Detection seam (existing): resolved Match colors from explicit config and from the palette, including User Patterns taking the next unused color.
- Config seam (existing): `color` as single hex and as a light/dark pair, invalid colors warn and fall back; `theme` and `copyJSON` load, default, and warn on bad values; first-launch emission still round-trips.
- Inspection seam (new): on the Monolog line, tab order is datetime, json, url, file path, then Plain Text, with counts 1/1/1/6; nested entries carry "in json 0"; the initial selection is the JSON Match; previews are single-line and truncated; Plain Text entries are the trimmed gaps without punctuation-only pieces; the URL breakdown decodes query parameters in order; datetime conversions for an offset-less datetime (assumed local) and its UTC re-read, a `Z` datetime and 10/13-digit epochs, with a fixed `now` and time zone; file path line/column/exists through a stubbed `fileExists`; with `previous`, tab order is kept, new tabs append before Plain Text, empty tabs drop, and the selection moves to the nearest Match of the same Pattern or falls back to the largest.
- Syntax coloring seam (new): the bundled GitHub themes load; `colorize` on the pretty-printed Monolog JSON gives distinct colors for keys, strings, numbers and literals; ranges are UTF-16 and cover the text without overlaps; a malformed theme is rejected; a user theme overriding the string scope changes string colors.
- Prior art: the v1 suites for detection, the config file, JSON and the JSON tree.
- The Textier app target is tested in-process by `Tests/TextierAppTests`: a real Panel driven with synthetic mouse and key events inside a running `NSApp`, with the pasteboard, browser and editor replaced by recorders. What tests can't see (the global shortcut from another app, real pointer tracking, appearance, clicking SwiftUI controls) stays in a short manual script.
- Tests run with `swift test` (`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test` until `xcode-select` points at Xcode; the app target needs an Xcode toolchain too, for SwiftUI's macros).

## Out of Scope

- Shiki or any JavaScript runtime (ADR-0003); syntax coloring for anything other than JSON.
- Search or filtering in the Inspector or the JSON Viewer.
- New Patterns or detection rules; pairing separate `"file"` and `"line"` JSON keys into one `open-file` target.
- A settings UI; configuration stays file-only.
- Changes to the menu bar, the global shortcut or selection capture.
- Launch at Login, distribution, signing.
- History of past Inputs.

## Further Notes

- The done scenario for v2: select the Monolog line, press ⌃⌥T; the Panel opens with the JSON selected in the Inspector's tree, syntax-colored; the tabs read datetime, json, url (1), file path (6), Plain Text; click the datetime in the Input and paste it; double-click the datetime and see its conversions; step through the six file paths with ↓ and press Return on one to open it in Cursor; pop the JSON out into a Match Window; turn Highlighting off with ⌘E, edit the line, and watch the Inspector update.
- The deployment target stays macOS 15; system materials should degrade gracefully there.
- v1's manual test script (`.scratch/textier-v1/manual-test.txt`) is the starting point for v2's.
